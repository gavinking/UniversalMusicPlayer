import com.example.android.uamp.utils {
    MediaIDHelper
}
import com.example.android.uamp {
    MusicService
}
import android.os {
    PowerManager
}
import android.net.wifi {
    WifiManager
}
import com.example.android.uamp.model {
    customMetadataTrackSource,
    MusicProvider
}
import android.media {
    AudioManager,
    MediaPlayer {
        OnCompletionListener,
        OnErrorListener,
        OnPreparedListener,
        OnSeekCompleteListener
    }
}
import java.util {
    Objects
}
import java.io {
    IOException
}
import android.media.session {
    PlaybackState,
    MediaSession
}
import android.content {
    Intent,
    IntentFilter,
    BroadcastReceiver,
    Context
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

//    value tag = LogHelper.makeLogTag(`LocalPlayback`);

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
//                LogHelper.d(tag, "Headphones disconnected.");
                if (playing) {
                    value i = Intent(context, `MusicService`);
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

    shared actual void play(MediaSession.QueueItem item) {
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
//        LogHelper.d(tag, "seekTo called with ", position);
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
//        LogHelper.d(tag, "tryToGetAudioFocus");
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
//        LogHelper.d(tag, "giveUpAudioFocus");
        if (audioManager.abandonAudioFocus(this)
                == AudioManager.audiofocusRequestGranted) {
            audioFocus = AudioFocus.noFocusNoDuck;
        }
    }

    void configMediaPlayerState() {
//        LogHelper.d(tag, "configMediaPlayerState. mAudioFocus=", audioFocus);
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
//                    LogHelper.d(tag, "configMediaPlayerState startMediaPlayer. seeking to ", currentPosition);
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
//        LogHelper.d(tag, "onAudioFocusChange. focusChange=", focusChange);
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
//            LogHelper.e(tag, "onAudioFocusChange: Ignoring unsupported focusChange: ", focusChange);
        }
        configMediaPlayerState();
    }

    shared actual void onSeekComplete(MediaPlayer mp) {
//        LogHelper.d(tag, "onSeekComplete from MediaPlayer:", mp.currentPosition);
        currentPosition = mp.currentPosition;
        if (state == PlaybackState.stateBuffering) {
            registerAudioNoisyReceiver();
            mediaPlayer?.start();
            state = PlaybackState.statePlaying;
        }
        callback?.onPlaybackStatusChanged(state);
    }

    shared actual void onCompletion(MediaPlayer player) {
//        LogHelper.d(tag, "onCompletion from MediaPlayer");
        callback?.onCompletion();
    }

    shared actual void onPrepared(MediaPlayer player) {
//        LogHelper.d(tag, "onPrepared from MediaPlayer");
        configMediaPlayerState();
    }

    shared actual Boolean onError(MediaPlayer mp, Integer what, Integer extra) {
//        LogHelper.e(tag, "Media player error: what=``what```, extra=``extra``");
        callback?.onError("MediaPlayer error ``what``` (``extra```)");
        return true;
    }

    MediaPlayer createMediaPlayerIfNeeded() {
//        LogHelper.d(tag, "createMediaPlayerIfNeeded. needed? ", !mediaPlayer exists);
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
//        LogHelper.d(tag, "relaxResources. releaseMediaPlayer=", releaseMediaPlayer);
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
