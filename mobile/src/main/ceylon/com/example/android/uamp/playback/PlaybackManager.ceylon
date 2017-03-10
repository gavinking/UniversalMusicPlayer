import android.content.res {
    Resources
}
import android.media.session {
    MediaSession,
    PlaybackState
}
import android.os {
    Bundle,
    SystemClock {
        elapsedRealtime
    }
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.utils {
    MediaIDHelper,
    WearHelper
}

shared class PlaybackManager(
        PlaybackServiceCallback serviceCallback,
        Resources resources,
        MusicProvider musicProvider,
        QueueManager queueManager,
        variable Playback currentPlayback)
        extends MediaSession.Callback() {

//    value tag = LogHelper.makeLogTag(`PlaybackManager`);

    value customActionThumbsUp = "com.example.android.uamp.THUMBS_UP";

    value availableActions
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
            exists mediaId = currentMusic.description.mediaId,
            exists musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId)) {
            value favoriteIcon
                    = musicProvider.isFavorite(musicId)
                    then R.Drawable.ic_star_on
                    else R.Drawable.ic_star_off;
//            LogHelper.d(tag, "updatePlaybackState, setting Favorite custom action of music ", musicId, " current favorite=", musicProvider.isFavorite(musicId));
            value customActionExtras = Bundle();
            WearHelper.setShowCustomActionOnWear(customActionExtras, true);
            stateBuilder.addCustomAction(PlaybackState.CustomAction.Builder(customActionThumbsUp,
                        resources.getString(R.String.favorite), favoriteIcon)
                .setExtras(customActionExtras).build());
        }
    }

    shared void updatePlaybackState(String? error) {
//        LogHelper.d(tag, "updatePlaybackState, playback state=``currentPlayback.state``");
        value position
                = currentPlayback.connected
                then currentPlayback.currentStreamPosition
                else PlaybackState.playbackPositionUnknown;
        value stateBuilder
                = PlaybackState.Builder()
                .setActions(availableActions);
        setCustomAction(stateBuilder);
        Integer state;
        if (exists error) {
            stateBuilder.setErrorMessage(error);
            state = PlaybackState.stateError;
        }
        else {
            state = currentPlayback.state;
        }
        stateBuilder.setState(state, position, 1.0, elapsedRealtime());
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
//        LogHelper.d(tag, "handlePlayRequest: mState=``currentPlayback.state``");
        if (exists currentMusic = queueManager.currentMusic) {
            serviceCallback.onPlaybackStart();
            currentPlayback.play(currentMusic);
        }
    }

    shared void handlePauseRequest() {
//        LogHelper.d(tag, "handlePauseRequest: mState=``currentPlayback.state``");
        if (currentPlayback.playing) {
            currentPlayback.pause();
            serviceCallback.onPlaybackStop();
        }
    }

    shared void handleStopRequest(String? withError) {
//        LogHelper.d(tag, "handleStopRequest: mState=``currentPlayback.state`` error=", withError);
        currentPlayback.stop(true);
        serviceCallback.onPlaybackStop();
        updatePlaybackState(withError);
    }

    shared actual void onPlay() {
//        LogHelper.d(tag, "play");
        if (!queueManager.currentMusic exists) {
            queueManager.setRandomQueue();
        }
        handlePlayRequest();
    }

    shared actual void onSkipToQueueItem(Integer queueId) {
//        LogHelper.d(tag, "OnSkipToQueueItem: ``queueId``");
        queueManager.setCurrentQueueItemByQueueId(queueId);
        queueManager.updateMetadata();
    }

    shared actual void onSeekTo(Integer position) {
//        LogHelper.d(tag, "onSeekTo:", position);
        currentPlayback.seekTo(position);
    }

    shared actual void onPlayFromMediaId(String mediaId, Bundle extras) {
//        LogHelper.d(tag, "playFromMediaId mediaId:", mediaId, "  extras=", extras);
        queueManager.setQueueFromMusic(mediaId);
        handlePlayRequest();
    }

    shared actual void onPause() {
//        LogHelper.d(tag, "pause. current state=``currentPlayback.state``");
        handlePauseRequest();
    }

    shared actual void onStop() {
//        LogHelper.d(tag, "stop. current state=``currentPlayback.state``");
        handleStopRequest(null);
    }

    shared actual void onSkipToNext() {
//        LogHelper.d(tag, "skipToNext");
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
        if (customActionThumbsUp == action) {
//            LogHelper.i(tag, "onCustomAction: favorite for current track");
            if (exists currentMusic = queueManager.currentMusic,
                exists mediaId = currentMusic.description.mediaId,
                exists musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId)) {
                musicProvider.setFavorite(musicId, !musicProvider.isFavorite(musicId));
            }
            updatePlaybackState(null);
        } else {
//            LogHelper.e(tag, "Unsupported action: ", action);
        }
    }

    shared actual void onPlayFromSearch(String query, Bundle extras) {
//        LogHelper.d(tag, "playFromSearch  query=", query, " extras=", extras);
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
//            LogHelper.d(tag, "setCurrentMediaId", mediaId);
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
        playback.currentStreamPosition = pos<0 then 0 else pos;
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
//            LogHelper.d(tag, "Default called. Old state is ", oldState);
        }
    }

}

shared interface PlaybackServiceCallback {
    shared formal void onPlaybackStart();
    shared formal void onNotificationRequired();
    shared formal void onPlaybackStop();
    shared formal void onPlaybackStateUpdated(PlaybackState newState);
}
