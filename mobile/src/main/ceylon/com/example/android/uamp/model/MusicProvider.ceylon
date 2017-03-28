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
import android.support.v4.media {
    MediaMetadata=MediaMetadataCompat,
    MediaDescription=MediaDescriptionCompat,
    MediaBrowser=MediaBrowserCompat {
        MediaItem
    }
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    MediaIDHelper {
        mediaIdMusicsByGenre,
        mediaIdRoot,
        createMediaID
    }
}

import java.lang {
    JBoolean=Boolean,
    Iterable
}
import java.util {
    List,
    ArrayList,
    Collections,
    Map,
    Set
}
import java.util.concurrent {
    ConcurrentHashMap
}

shared String customMetadataTrackSource = "__SOURCE__";

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

shared class MusicProvider({MediaMetadata*} source = RemoteJSONSource()) {

//    static value tag = LogHelper.makeLogTag(`MusicProvider`);

    variable State currentState = State.nonInitialized;

    //declare explicit type here because of bug in Android's ConcurrentHashMap
    Map<String,List<MediaMetadata>> musicListByGenre
            = ConcurrentHashMap<String,List<MediaMetadata>>();
    Map<String,MutableMediaMetadata> musicListById
            = ConcurrentHashMap<String,MutableMediaMetadata>();
    Set<String> favoriteTracks
            = Collections.newSetFromMap(ConcurrentHashMap<String,JBoolean>());

    shared Iterable<String> genres
            => if (currentState != State.initialized)
            then Collections.emptyList<String>()
            else musicListByGenre.keySet();

    shared Iterable<MediaMetadata> shuffledMusic {
        if (currentState != State.initialized) {
            return Collections.emptyList<MediaMetadata>();
        }
        value shuffled = ArrayList<MediaMetadata>(musicListById.size());
        for (mutableMetadata in musicListById.values()) {
            shuffled.add(mutableMetadata.metadata);
        }
        Collections.shuffle(shuffled);
        return shuffled;
    }

    shared Iterable<MediaMetadata> getMusicsByGenre(String genre)
            => if (currentState != State.initialized
                || !musicListByGenre.containsKey(genre))
            then Collections.emptyList<MediaMetadata>()
            else musicListByGenre.get(genre);

    function searchMusic(String metadataField, String query) {
        if (currentState != State.initialized) {
            return Collections.emptyList<MediaMetadata>();
        }
        value result = ArrayList<MediaMetadata>();
        for (track in musicListById.values()) {
            if (query.lowercased in track.metadata.getString(metadataField)) {
                result.add(track.metadata);
            }
        }
        return result;
    }

    shared Iterable<MediaMetadata> searchMusicBySongTitle(String query)
            => searchMusic(MediaMetadata.metadataKeyTitle, query);

    shared Iterable<MediaMetadata> searchMusicByAlbum(String query)
            => searchMusic(MediaMetadata.metadataKeyAlbum, query);

    shared Iterable<MediaMetadata> searchMusicByArtist(String query)
            => searchMusic(MediaMetadata.metadataKeyArtist, query);

    shared MediaMetadata? getMusic(String musicId)
            => musicListById.containsKey(musicId)
            then musicListById.get(musicId).metadata;

    shared void updateMusicArt(String musicId, Bitmap? albumArt, Bitmap? icon) {
        value metadata
                = MediaMetadata.Builder(getMusic(musicId))
                .putBitmap(MediaMetadata.metadataKeyAlbumArt, albumArt)
                .putBitmap(MediaMetadata.metadataKeyDisplayIcon, icon)
                .build();
        "Unexpected error: Inconsistent data structures in MusicProvider"
        assert (exists mutableMetadata = musicListById.get(musicId));
        mutableMetadata.metadata = metadata;
    }

    shared void setFavorite(String musicId, Boolean favorite) {
        if (favorite) {
            favoriteTracks.add(musicId);
        } else {
            favoriteTracks.remove(musicId);
        }
    }

    shared Boolean initialized
            => currentState == State.initialized;

    shared Boolean isFavorite(String musicId)
            => musicId in favoriteTracks;

    shared void retrieveMediaAsync(void onMusicCatalogReady(Boolean success)) {
//        LogHelper.d(tag, "retrieveMediaAsync called");
        if (currentState == State.initialized) {
//            if (exists callback) {
            onMusicCatalogReady(true);
//            }
        }
        else {
            object extends AsyncTask<Anything,Anything,State>() {
                shared actual State doInBackground(Anything*params) {
                    retrieveMedia();
                    return currentState;
                }
                shared actual void onPostExecute(State current) {
                    //                if (exists callback) {
                    onMusicCatalogReady(current == State.initialized);
                    //                }
                }
            }.execute();
        }
    }

    void buildListsByGenre() {
        value newMusicListByGenre = ConcurrentHashMap<String,List<MediaMetadata>>();
        for (m in musicListById.values()) {
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
        musicListByGenre.clear();
        musicListByGenre.putAll(newMusicListByGenre);
    }

    void retrieveMedia() {
        try {
            if (currentState == State.nonInitialized) {
                currentState = State.initializing;
                for (item in source) {
                    value musicId = item.getString(MediaMetadata.metadataKeyMediaId);
                    musicListById.put(musicId, MutableMediaMetadata(musicId, item));
                }
                buildListsByGenre();
                currentState = State.initialized;
            }
        }
        finally {
            if (currentState != State.initialized) {
                currentState = State.nonInitialized;
            }
        }
    }

    function createBrowsableMediaItemForRoot(Resources resources) {
        value description
                = MediaDescription.Builder()
                .setMediaId(mediaIdMusicsByGenre)
                .setTitle(resources.getString(R.String.browse_genres))
                .setSubtitle(resources.getString(R.String.browse_genre_subtitle))
                .setIconUri(Uri.parse("android.resource://com.example.android.uamp/drawable/ic_by_genre"))
                .build();
        return MediaItem(description, MediaItem.flagBrowsable);
    }

    function createBrowsableMediaItemForGenre(String genre, Resources resources) {
        value description
                = MediaDescription.Builder()
                .setMediaId(createMediaID(null, mediaIdMusicsByGenre, genre))
                .setTitle(genre)
                .setSubtitle(resources.getString(R.String.browse_musics_by_genre_subtitle, genre))
                .build();
        return MediaItem(description, MediaItem.flagBrowsable);
    }

    function createMediaItem(MediaMetadata metadata) {
        value genre = metadata.getString(MediaMetadata.metadataKeyGenre);
        value hierarchyAwareMediaID
                = MediaIDHelper.createMediaID(metadata.description.mediaId, mediaIdMusicsByGenre, genre);
        value copy
                = MediaMetadata.Builder(metadata)
                .putString(MediaMetadata.metadataKeyMediaId, hierarchyAwareMediaID)
                .build();
        return MediaItem(copy.description, MediaItem.flagPlayable);
    }

    shared List<MediaItem> getChildren(String mediaId, Resources resources) {
        value mediaItems = ArrayList<MediaItem>();
        if (MediaIDHelper.isBrowseable(mediaId)) {
            switch (mediaId)
            else case (mediaIdRoot) {
                mediaItems.add(createBrowsableMediaItemForRoot(resources));
            }
            else case (mediaIdMusicsByGenre) {
                for (genre in genres) {
                    mediaItems.add(createBrowsableMediaItemForGenre(genre, resources));
                }
            }
            else if (mediaId.startsWith(mediaIdMusicsByGenre)) {
                if (exists genre = MediaIDHelper.getHierarchy(mediaId)[1]) {
                    for (metadata in getMusicsByGenre(genre)) {
                        mediaItems.add(createMediaItem(metadata));
                    }
                }
            }
            else {
                //LogHelper.w(tag, "Skipping unmatched mediaId: ", mediaId);
            }
        }
        return mediaItems;
    }

}
