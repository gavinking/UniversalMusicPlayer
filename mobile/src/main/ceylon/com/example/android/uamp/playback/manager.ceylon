import android.content.res {
    Resources
}
import android.os {
    Bundle,
    SystemClock
}
import android.media.session {
    MediaSession,
    PlaybackState
}

import com.example.android.uamp {
    R,
    AlbumArtCache
}
import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.utils {
    LogHelper,
    MediaIDHelper,
    WearHelper,
    QueueHelper
}
import java.util {
    Collections,
    ArrayList,
    Arrays,
    List
}
import android.graphics {
    Bitmap
}
import android.media {
    MediaMetadata
}

shared class PlaybackManager(
        PlaybackServiceCallback serviceCallback,
        Resources resources,
        MusicProvider musicProvider,
        QueueManager queueManager,
        variable Playback currentPlayback)
        extends MediaSession.Callback() {

    value tag = LogHelper.makeLogTag(`PlaybackManager`);

    value customActionThumbsUp = "com.example.android.uamp.THUMBS_UP";

    Integer availableActions
            => PlaybackState.actionPlayPause
            .or(PlaybackState.actionPlayFromMediaId)
            .or(PlaybackState.actionPlayFromSearch)
            .or(PlaybackState.actionSkipToPrevious)
            .or(PlaybackState.actionSkipToNext)
            .or(currentPlayback.playing
                    then PlaybackState.actionPause
                    else PlaybackState.actionPlay);

    shared Playback playback => currentPlayback;

    void setCustomAction(PlaybackState.Builder stateBuilder) {
        if (exists currentMusic = queueManager.currentMusic,
            exists mediaId = currentMusic.description.mediaId) {
            value musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId);
            value favoriteIcon
                    = musicProvider.isFavorite(musicId)
                    then R.Drawable.ic_star_on
                    else R.Drawable.ic_star_off;
            LogHelper.d(tag, "updatePlaybackState, setting Favorite custom action of music ", musicId, " current favorite=", musicProvider.isFavorite(musicId));
            value customActionExtras = Bundle();
            WearHelper.setShowCustomActionOnWear(customActionExtras, true);
            stateBuilder.addCustomAction(PlaybackState.CustomAction.Builder(customActionThumbsUp,
                        resources.getString(R.String.favorite), favoriteIcon)
                .setExtras(customActionExtras).build());
        }
    }

    shared void updatePlaybackState(String? error) {
        LogHelper.d(tag, "updatePlaybackState, playback state=``currentPlayback.state``");
        value position
                = currentPlayback.connected
                then currentPlayback.currentStreamPosition
                else PlaybackState.playbackPositionUnknown;
        value stateBuilder
                = PlaybackState.Builder()
                .setActions(availableActions);
        setCustomAction(stateBuilder);
        variable value state = currentPlayback.state;
        if (exists error) {
            stateBuilder.setErrorMessage(error);
            state = PlaybackState.stateError;
        }
        stateBuilder.setState(state, position, 1.0f, SystemClock.elapsedRealtime());
        if (exists currentMusic = queueManager.currentMusic) {
            stateBuilder.setActiveQueueItemId(currentMusic.queueId);
        }
        serviceCallback.onPlaybackStateUpdated(stateBuilder.build());
        if (state == PlaybackState.statePlaying
         || state == PlaybackState.statePaused) {
            serviceCallback.onNotificationRequired();
        }
    }

    shared void handlePlayRequest() {
        LogHelper.d(tag, "handlePlayRequest: mState=``currentPlayback.state``");
        if (exists currentMusic = queueManager.currentMusic) {
            serviceCallback.onPlaybackStart();
            currentPlayback.play(currentMusic);
        }
    }

    shared void handlePauseRequest() {
        LogHelper.d(tag, "handlePauseRequest: mState=``currentPlayback.state``");
        if (currentPlayback.playing) {
            currentPlayback.pause();
            serviceCallback.onPlaybackStop();
        }
    }

    shared void handleStopRequest(String? withError) {
        LogHelper.d(tag, "handleStopRequest: mState=``currentPlayback.state`` error=", withError);
        currentPlayback.stop(true);
        serviceCallback.onPlaybackStop();
        updatePlaybackState(withError);
    }

    shared actual void onPlay() {
        LogHelper.d(tag, "play");
        if (!queueManager.currentMusic exists) {
            queueManager.setRandomQueue();
        }
        handlePlayRequest();
    }

    shared actual void onSkipToQueueItem(Integer queueId) {
        LogHelper.d(tag, "OnSkipToQueueItem: ``queueId``");
        queueManager.setCurrentQueueItemByQueueId(queueId);
        queueManager.updateMetadata();
    }

    shared actual void onSeekTo(Integer position) {
        LogHelper.d(tag, "onSeekTo:", position);
        currentPlayback.seekTo(position);
    }

    shared actual void onPlayFromMediaId(String mediaId, Bundle extras) {
        LogHelper.d(tag, "playFromMediaId mediaId:", mediaId, "  extras=", extras);
        queueManager.setQueueFromMusic(mediaId);
        handlePlayRequest();
    }

    shared actual void onPause() {
        LogHelper.d(tag, "pause. current state=``currentPlayback.state``");
        handlePauseRequest();
    }

    shared actual void onStop() {
        LogHelper.d(tag, "stop. current state=``currentPlayback.state``");
        handleStopRequest(null);
    }

    shared actual void onSkipToNext() {
        LogHelper.d(tag, "skipToNext");
        if (queueManager.skipQueuePosition(1)) {
            handlePlayRequest();
        } else {
            handleStopRequest("Cannot skip");
        }
        queueManager.updateMetadata();
    }

    shared actual void onSkipToPrevious() {
        if (queueManager.skipQueuePosition(-1)) {
            handlePlayRequest();
        } else {
            handleStopRequest("Cannot skip");
        }
        queueManager.updateMetadata();
    }

    shared actual void onCustomAction(String action, Bundle extras) {
        if (customActionThumbsUp.equals(action)) {
            LogHelper.i(tag, "onCustomAction: favorite for current track");
            if (exists currentMusic = queueManager.currentMusic,
                exists mediaId = currentMusic.description.mediaId) {
                value musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId);
                musicProvider.setFavorite(musicId, !musicProvider.isFavorite(musicId));
            }
            updatePlaybackState(null);
        } else {
            LogHelper.e(tag, "Unsupported action: ", action);
        }
    }

    shared actual void onPlayFromSearch(String query, Bundle extras) {
        LogHelper.d(tag, "playFromSearch  query=", query, " extras=", extras);
        currentPlayback.state = PlaybackState.stateConnecting;
        value successSearch = queueManager.setQueueFromSearch(query, extras);
        if (successSearch) {
            handlePlayRequest();
            queueManager.updateMetadata();
        } else {
            updatePlaybackState("Could not find music");
        }
    }

    object callback satisfies Callback {
        shared actual void onCompletion() {
            if (queueManager.skipQueuePosition(1)) {
                handlePlayRequest();
                queueManager.updateMetadata();
            } else {
                handleStopRequest(null);
            }
        }
        shared actual void onPlaybackStatusChanged(Integer state)
                => updatePlaybackState(null);
        shared actual void onError(String error)
                => updatePlaybackState(error);
        shared actual void setCurrentMediaId(String mediaId) {
            LogHelper.d(tag, "setCurrentMediaId", mediaId);
            queueManager.setQueueFromMusic(mediaId);
        }
    }

    currentPlayback.setCallback(callback);

    shared void switchToPlayback(Playback playback, Boolean resumePlaying) {
        value oldState = playback.state;
        value pos = playback.currentStreamPosition;
        value currentMediaId = playback.currentMediaId;
        playback.stop(false);
        playback.setCallback(callback);
        playback.currentStreamPosition = if (pos<0) then 0 else pos;
        playback.currentMediaId = currentMediaId;
        playback.start();
        this.currentPlayback = playback;

        if (oldState == PlaybackState.stateBuffering) {
            playback.pause();
        }
        else if (oldState == PlaybackState.statePlaying) {
            if (resumePlaying,
                exists currentMusic = queueManager.currentMusic) {
                playback.play(currentMusic);
            } else if (!resumePlaying) {
                playback.pause();
            } else {
                playback.stop(true);
            }
        }
        else if (oldState == PlaybackState.stateNone) {
        }
        else {
            LogHelper.d(tag, "Default called. Old state is ", oldState);
        }
    }

}

shared interface PlaybackServiceCallback {
    shared formal void onPlaybackStart();
    shared formal void onNotificationRequired();
    shared formal void onPlaybackStop();
    shared formal void onPlaybackStateUpdated(PlaybackState newState);
}

shared class QueueManager(
        MusicProvider musicProvider,
        Resources resources,
        MetadataUpdateListener listener) {

    value tag = LogHelper.makeLogTag(`QueueManager`);

    variable value mPlayingQueue
            = Collections.synchronizedList(ArrayList<MediaSession.QueueItem>());
    variable value mCurrentIndex = 0;

    shared Boolean isSameBrowsingCategory(String mediaId) {
        value newBrowseHierarchy = MediaIDHelper.getHierarchy(mediaId);
        if (exists current = currentMusic) {
            assert (exists id = current.description.mediaId);
            value currentBrowseHierarchy = MediaIDHelper.getHierarchy(id);
            return Arrays.equals(newBrowseHierarchy, currentBrowseHierarchy);
        }
        else {
            return false;
        }
    }

    void setCurrentQueueIndex(Integer index) {
        if (index>=0, index<mPlayingQueue.size()) {
            mCurrentIndex = index;
            listener.onCurrentQueueIndexUpdated(mCurrentIndex);
        }
    }

    shared Boolean setCurrentQueueItemByQueueId(Integer queueId) {
        value index = QueueHelper.getMusicIndexOnQueue(mPlayingQueue, queueId);
        setCurrentQueueIndex(index);
        return index>=0;
    }

    shared Boolean setCurrentQueueItemByMediaId(String mediaId) {
        value index = QueueHelper.getMusicIndexOnQueue(mPlayingQueue, mediaId);
        setCurrentQueueIndex(index);
        return index>=0;
    }

    shared Boolean skipQueuePosition(Integer amount) {
        variable Integer index = mCurrentIndex + amount;
        if (index<0) {
            index = 0;
        } else {
            index %=mPlayingQueue.size();
        }
        if (!QueueHelper.isIndexPlayable(index, mPlayingQueue)) {
            LogHelper.e(tag, "Cannot increment queue index by ", amount, ". Current=", mCurrentIndex, " queue length=", mPlayingQueue.size());
            return false;
        }
        mCurrentIndex = index;
        return true;
    }

    shared Boolean setQueueFromSearch(String query, Bundle extras) {
        value queue = QueueHelper.getPlayingQueueFromSearch(query, extras, musicProvider);
        setCurrentQueue(resources.getString(R.String.search_queue_title), queue);
        updateMetadata();
        return queue exists && !queue.empty;
    }

    shared void setRandomQueue() {
        value queue = QueueHelper.getRandomQueue(musicProvider);
        setCurrentQueue(resources.getString(R.String.random_queue_title), queue);
        updateMetadata();
    }

    shared void setQueueFromMusic(String mediaId) {
        LogHelper.d(tag, "setQueueFromMusic", mediaId);
        value canReuseQueue
                = isSameBrowsingCategory(mediaId)
                then setCurrentQueueItemByMediaId(mediaId)
        else false;
        if (!canReuseQueue) {
            value queueTitle
                    = resources.getString(R.String.browse_musics_by_genre_subtitle,
                            MediaIDHelper.extractBrowseCategoryValueFromMediaID(mediaId));
            setCurrentQueue(queueTitle, QueueHelper.getPlayingQueue(mediaId, musicProvider), mediaId);
        }
        updateMetadata();
    }

    shared MediaSession.QueueItem? currentMusic
            => QueueHelper.isIndexPlayable(mCurrentIndex, mPlayingQueue)
            then mPlayingQueue.get(mCurrentIndex);

    shared Integer currentQueueSize => mPlayingQueue?.size() else 0;

    void setCurrentQueue(String title, List<MediaSession.QueueItem> newQueue, String? initialMediaId = null) {
        mPlayingQueue = newQueue;
        value index
                = if (exists initialMediaId)
                then QueueHelper.getMusicIndexOnQueue(mPlayingQueue, initialMediaId)
                else 0;
        mCurrentIndex = largest(index, 0);
        listener.onQueueUpdated(title, newQueue);
    }

    shared void updateMetadata() {
        if (exists currentMusic = this.currentMusic) {
            assert (exists mediaId = currentMusic.description.mediaId);
            value musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId);
            "Invalid musicId ``musicId``"
            assert (exists metadata = musicProvider.getMusic(musicId));
            listener.onMetadataChanged(metadata);
            if (!metadata.description.iconBitmap exists, metadata.description.iconUri exists) {
                value albumUri = metadata.description.iconUri?.string;
                AlbumArtCache.instance.fetch(albumUri, object extends AlbumArtCache.FetchListener() {
                    shared actual void onFetched(String artUrl, Bitmap bitmap, Bitmap icon) {
                        musicProvider.updateMusicArt(musicId, bitmap, icon);
                        if (exists currentMusic = outer.currentMusic) {
                            assert (exists mediaId = currentMusic.description.mediaId);
                            value currentPlayingId = MediaIDHelper.extractMusicIDFromMediaID(mediaId);
                            if (musicId == currentPlayingId) {
                                assert (exists music = musicProvider.getMusic(currentPlayingId));
                                listener.onMetadataChanged(music);
                            }
                        }
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
    shared formal void onQueueUpdated(String title, List<MediaSession.QueueItem> newQueue) ;
}
