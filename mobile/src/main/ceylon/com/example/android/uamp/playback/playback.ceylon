import android.content {
    BroadcastReceiver,
    Context,
    Intent,
    IntentFilter
}
import android.media {
    AudioManager,
    MediaMetadata,
    MediaPlayer {
        OnCompletionListener,
        OnErrorListener,
        OnPreparedListener,
        OnSeekCompleteListener
    }
}
import android.net {
    Uri
}
import android.net.wifi {
    WifiManager
}
import android.os {
    PowerManager
}
import android.media.session {
    MediaSession {
        QueueItem
    },
    PlaybackState
}

import com.example.android.uamp {
    MusicService
}
import com.example.android.uamp.model {
    MusicProvider,
    customMetadataTrackSource
}
import com.example.android.uamp.utils {
    LogHelper,
    MediaIDHelper
}
import com.google.android.gms.cast {
    MediaInfo,
    MediaData=MediaMetadata,
    MediaStatus
}
import com.google.android.gms.cast.framework {
    CastContext
}
import com.google.android.gms.cast.framework.media {
    RemoteMediaClient
}
import com.google.android.gms.common.images {
    WebImage
}

import java.io {
    IOException
}
import java.util {
    Objects
}

import org.json {
    JSONException,
    JSONObject
}

shared class CastPlayback(MusicProvider musicProvider, Context context)
        satisfies Playback
                & RemoteMediaClient.Listener {

    value tag = LogHelper.makeLogTag(`CastPlayback`);

    value mimeTypeAudioMpeg = "audio/mpeg";
    value itemId = "itemId";

    function toCastMediaMetadata(MediaMetadata track, JSONObject customData) {
        value metadata = MediaData(MediaData.mediaTypeMusicTrack);
        metadata.putString(MediaData.keyTitle, track.description.title?.string else "");
        metadata.putString(MediaData.keySubtitle, track.description.subtitle?.string else "");
        metadata.putString(MediaData.keyAlbumArtist, track.getString(MediaMetadata.metadataKeyAlbumArtist));
        metadata.putString(MediaData.keyAlbumTitle, track.getString(MediaMetadata.metadataKeyAlbum));
        value image = WebImage(Uri.Builder().encodedPath(track.getString(MediaMetadata.metadataKeyAlbumArtUri)).build());
        metadata.addImage(image);
        metadata.addImage(image);
        return MediaInfo.Builder(track.getString(customMetadataTrackSource))
            .setContentType(mimeTypeAudioMpeg)
            .setStreamType(MediaInfo.streamTypeBuffered)
            .setMetadata(metadata)
            .setCustomData(customData)
            .build();
    }

    value appContext = context.applicationContext;

    value remoteMediaClient
            = CastContext.getSharedInstance(appContext)
            .sessionManager.currentCastSession
            .remoteMediaClient;

    variable Callback? callback = null;
    variable Integer currentPosition = 0;

    shared actual variable Integer state = 0;

    shared actual variable String? currentMediaId = null;

    shared actual void start() => remoteMediaClient.addListener(this);

    shared actual void stop(Boolean notifyListeners) {
        remoteMediaClient.removeListener(this);
        state = PlaybackState.stateStopped;
        if (notifyListeners) {
            callback?.onPlaybackStatusChanged(state);
        }
    }

    shared actual Integer currentStreamPosition
            => !connected then this.currentPosition
            else remoteMediaClient.approximateStreamPosition;

    assign currentStreamPosition
            => this.currentPosition = currentStreamPosition;

    shared actual void updateLastKnownStreamPosition()
            => currentPosition = currentStreamPosition;

    shared actual void play(QueueItem item) {
        try {
            assert (exists id = item.description.mediaId);
            loadMedia(id, true);
            state = PlaybackState.stateBuffering;
            callback?.onPlaybackStatusChanged(state);
        }
        catch (JSONException e) {
            LogHelper.e(tag, "Exception loading media ", e, null);
            callback?.onError(e.message);
        }
    }

    shared actual void pause() {
        try {
            if (remoteMediaClient.hasMediaSession()) {
                remoteMediaClient.pause();
                currentPosition = remoteMediaClient.approximateStreamPosition;
            } else {
                assert (exists id = currentMediaId);
                loadMedia(id, false);
            }
        }
        catch (JSONException e) {
//            LogHelper.e(tag, e, "Exception pausing cast playback");
            callback?.onError(e.message);
        }
    }

    shared actual void seekTo(Integer position) {
        if (exists id = currentMediaId) {
            try {
                if (remoteMediaClient.hasMediaSession()) {
                    remoteMediaClient.seek(position);
                    currentPosition = position;
                } else {
                    currentPosition = position;
                    loadMedia(id, false);
                }
            }
            catch (JSONException e) {
    //            LogHelper.e(tag, e, "Exception pausing cast playback");
                callback?.onError(e.message);
            }
        }
        else {
            callback?.onError("seekTo cannot be calling in the absence of mediaId.");
            return;
        }
    }

    shared actual void setCallback(Callback callback) => this.callback = callback;

    shared actual Boolean connected
            => CastContext.getSharedInstance(appContext)
                    .sessionManager.currentCastSession
                    ?.connected
            else false;

    shared actual Boolean playing => connected && remoteMediaClient.playing;

    void loadMedia(String mediaId, Boolean autoPlay) {
        value musicId = MediaIDHelper.extractMusicIDFromMediaID(mediaId);
        "Invalid mediaId ``mediaId``"
        assert (exists track = musicProvider.getMusic(musicId));
        if (!Objects.equals(mediaId, currentMediaId)) {
            currentMediaId = mediaId;
            currentPosition = 0;
        }
        value customData = JSONObject();
        customData.put(itemId, mediaId);
        value media = toCastMediaMetadata(track, customData);
        remoteMediaClient.load(media, autoPlay, currentPosition, customData);
    }


    void setMetadataFromRemote() {
        try {
            if (exists mediaInfo = remoteMediaClient.mediaInfo,
                exists customData = mediaInfo.customData, customData.has(itemId)) {
                value remoteMediaId = customData.getString(itemId);
                if (!Objects.equals(currentMediaId, remoteMediaId)) {
                    currentMediaId = remoteMediaId;
                    callback?.setCurrentMediaId(remoteMediaId);
                    updateLastKnownStreamPosition();
                }
            }
        }
        catch (JSONException e) {
//            LogHelper.e(tag, e, "Exception processing update metadata");
        }
    }

    void updatePlaybackState() {
        value status = remoteMediaClient.playerState;
        value idleReason = remoteMediaClient.idleReason;
        LogHelper.d(tag, "onRemoteMediaPlayerStatusUpdated ", status);
        if (status == MediaStatus.playerStateIdle) {
            if (idleReason == MediaStatus.idleReasonFinished) {
                callback?.onCompletion();
            }
        }
        else if (status == MediaStatus.playerStateBuffering) {
            state = PlaybackState.stateBuffering;
            callback?.onPlaybackStatusChanged(state);
        }
        else if (status == MediaStatus.playerStatePlaying) {
            state = PlaybackState.statePlaying;
            setMetadataFromRemote();
            callback?.onPlaybackStatusChanged(state);
        }
        else if (status == MediaStatus.playerStatePaused) {
            state = PlaybackState.statePaused;
            setMetadataFromRemote();
            callback?.onPlaybackStatusChanged(state);
        }
        else {
            LogHelper.d(tag, "State default : ", status);
        }
    }

    shared actual void onMetadataUpdated() {
        LogHelper.d(tag, "RemoteMediaClient.onMetadataUpdated");
        setMetadataFromRemote();
    }

    shared actual void onStatusUpdated() {
        LogHelper.d(tag, "RemoteMediaClient.onStatusUpdated");
        updatePlaybackState();
    }

    shared actual void onSendingRemoteMediaRequest() {}

    shared actual void onAdBreakStatusUpdated() {}

    shared actual void onQueueStatusUpdated() {}

    shared actual void onPreloadStatusUpdated() {}
}

class AudioFocus {
    shared Float volume;
    shared new focused {
        volume => 1.0;
    }
    shared new noFocusNoDuck {
        volume => 0.0;
    }
    shared new noFocusCanDuck {
        volume => 0.2;
    }
}

shared class LocalPlayback(Context context, MusicProvider musicProvider)
        satisfies Playback
                & AudioManager.OnAudioFocusChangeListener
                & OnCompletionListener
                & OnErrorListener
                & OnPreparedListener
                & OnSeekCompleteListener {

    value tag = LogHelper.makeLogTag(`LocalPlayback`);

    variable Boolean playOnFocusGain = false;
    variable Callback? callback = null;
    variable Boolean noisyReceiverRegistered = false;
    variable Integer currentPosition = 0;
    variable AudioFocus audioFocus = AudioFocus.noFocusNoDuck;
    variable MediaPlayer? mediaPlayer = null;

    value noisyIntentFilter = IntentFilter(AudioManager.actionAudioBecomingNoisy);

    assert (is AudioManager audioManager = context.getSystemService(Context.audioService));
    assert (is WifiManager wifiManager = context.getSystemService(Context.wifiService));
    value wifiLock = wifiManager.createWifiLock(WifiManager.wifiModeFull, "uAmp_lock");

    shared actual variable Integer state = PlaybackState.stateNone;

    shared actual variable String? currentMediaId = null;

    shared actual Boolean playing
            => playOnFocusGain
            || (mediaPlayer?.playing else false);

    object audioNoisyReceiver extends BroadcastReceiver() {
        shared actual void onReceive(Context context, Intent intent) {
            if (AudioManager.actionAudioBecomingNoisy==intent.action) {
                LogHelper.d(tag, "Headphones disconnected.");
                if (playing) {
                    Intent i = Intent(context, `MusicService`);
                    i.setAction(MusicService.actionCmd);
                    i.putExtra(MusicService.cmdName, MusicService.cmdPause);
                    context.startService(i);
                }
            }
        }
    }

    shared actual void start() {}

    shared actual void stop(Boolean notifyListeners) {
        state = PlaybackState.stateStopped;
        if (notifyListeners) {
            callback?.onPlaybackStatusChanged(state);
        }
        currentPosition = currentStreamPosition;
        giveUpAudioFocus();
        unregisterAudioNoisyReceiver();
        relaxResources(true);
    }

    shared actual Boolean connected => true;

    shared actual Integer currentStreamPosition
            => if (exists player = mediaPlayer)
            then player.currentPosition
            else currentPosition;

    assign currentStreamPosition
            => this.currentPosition = currentStreamPosition;

    shared actual void updateLastKnownStreamPosition() {
        if (exists player = mediaPlayer) {
            currentPosition = player.currentPosition;
        }
    }

    shared actual void play(QueueItem item) {
        playOnFocusGain = true;
        tryToGetAudioFocus();
        registerAudioNoisyReceiver();
        value mediaId = item.description.mediaId;
        value mediaHasChanged = !Objects.equals(mediaId, currentMediaId);
        if (mediaHasChanged) {
            currentPosition = 0;
            currentMediaId = mediaId;
        }
        if (state == PlaybackState.statePaused,
            !mediaHasChanged,
            mediaPlayer exists) {
            configMediaPlayerState();
        } else {
            state = PlaybackState.stateStopped;
            relaxResources(false);
            assert (exists id = item.description.mediaId);
            value track = musicProvider.getMusic(MediaIDHelper.extractMusicIDFromMediaID(id));
            value source = track?.getString(customMetadataTrackSource)?.replace(" ", "%20");
            try {
                value player = createMediaPlayerIfNeeded();
                state = PlaybackState.stateBuffering;
                player.setAudioStreamType(AudioManager.streamMusic);
                player.setDataSource(source);
                player.prepareAsync();
                wifiLock.acquire();
                callback?.onPlaybackStatusChanged(state);
            }
            catch (IOException ex) {
//                LogHelper.e(tag, ex, "Exception playing song");
                callback?.onError(ex.message);
            }
        }
    }

    shared actual void pause() {
        if (state == PlaybackState.statePlaying) {
            if (exists player = mediaPlayer, player.playing) {
                player.pause();
                currentPosition = player.currentPosition;
            }
            relaxResources(false);
        }
        state = PlaybackState.statePaused;
        callback?.onPlaybackStatusChanged(state);
        unregisterAudioNoisyReceiver();
    }

    shared actual void seekTo(Integer position) {
        LogHelper.d(tag, "seekTo called with ", position);
        if (exists player = mediaPlayer) {
            if (player.playing) {
                state = PlaybackState.stateBuffering;
            }
            registerAudioNoisyReceiver();
            player.seekTo(position);
            callback?.onPlaybackStatusChanged(state);
        } else {
            currentPosition = position;
        }
    }

    shared actual void setCallback(Callback callback) => this.callback = callback;

    void tryToGetAudioFocus() {
        LogHelper.d(tag, "tryToGetAudioFocus");
        value result
                = audioManager.requestAudioFocus(this,
                    AudioManager.streamMusic,
                    AudioManager.audiofocusGain);
        audioFocus
                = result == AudioManager.audiofocusRequestGranted
                then AudioFocus.focused
                else AudioFocus.noFocusNoDuck;
    }

    void giveUpAudioFocus() {
        LogHelper.d(tag, "giveUpAudioFocus");
        if (audioManager.abandonAudioFocus(this)
                == AudioManager.audiofocusRequestGranted) {
            audioFocus = AudioFocus.noFocusNoDuck;
        }
    }

    void configMediaPlayerState() {
        LogHelper.d(tag, "configMediaPlayerState. mAudioFocus=", audioFocus);
        switch (audioFocus)
        case (AudioFocus.noFocusNoDuck) {
            if (state == PlaybackState.statePlaying) {
                pause();
            }
        } else {
            registerAudioNoisyReceiver();
            value volume = audioFocus.volume;
            mediaPlayer?.setVolume(volume, volume);
            if (playOnFocusGain) {
                if (exists player = mediaPlayer, !player.playing) {
                    LogHelper.d(tag, "configMediaPlayerState startMediaPlayer. seeking to ", currentPosition);
                    if (currentPosition == player.currentPosition) {
                        player.start();
                        state = PlaybackState.statePlaying;
                    } else {
                        player.seekTo(currentPosition);
                        state = PlaybackState.stateBuffering;
                    }
                }
                playOnFocusGain = false;
            }
        }
        callback?.onPlaybackStatusChanged(state);
    }

    shared actual void onAudioFocusChange(Integer focusChange) {
        LogHelper.d(tag, "onAudioFocusChange. focusChange=", focusChange);
        if (focusChange == AudioManager.audiofocusGain) {
            audioFocus = AudioFocus.focused;
        } else if (focusChange == AudioManager.audiofocusLoss
                || focusChange == AudioManager.audiofocusLossTransient
                || focusChange == AudioManager.audiofocusLossTransientCanDuck) {
            value canDuck = focusChange == AudioManager.audiofocusLossTransientCanDuck;
            audioFocus = canDuck then AudioFocus.noFocusCanDuck else AudioFocus.noFocusNoDuck;
            if (state == PlaybackState.statePlaying, !canDuck) {
                playOnFocusGain = true;
            }
        } else {
            LogHelper.e(tag, "onAudioFocusChange: Ignoring unsupported focusChange: ", focusChange);
        }
        configMediaPlayerState();
    }

    shared actual void onSeekComplete(MediaPlayer mp) {
        LogHelper.d(tag, "onSeekComplete from MediaPlayer:", mp.currentPosition);
        currentPosition = mp.currentPosition;
        if (state == PlaybackState.stateBuffering) {
            registerAudioNoisyReceiver();
            mediaPlayer?.start();
            state = PlaybackState.statePlaying;
        }
        callback?.onPlaybackStatusChanged(state);
    }

    shared actual void onCompletion(MediaPlayer player) {
        LogHelper.d(tag, "onCompletion from MediaPlayer");
        callback?.onCompletion();
    }

    shared actual void onPrepared(MediaPlayer player) {
        LogHelper.d(tag, "onPrepared from MediaPlayer");
        configMediaPlayerState();
    }

    shared actual Boolean onError(MediaPlayer mp, Integer what, Integer extra) {
        LogHelper.e(tag, "Media player error: what=``what```, extra=``extra``");
        callback?.onError("MediaPlayer error ``what``` (``extra```)");
        return true;
    }

    MediaPlayer createMediaPlayerIfNeeded() {
        LogHelper.d(tag, "createMediaPlayerIfNeeded. needed? ", !mediaPlayer exists);
        if (exists player = mediaPlayer) {
            player.reset();
            return player;
        } else {
            value player = MediaPlayer();
            player.setWakeMode(context.applicationContext, PowerManager.partialWakeLock);
            player.setOnPreparedListener(this);
            player.setOnCompletionListener(this);
            player.setOnErrorListener(this);
            player.setOnSeekCompleteListener(this);
            mediaPlayer = player;
            return player;
        }
    }

    void relaxResources(Boolean releaseMediaPlayer) {
        LogHelper.d(tag, "relaxResources. releaseMediaPlayer=", releaseMediaPlayer);
        if (releaseMediaPlayer, exists player = mediaPlayer) {
            player.reset();
            player.release();
            mediaPlayer = null;
        }
        if (wifiLock.held) {
            wifiLock.release();
        }
    }

    void registerAudioNoisyReceiver() {
        if (!noisyReceiverRegistered) {
            context.registerReceiver(audioNoisyReceiver, noisyIntentFilter);
            noisyReceiverRegistered = true;
        }
    }

    void unregisterAudioNoisyReceiver() {
        if (noisyReceiverRegistered) {
            context.unregisterReceiver(audioNoisyReceiver);
            noisyReceiverRegistered = false;
        }
    }

}

shared interface Callback {
    shared formal void onCompletion() ;
    shared formal void onPlaybackStatusChanged(Integer state) ;
    shared formal void onError(String error) ;
    shared formal void setCurrentMediaId(String mediaId) ;
}

shared interface Playback {
    shared formal void start() ;
    shared formal void stop(Boolean notifyListeners) ;
    shared formal variable Integer state;
    shared formal Boolean connected;
    shared formal Boolean playing;
    shared formal variable Integer currentStreamPosition;
    shared formal void updateLastKnownStreamPosition() ;
    shared formal void play(QueueItem item) ;
    shared formal void pause() ;
    shared formal void seekTo(Integer position) ;
    shared formal variable String? currentMediaId;

    shared formal void setCallback(Callback callback) ;
}
