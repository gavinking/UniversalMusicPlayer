import android.app {
    Activity
}
import android.content {
    Context
}
import android.os {
    Bundle
}
import android.support.v4.media {
    MediaMetadata=MediaMetadataCompat
}
import android.support.v4.media.session {
    MediaController=MediaControllerCompat,
    MediaSession=MediaSessionCompat {
        QueueItem
    }
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
        value queue = ArrayList<QueueItem>();
        variable value count = 0;
        for (track in tracks) {
            value hierarchyAwareMediaID
                    = MediaIDHelper.createMediaID(track.description.mediaId, *categories);
            value trackCopy
                    = MediaMetadata.Builder(track)
                    .putString(MediaMetadata.metadataKeyMediaId, hierarchyAwareMediaID)
                    .build();
            value item = QueueItem(trackCopy.description, count++);
            queue.add(item);
        }
        return queue;
    }

    shared static List<QueueItem>? getPlayingQueue(String mediaId, MusicProvider musicProvider) {
        value hierarchy = MediaIDHelper.getHierarchy(mediaId);

        if (exists categoryType = hierarchy[0],
            exists categoryValue = hierarchy[1]) {
            suppressWarnings ("caseNotDisjoint")
            value tracks
                    = switch (categoryType)
                    case (mediaIdMusicsByGenre) musicProvider.getMusicsByGenre(categoryValue)
                    case (mediaIdMusicsBySearch) musicProvider.searchMusicBySongTitle(categoryValue)
                    else null;

            return if (exists tracks) then convertToQueue(tracks, categoryType, categoryValue) else null;
        }
        else {
            return null;
        }
    }

    shared static List<QueueItem> getRandomQueue(MusicProvider musicProvider) {
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

    shared static List<QueueItem> getPlayingQueueFromSearch(
            String query, Bundle queryParams, MusicProvider musicProvider) {
//        LogHelper.d(tag, "Creating playing queue for musics from search: ", query, " params=", queryParams);
        value params = VoiceSearchParams(query, queryParams);
//        LogHelper.d(tag, "VoiceSearchParams: ", params);
        if (params.isAny) {
            return getRandomQueue(musicProvider);
        }

        value result
                = if (params.isUnstructured)
                    then musicProvider.searchMusicBySongTitle(query)
                else if (params.isAlbumFocus)
                    then musicProvider.searchMusicByAlbum(params.album)
                else if (params.isGenreFocus)
                    then musicProvider.getMusicsByGenre(params.genre)
                else if (params.isArtistFocus)
                    then musicProvider.searchMusicByArtist(params.artist)
                else if (params.isSongFocus)
                    then musicProvider.searchMusicBySongTitle(params.song)
                else musicProvider.searchMusicBySongTitle(query);

        value finalResult
                = result.iterator().hasNext()
                then result else
                musicProvider.searchMusicBySongTitle(query);

        return convertToQueue(finalResult, mediaIdMusicsBySearch, query);
    }

    shared static Integer getMusicIndexOnQueueByMediaId(List<QueueItem> queue, String mediaId)
            => (0:queue.size()).find((index) => (queue.get(index).description.mediaId else "") == mediaId) else -1;

    shared static Integer getMusicIndexOnQueueByQueueId(List<QueueItem> queue, Integer queueId)
            => (0:queue.size()).find((index) => queue.get(index).queueId == queueId) else -1;

    shared static Boolean isIndexPlayable(Integer index, List<QueueItem> queue)
            => 0 <= index < queue.size();

    shared static Boolean equalQueues(List<QueueItem> list1, List<QueueItem> list2)
            => list1.size() == list2.size()
            && (0:list1.size()).every((index) {
                value item1 = list1.get(index);
                value item2 = list2.get(index);
                return item1.queueId == item2.queueId
                    && !MediaIDHelper.equalIds(item1.description.mediaId,
                                               item2.description.mediaId);
            });

    shared static Boolean isQueueItemPlaying(Context context, QueueItem queueItem) {
        if (is Activity context,
            exists controller = MediaController.getMediaController(context),
            exists state = controller.playbackState) {
            value currentPlayingQueueId = state.activeQueueItemId;
            value itemMusicId = MediaIDHelper.extractMusicIDFromMediaID(queueItem.description.mediaId);
            if (queueItem.queueId == currentPlayingQueueId,
                exists currentPlayingMediaId = controller.metadata.description.mediaId,
                MediaIDHelper.equalIds(currentPlayingMediaId, itemMusicId)) {
                return true;
            }
        }
        return false;
    }

    shared new () {}

}
