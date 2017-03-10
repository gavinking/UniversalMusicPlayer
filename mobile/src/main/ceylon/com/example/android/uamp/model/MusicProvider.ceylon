import android.content.res {
    Resources
}
import android.graphics {
    Bitmap
}
import android.media {
    MediaMetadata,
    MediaDescription
}
import android.media.browse {
    MediaBrowser
}
import android.net {
    Uri
}
import android.os {
    AsyncTask
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
    JIterable=Iterable
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

shared interface MusicProviderSource satisfies JIterable<MediaMetadata> {}

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

shared class MusicProvider(MusicProviderSource source = RemoteJSONSource()) {

//    static value tag = LogHelper.makeLogTag(`MusicProvider`);

    variable State mCurrentState = State.nonInitialized;

    Map<String,List<MediaMetadata>> musicListByGenre = ConcurrentHashMap<String,List<MediaMetadata>>();
    Map<String,MutableMediaMetadata> musicListById = ConcurrentHashMap<String,MutableMediaMetadata>();
    Set<String> favoriteTracks = Collections.newSetFromMap(ConcurrentHashMap<String,JBoolean>());

    shared JIterable<String> genres
            => if (mCurrentState != State.initialized)
            then Collections.emptyList<String>()
            else musicListByGenre.keySet();

    shared JIterable<MediaMetadata> shuffledMusic {
        if (mCurrentState != State.initialized) {
            return Collections.emptyList<MediaMetadata>();
        }
        value shuffled = ArrayList<MediaMetadata>(musicListById.size());
        for (mutableMetadata in musicListById.values()) {
            shuffled.add(mutableMetadata.metadata);
        }
        Collections.shuffle(shuffled);
        return shuffled;
    }

    shared JIterable<MediaMetadata> getMusicsByGenre(String genre)
            => if (mCurrentState != State.initialized
                || !musicListByGenre.containsKey(genre))
            then Collections.emptyList<MediaMetadata>()
            else musicListByGenre.get(genre);

    function searchMusic(String metadataField, String query) {
        if (mCurrentState != State.initialized) {
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

    shared JIterable<MediaMetadata> searchMusicBySongTitle(String query)
            => searchMusic(MediaMetadata.metadataKeyTitle, query);

    shared JIterable<MediaMetadata> searchMusicByAlbum(String query)
            => searchMusic(MediaMetadata.metadataKeyAlbum, query);

    shared JIterable<MediaMetadata> searchMusicByArtist(String query)
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
            => mCurrentState == State.initialized;

    shared Boolean isFavorite(String musicId)
            => musicId in favoriteTracks;

    shared void retrieveMediaAsync(void onMusicCatalogReady(Boolean success)) {
//        LogHelper.d(tag, "retrieveMediaAsync called");
        if (mCurrentState == State.initialized) {
//            if (exists callback) {
            onMusicCatalogReady(true);
//            }
            return;
        }
        object extends AsyncTask<Anything,Anything,State>() {
            shared actual State doInBackground(Anything* params) {
                retrieveMedia();
                return mCurrentState;
            }
            shared actual void onPostExecute(State current) {
//                if (exists callback) {
                onMusicCatalogReady(current == State.initialized);
//                }
            }

        }.execute();
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
            if (mCurrentState == State.nonInitialized) {
                mCurrentState = State.initializing;
                for (item in source) {
                    value musicId = item.getString(MediaMetadata.metadataKeyMediaId);
                    musicListById.put(musicId, MutableMediaMetadata(musicId, item));
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
            assert (exists genre = MediaIDHelper.getHierarchy(mediaId)[1]);
            for (metadata in getMusicsByGenre(genre)) {
                mediaItems.add(createMediaItem(metadata));
            }
        } else {
//            LogHelper.w(tag, "Skipping unmatched mediaId: ", mediaId);
        }
        return mediaItems;
    }

}