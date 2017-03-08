import android.content.res {
    Resources
}
import android.graphics {
    Bitmap
}
import android.net {
    Uri
}
import android.os {
    AsyncTask
}
import android.media {
    MediaDescription,
    MediaMetadata
}
import android.media.browse {
    MediaBrowser
}
import android.text {
    TextUtils
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    LogHelper,
    MediaIDHelper {
        mediaIdMusicsByGenre,
        mediaIdRoot,
        createMediaID
    }
}

import java.io {
    BufferedReader,
    InputStreamReader
}
import java.lang {
    JBoolean=Boolean,
    JIterable=Iterable
}
import java.net {
    URL
}
import java.util {
    ArrayList,
    Collections,
    Iterator,
    List,
    Set
}
import java.util.concurrent {
    ConcurrentHashMap,
    ConcurrentMap
}

import org.json {
    JSONObject,
    JSONException
}


shared interface MusicProviderSource {
    shared formal Iterator<MediaMetadata> iterator() ;
}

shared String customMetadataTrackSource = "__SOURCE__";

shared class RemoteJSONSource satisfies MusicProviderSource {

    static value tag = LogHelper.makeLogTag(`RemoteJSONSource`);

    static value catalogUrl = "http://storage.googleapis.com/automotive-media/music.json";
    static value jsonMusic = "music";
    static value jsonTitle = "title";
    static value jsonAlbum = "album";
    static value jsonArtist = "artist";
    static value jsonGenre = "genre";
    static value jsonSource = "source";
    static value jsonImage = "image";
    static value jsonTrackNumber = "trackNumber";
    static value jsonTotalTrackCount = "totalTrackCount";
    static value jsonDuration = "duration";

    shared new () {}

    function buildFromJSON(JSONObject json, String basePath) {
        String title = json.getString(jsonTitle);
        String album = json.getString(jsonAlbum);
        String artist = json.getString(jsonArtist);
        String genre = json.getString(jsonGenre);
        variable String source = json.getString(jsonSource);
        variable String iconUrl = json.getString(jsonImage);
        Integer trackNumber = json.getInt(jsonTrackNumber);
        Integer totalTrackCount = json.getInt(jsonTotalTrackCount);
        Integer duration = json.getInt(jsonDuration) * 1000;
        LogHelper.d(tag, "Found music track: ", json);
        if (!source.startsWith("http")) {
            source = basePath + source;
        }
        if (!iconUrl.startsWith("http")) {
            iconUrl = basePath + iconUrl;
        }
        return MediaMetadata.Builder()
            .putString(MediaMetadata.metadataKeyMediaId, source.hash.string)
            .putString(customMetadataTrackSource, source)
            .putString(MediaMetadata.metadataKeyAlbum, album)
            .putString(MediaMetadata.metadataKeyArtist, artist)
            .putLong(MediaMetadata.metadataKeyDuration, duration)
            .putString(MediaMetadata.metadataKeyGenre, genre)
            .putString(MediaMetadata.metadataKeyAlbumArtUri, iconUrl)
            .putString(MediaMetadata.metadataKeyTitle, title)
            .putLong(MediaMetadata.metadataKeyTrackNumber, trackNumber)
            .putLong(MediaMetadata.metadataKeyNumTracks, totalTrackCount)
            .build();
    }

    function fetchJSONFromUrl(String urlString) {
        try {
            value urlConnection = URL(urlString).openConnection();
            try (reader = BufferedReader(InputStreamReader(urlConnection.inputStream, "iso-8859-1"))) {
                value sb = StringBuilder();
                while (exists line = reader.readLine()) {
                    sb.append(line);
                }
                return JSONObject(sb.string);
            }
        }
        catch (JSONException e) {
            throw e;
        }
        catch (e) {
            LogHelper.e(tag, "Failed to parse the json for media list", e);
            return null;
        }
    }

    shared actual Iterator<MediaMetadata> iterator() {
//        try {
        value slashPos = catalogUrl.lastIndexOf("/");
        value path = catalogUrl.substring(0, slashPos + 1);
        value tracks = ArrayList<MediaMetadata>();
        if (exists jsonObj = fetchJSONFromUrl(catalogUrl),
            exists jsonTracks = jsonObj.getJSONArray(jsonMusic)) {
            for (j in 0:jsonTracks.length()) {
                tracks.add(buildFromJSON(jsonTracks.getJSONObject(j), path));
            }
        }
        return tracks.iterator();
//        }
//        catch (JSONException e) {
//            LogHelper.e(tag, e, "Could not retrieve music list");
//            throw Exception("Could not retrieve music list", e);
//        }
    }

}

class State
        of nonInitialized
         | initializing
         | initialized {
    shared actual String string;
    shared new nonInitialized {
        string = "NON_INITIALIZED";
    }
    shared new initializing {
        string = "INITIALIZING";
    }
    shared new initialized {
        string = "INITIALIZED";
    }
}

shared interface Callback {
    shared formal void onMusicCatalogReady(Boolean success);
}

shared class MusicProvider {

    static value tag = LogHelper.makeLogTag(`MusicProvider`);

    MusicProviderSource mSource;

    ConcurrentMap<String,List<MediaMetadata>> mMusicListByGenre;
    ConcurrentMap<String,MutableMediaMetadata> mMusicListById;
    Set<String> mFavoriteTracks;

    variable State mCurrentState = State.nonInitialized;

    shared new (MusicProviderSource source = RemoteJSONSource()) {
        mSource = source;
        mMusicListByGenre = ConcurrentHashMap<String,List<MediaMetadata>>();
        mMusicListById = ConcurrentHashMap<String,MutableMediaMetadata>();
        mFavoriteTracks = Collections.newSetFromMap(ConcurrentHashMap<String,JBoolean>());
    }

    shared JIterable<String> genres
            => if (mCurrentState != State.initialized)
            then Collections.emptyList<String>()
            else mMusicListByGenre.keySet();

    shared JIterable<MediaMetadata> shuffledMusic {
        if (mCurrentState != State.initialized) {
            return Collections.emptyList<MediaMetadata>();
        }
        value shuffled = ArrayList<MediaMetadata>(mMusicListById.size());
        for (mutableMetadata in mMusicListById.values()) {
            shuffled.add(mutableMetadata.metadata);
        }
        Collections.shuffle(shuffled);
        return shuffled;
    }

    shared JIterable<MediaMetadata> getMusicsByGenre(String genre)
            => if (mCurrentState != State.initialized
                || !mMusicListByGenre.containsKey(genre))
            then Collections.emptyList<MediaMetadata>()
            else mMusicListByGenre.get(genre);

    function searchMusic(String metadataField, String query) {
        if (mCurrentState != State.initialized) {
            return Collections.emptyList<MediaMetadata>();
        }
        value result = ArrayList<MediaMetadata>();
        for (track in mMusicListById.values()) {
            if (query.lowercased in track.metadata.getString(metadataField).string) {
                result.add(track.metadata);
            }
        }
        return result;
    }

    shared JIterable<MediaMetadata> searchMusicBySongTitle(String query)
            => searchMusic(MediaMetadata.metadataKeyTitle, query);

    shared JIterable<MediaMetadata> searchMusicByAlbum(String query)
            => searchMusic(MediaMetadata.metadataKeyAlbum, query);

    shared JIterable<MediaMetadata> searchMusicByArtist(String query)
            => searchMusic(MediaMetadata.metadataKeyArtist, query);

    shared MediaMetadata? getMusic(String musicId)
            => mMusicListById.containsKey(musicId)
            then mMusicListById.get(musicId).metadata;

    shared void updateMusicArt(String musicId, Bitmap albumArt, Bitmap icon) {
        value metadata = MediaMetadata.Builder(getMusic(musicId))
            .putBitmap(MediaMetadata.metadataKeyAlbumArt, albumArt)
            .putBitmap(MediaMetadata.metadataKeyDisplayIcon, icon)
            .build();
        "Unexpected error: Inconsistent data structures in MusicProvider"
        assert (exists mutableMetadata = mMusicListById.get(musicId));
        mutableMetadata.metadata = metadata;
    }

    shared void setFavorite(String musicId, Boolean favorite) {
        if (favorite) {
            mFavoriteTracks.add(musicId);
        } else {
            mFavoriteTracks.remove(musicId);
        }
    }

    shared Boolean initialized
            => mCurrentState == State.initialized;

    shared Boolean isFavorite(String musicId)
            => mFavoriteTracks.contains(musicId);

    shared void retrieveMediaAsync(Callback? callback) {
        LogHelper.d(tag, "retrieveMediaAsync called");
        if (mCurrentState == State.initialized) {
            if (exists callback) {
                callback.onMusicCatalogReady(true);
            }
            return;
        }
        object extends AsyncTask<Anything,Anything,State>() {
            shared actual State doInBackground(Anything* params) {
                retrieveMedia();
                return mCurrentState;
            }
            shared actual void onPostExecute(State current) {
                if (exists callback) {
                    callback.onMusicCatalogReady(current == State.initialized);
                }
            }

        }.execute();
    }

    void buildListsByGenre() {
        value newMusicListByGenre = ConcurrentHashMap<String,List<MediaMetadata>>();
        for (m in mMusicListById.values()) {
            value genre = m.metadata.getString(MediaMetadata.metadataKeyGenre);
            if (exists list = newMusicListByGenre[genre]) {
                list.add(m.metadata);
            }
            else {
                value list = ArrayList<MediaMetadata>();
                newMusicListByGenre.put(genre, list);
                list.add(m.metadata);
            }
        }
        mMusicListByGenre.clear();
        mMusicListByGenre.putAll(newMusicListByGenre);
    }

    void retrieveMedia() {
        try {
            if (mCurrentState == State.nonInitialized) {
                mCurrentState = State.initializing;
                value tracks = mSource.iterator();
                while (tracks.hasNext()) {
                    value item = tracks.next();
                    value musicId = item.getString(MediaMetadata.metadataKeyMediaId);
                    mMusicListById.put(musicId, MutableMediaMetadata(musicId, item));
                }
                buildListsByGenre();
                mCurrentState = State.initialized;
            }
        }
        finally {
            if (mCurrentState != State.initialized) {
                mCurrentState = State.nonInitialized;
            }
        }
    }

    function createBrowsableMediaItemForRoot(Resources resources) {
        value description = MediaDescription.Builder()
            .setMediaId(mediaIdMusicsByGenre)
            .setTitle(resources.getString(R.String.browse_genres))
            .setSubtitle(resources.getString(R.String.browse_genre_subtitle))
            .setIconUri(Uri.parse("android.resource://com.example.android.uamp/drawable/ic_by_genre"))
            .build();
        return MediaBrowser.MediaItem(description, MediaBrowser.MediaItem.flagBrowsable);
    }

    function createBrowsableMediaItemForGenre(String genre, Resources resources) {
        value description = MediaDescription.Builder()
            .setMediaId(createMediaID(null, mediaIdMusicsByGenre, genre))
            .setTitle(genre)
            .setSubtitle(resources.getString(R.String.browse_musics_by_genre_subtitle, genre))
            .build();
        return MediaBrowser.MediaItem(description, MediaBrowser.MediaItem.flagBrowsable);
    }

    function createMediaItem(MediaMetadata metadata) {
        value genre = metadata.getString(MediaMetadata.metadataKeyGenre);
        value hierarchyAwareMediaID
                = MediaIDHelper.createMediaID(metadata.description.mediaId, mediaIdMusicsByGenre, genre);
        value copy = MediaMetadata.Builder(metadata)
            .putString(MediaMetadata.metadataKeyMediaId, hierarchyAwareMediaID)
            .build();
        return MediaBrowser.MediaItem(copy.description, MediaBrowser.MediaItem.flagPlayable);
    }

    shared List<MediaBrowser.MediaItem> getChildren(String mediaId, Resources resources) {
        value mediaItems = ArrayList<MediaBrowser.MediaItem>();
        if (!MediaIDHelper.isBrowseable(mediaId)) {
            return mediaItems;
        }
        if (mediaIdRoot==mediaId) {
            mediaItems.add(createBrowsableMediaItemForRoot(resources));
        } else if (mediaIdMusicsByGenre.equals(mediaId)) {
            for (genre in genres) {
                mediaItems.add(createBrowsableMediaItemForGenre(genre, resources));
            }
        } else if (mediaId.startsWith(mediaIdMusicsByGenre)) {
            value genre = MediaIDHelper.getHierarchy(mediaId).get(1);
            for (metadata in getMusicsByGenre(genre.string)) {
                mediaItems.add(createMediaItem(metadata));
            }
        } else {
            LogHelper.w(tag, "Skipping unmatched mediaId: ", mediaId);
        }
        return mediaItems;
    }

}

shared class MutableMediaMetadata {

    shared variable MediaMetadata metadata;

    shared String trackId;

    shared new (String trackId, MediaMetadata metadata) {
        this.metadata = metadata;
        this.trackId = trackId;
    }

    equals(Object that)
            => if (is MutableMediaMetadata that)
            then this===that
              || TextUtils.equals(trackId, that.trackId)
            else false;

    hash => trackId.hash;

}
