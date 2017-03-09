import android.content {
    Context
}
import android.media {
    MediaMetadata
}
import android.media.session {
    MediaSession
}
import android.os {
    Bundle
}
import android.support.v4.app {
    FragmentActivity
}
import android.text {
    TextUtils
}

import com.example.android.uamp {
    VoiceSearchParams
}
import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.utils {
    MediaIDHelper {
        mediaIdMusicsByGenre,
        mediaIdMusicsBySearch
    }
}

import java.lang {
    Iterable
}
import java.util {
    ArrayList,
    List
}

shared class QueueHelper {

//    static value tag = LogHelper.makeLogTag(`QueueHelper`);

    static value randomQueueSize = 10;

    static function convertToQueue(Iterable<MediaMetadata> tracks, String* categories) {
        value queue = ArrayList<MediaSession.QueueItem>();
        variable value count = 0;
        for (track in tracks) {
            value hierarchyAwareMediaID
                    = MediaIDHelper.createMediaID(track.description.mediaId, *categories);
            value trackCopy
                    = MediaMetadata.Builder(track)
                    .putString(MediaMetadata.metadataKeyMediaId, hierarchyAwareMediaID)
                    .build();
            value item = MediaSession.QueueItem(trackCopy.description, count++);
            queue.add(item);
        }
        return queue;
    }

    shared static List<MediaSession.QueueItem>? getPlayingQueue(String mediaId, MusicProvider musicProvider) {
        value hierarchy = [ for (str in MediaIDHelper.getHierarchy(mediaId)) str.string ];
        if (hierarchy.size != 2) {
//            LogHelper.e(tag, "Could not build a playing queue for this mediaId: ", mediaId);
            return null;
        }

        assert (exists categoryType = hierarchy[0],
                exists categoryValue = hierarchy[1]);
//        LogHelper.d(tag, "Creating playing queue for ", categoryType, ",  ", categoryValue);

        Iterable<MediaMetadata>? tracks;
        if (categoryType == mediaIdMusicsByGenre) {
            tracks = musicProvider.getMusicsByGenre(categoryValue);
        } else if (categoryType == mediaIdMusicsBySearch) {
            tracks = musicProvider.searchMusicBySongTitle(categoryValue);
        }
        else {
            tracks = null;
        }
        if (exists tracks) {
            return convertToQueue(tracks, categoryType, categoryValue);
        }
        else {
//            LogHelper.e(tag, "Unrecognized category type: ", categoryType, " for media ", mediaId);
            return null;
        }
    }

    shared static List<MediaSession.QueueItem> getRandomQueue(MusicProvider musicProvider) {
        value result = ArrayList<MediaMetadata>(randomQueueSize);
        value shuffled = musicProvider.shuffledMusic;
        for (metadata in shuffled) {
            if (result.size() == randomQueueSize) {
                break;
            }
            result.add(metadata);
        }
//        LogHelper.d(tag, "getRandomQueue: result.size=", result.size());
        return convertToQueue(result, mediaIdMusicsBySearch, "random");
    }

    shared static List<MediaSession.QueueItem> getPlayingQueueFromSearch(
            String query, Bundle queryParams, MusicProvider musicProvider) {
//        LogHelper.d(tag, "Creating playing queue for musics from search: ", query, " params=", queryParams);
        value params = VoiceSearchParams(query, queryParams);
//        LogHelper.d(tag, "VoiceSearchParams: ", params);
        if (params.isAny) {
            return getRandomQueue(musicProvider);
        }

        Iterable<MediaMetadata> result;
        if (params.isUnstructured) {
            result = musicProvider.searchMusicBySongTitle(query);
        } else if (params.isAlbumFocus) {
            result = musicProvider.searchMusicByAlbum(params.album);
        } else if (params.isGenreFocus) {
            result = musicProvider.getMusicsByGenre(params.genre);
        } else if (params.isArtistFocus) {
            result = musicProvider.searchMusicByArtist(params.artist);
        } else if (params.isSongFocus) {
            result = musicProvider.searchMusicBySongTitle(params.song);
        } else {
            result = musicProvider.searchMusicBySongTitle(query);
        }
        value finalResult
                = result.iterator().hasNext()
                then result else
                musicProvider.searchMusicBySongTitle(query);

        return convertToQueue(finalResult, mediaIdMusicsBySearch, query);
    }

    shared static Integer getMusicIndexOnQueueByMediaId(Iterable<MediaSession.QueueItem> queue, String mediaId) {
        variable Integer index = 0;
        for (MediaSession.QueueItem item in queue) {
            if (mediaId.equals(item.description.mediaId)) {
                return index;
            }
            index++;
        }
        return -1;
    }

    shared static Integer getMusicIndexOnQueueByQueueId(Iterable<MediaSession.QueueItem> queue, Integer queueId) {
        variable Integer index = 0;
        for (MediaSession.QueueItem item in queue) {
            if (queueId == item.queueId) {
                return index;
            }
            index++;
        }
        return -1;
    }

    shared static Boolean isIndexPlayable(Integer index, List<MediaSession.QueueItem> queue)
            => index>=0 && index<queue.size();

    shared static Boolean equalQueues(List<MediaSession.QueueItem> list1, List<MediaSession.QueueItem> list2) {
        if (list1.size() != list2.size()) {
            return false;
        }
        variable Integer i = 0;
        while (i<list1.size()) {
            if (list1.get(i).queueId != list2.get(i).queueId) {
                return false;
            }
            if (!TextUtils.equals(list1.get(i).description.mediaId, list2.get(i).description.mediaId)) {
                return false;
            }
            i++;
        }
        return true;
    }

    shared static Boolean isQueueItemPlaying(Context context, MediaSession.QueueItem queueItem) {
        if (is FragmentActivity context,
            exists controller = context.mediaController,
            exists state = controller.playbackState) {
            value currentPlayingQueueId = state.activeQueueItemId;
            value itemMusicId = MediaIDHelper.extractMusicIDFromMediaID(queueItem.description.mediaId);
            if (queueItem.queueId == currentPlayingQueueId,
                exists currentPlayingMediaId = controller.metadata.description.mediaId,
                TextUtils.equals(currentPlayingMediaId, itemMusicId)) {
                return true;
            }
        }
        return false;
    }

    shared new () {}

}
