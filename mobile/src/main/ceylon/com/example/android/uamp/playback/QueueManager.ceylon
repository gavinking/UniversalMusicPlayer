import android.content.res {
    Resources
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

import com.example.android.uamp {
    R,
    AlbumArtCache
}
import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.utils {
    QueueHelper,
    MediaIDHelper
}

import java.util {
    List,
    ArrayList,
    Collections
}

shared class QueueManager(
        MusicProvider musicProvider,
        Resources resources,
        MetadataUpdateListener listener) {

//    value tag = LogHelper.makeLogTag(`QueueManager`);

    variable value playingQueue
            = Collections.synchronizedList(ArrayList<MediaSession.QueueItem>());
    variable value currentIndex = 0;

    shared Boolean isSameBrowsingCategory(String mediaId) {
        if (exists current = currentMusic,
            exists id = current.description.mediaId) {
            value newBrowseHierarchy = MediaIDHelper.getHierarchy(mediaId);
            value currentBrowseHierarchy = MediaIDHelper.getHierarchy(id);
            return newBrowseHierarchy == currentBrowseHierarchy;
        }
        else {
            return false;
        }
    }

    void setCurrentQueueIndex(Integer index) {
        if (0 <= index < playingQueue.size()) {
            currentIndex = index;
            listener.onCurrentQueueIndexUpdated(currentIndex);
        }
    }

    shared Boolean setCurrentQueueItemByQueueId(Integer queueId) {
        value index = QueueHelper.getMusicIndexOnQueueByQueueId(playingQueue, queueId);
        setCurrentQueueIndex(index);
        return index>=0;
    }

    shared Boolean setCurrentQueueItemByMediaId(String mediaId) {
        value index = QueueHelper.getMusicIndexOnQueueByMediaId(playingQueue, mediaId);
        setCurrentQueueIndex(index);
        return index>=0;
    }

    shared Boolean skipQueuePosition(Integer amount) {
        variable Integer index = currentIndex + amount;
        if (index<0) {
            index = 0;
        } else {
            index %= playingQueue.size();
        }
        if (!QueueHelper.isIndexPlayable(index, playingQueue)) {
//            LogHelper.e(tag, "Cannot increment queue index by ", amount, ". Current=", mCurrentIndex, " queue length=", mPlayingQueue.size());
            return false;
        }
        currentIndex = index;
        return true;
    }

    shared Boolean setQueueFromSearch(String query, Bundle extras) {
        value queue = QueueHelper.getPlayingQueueFromSearch(query, extras, musicProvider);
        setCurrentQueue(resources.getString(R.String.search_queue_title), queue);
        updateMetadata();
        return !queue.empty;
    }

    shared void setRandomQueue() {
        value queue = QueueHelper.getRandomQueue(musicProvider);
        setCurrentQueue(resources.getString(R.String.random_queue_title), queue);
        updateMetadata();
    }

    shared void setQueueFromMusic(String mediaId) {
//        LogHelper.d(tag, "setQueueFromMusic", mediaId);
        value canReuseQueue
                = isSameBrowsingCategory(mediaId)
                && setCurrentQueueItemByMediaId(mediaId);
        if (!canReuseQueue) {
            value queueTitle
                    = resources.getString(R.String.browse_musics_by_genre_subtitle,
                MediaIDHelper.extractBrowseCategoryValueFromMediaID(mediaId));
            setCurrentQueue(queueTitle, QueueHelper.getPlayingQueue(mediaId, musicProvider), mediaId);
        }
        updateMetadata();
    }

    shared MediaSession.QueueItem? currentMusic
            => QueueHelper.isIndexPlayable(currentIndex, playingQueue)
            then playingQueue.get(currentIndex);

    shared Integer currentQueueSize => playingQueue?.size() else 0;

    void setCurrentQueue(String title,
            List<MediaSession.QueueItem>? newQueue,
            String? initialMediaId = null) {
        playingQueue = newQueue;
        value index
                = if (exists initialMediaId)
                then QueueHelper.getMusicIndexOnQueueByMediaId(playingQueue, initialMediaId)
                else 0;
        currentIndex = largest(index, 0);
        listener.onQueueUpdated(title, newQueue);
    }

    shared void updateMetadata() {
        if (exists currentMusic = this.currentMusic,
            exists mediaId = currentMusic.description.mediaId,
            exists musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId),
            exists metadata = musicProvider.getMusic(musicId)) {

            listener.onMetadataChanged(metadata);
            if (!metadata.description.iconBitmap exists, metadata.description.iconUri exists) {
                value albumUri = metadata.description.iconUri?.string;
                AlbumArtCache.instance.fetch(albumUri, (artUrl, bitmap, icon) {
                    musicProvider.updateMusicArt(musicId, bitmap, icon);
                    if (exists currentMusic = this.currentMusic,
                        exists mediaId = currentMusic.description.mediaId,
                        exists currentPlayingId = MediaIDHelper.extractMusicIDFromMediaID(mediaId),
                        musicId == currentPlayingId,
                        exists music = musicProvider.getMusic(currentPlayingId)) {
                        listener.onMetadataChanged(music);
                    }
                });
            }
        }
        else {
            listener.onMetadataRetrieveError();
        }
    }

}

shared interface MetadataUpdateListener {
    shared formal void onMetadataChanged(MediaMetadata metadata) ;
    shared formal void onMetadataRetrieveError() ;
    shared formal void onCurrentQueueIndexUpdated(Integer queueIndex) ;
    shared formal void onQueueUpdated(String title, List<MediaSession.QueueItem>? newQueue) ;
}
