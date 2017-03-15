import android.content {
    Intent,
    IntentFilter,
    BroadcastReceiver,
    Context
}
import android.media {
    AudioManager,
    MediaPlayer
}
import android.net.wifi {
    WifiManager
}
import android.os {
    PowerManager
}
import android.support.v4.media.session {
    PlaybackStateCompat,
    MediaSessionCompat
}

import com.example.android.uamp {
    MusicService
}
import com.example.android.uamp.model {
    customMetadataTrackSource,
    MusicProvider
}
import com.example.android.uamp.utils {
    MediaIDHelper
}

import java.io {
    IOException
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
                & AudioManager.OnAudioFocusChangeListener {

//    value tag = LogHelper.makeLogTag(`LocalPlayback`);

    variable Boolean playOnFocusGain = false;
    variable Boolean noisyReceiverRegistered = false;
    variable Integer currentPosition = 0;
    variable AudioFocus audioFocus = AudioFocus.noFocusNoDuck;
    variable MediaPlayer? mediaPlayer = null;

    shared actual variable Callback? callback = null;

    value noisyIntentFilter = IntentFilter(AudioManager.actionAudioBecomingNoisy);

    assert (is AudioManager audioManager = context.getSystemService(Context.audioService));
    assert (is WifiManager wifiManager = context.getSystemService(Context.wifiService));
    value wifiLock = wifiManager.createWifiLock(WifiManager.wifiModeFull, "uAmp_lock");

    shared actual variable Integer state = PlaybackStateCompat.stateNone;

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
        state = PlaybackStateCompat.stateStopped;
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

    shared actual void play(MediaSessionCompat.QueueItem item) {
        playOnFocusGain = true;
        tryToGetAudioFocus();
        registerAudioNoisyReceiver();
        value mediaId = item.description.mediaId;
        value mediaHasChanged = !MediaIDHelper.equalIds(mediaId, currentMediaId);
        if (mediaHasChanged) {
            currentPosition = 0;
            currentMediaId = mediaId;
        }
        if (state == PlaybackStateCompat.statePaused,
            !mediaHasChanged,
            exists player = mediaPlayer) {
            configMediaPlayerState(player);
        } else {
            state = PlaybackStateCompat.stateStopped;
            relaxResources(false);
            assert (exists id = item.description.mediaId,
                    exists musicId = MediaIDHelper.extractMusicIDFromMediaID(id));
            value track = musicProvider.getMusic(musicId);
            value source = track?.getString(customMetadataTrackSource)?.replace(" ", "%20");
            try {
                value player = createMediaPlayerIfNeeded();
                state = PlaybackStateCompat.stateBuffering;
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
        if (state == PlaybackStateCompat.statePlaying) {
            if (exists player = mediaPlayer, player.playing) {
                player.pause();
                currentPosition = player.currentPosition;
            }
            relaxResources(false);
        }
        state = PlaybackStateCompat.statePaused;
        callback?.onPlaybackStatusChanged(state);
        unregisterAudioNoisyReceiver();
    }

    shared actual void seekTo(Integer position) {
//        LogHelper.d(tag, "seekTo called with ", position);
        if (exists player = mediaPlayer) {
            if (player.playing) {
                state = PlaybackStateCompat.stateBuffering;
            }
            registerAudioNoisyReceiver();
            player.seekTo(position);
            callback?.onPlaybackStatusChanged(state);
        } else {
            currentPosition = position;
        }
    }

    void tryToGetAudioFocus() {
//        LogHelper.d(tag, "tryToGetAudioFocus");
        value result
                = audioManager.requestAudioFocus(this,
                    AudioManager.streamMusic, AudioManager.audiofocusGain);
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

    void configMediaPlayerState(MediaPlayer player) {
//        LogHelper.d(tag, "configMediaPlayerState. mAudioFocus=", audioFocus);

        if (audioFocus == AudioFocus.noFocusNoDuck) {
            if (state == PlaybackStateCompat.statePlaying) {
                pause();
            }
        } else {
            registerAudioNoisyReceiver();
            value volume = audioFocus.volume;
            player.setVolume(volume, volume);
            if (playOnFocusGain) {
                if (!player.playing) {
//                    LogHelper.d(tag, "configMediaPlayerState startMediaPlayer. seeking to ", currentPosition);

                    if (currentPosition == player.currentPosition) {
                        player.start();
                        state = PlaybackStateCompat.statePlaying;
                    } else {
                        player.seekTo(currentPosition);
                        state = PlaybackStateCompat.stateBuffering;
                    }
                }
                playOnFocusGain = false;
            }
        }
        callback?.onPlaybackStatusChanged(state);
    }

    suppressWarnings("caseNotDisjoint")
    shared actual void onAudioFocusChange(Integer focusChange) {
//        LogHelper.d(tag, "onAudioFocusChange. focusChange=", focusChange);
        switch (focusChange)
        case (AudioManager.audiofocusGain) {
            audioFocus = AudioFocus.focused;
        }
        case (AudioManager.audiofocusLoss
            | AudioManager.audiofocusLossTransient
            | AudioManager.audiofocusLossTransientCanDuck) {
            value canDuck = focusChange == AudioManager.audiofocusLossTransientCanDuck;
            audioFocus = canDuck then AudioFocus.noFocusCanDuck else AudioFocus.noFocusNoDuck;
            if (state == PlaybackStateCompat.statePlaying, !canDuck) {
                playOnFocusGain = true;
            }
        }
        else {
//            LogHelper.e(tag, "onAudioFocusChange: Ignoring unsupported focusChange: ", focusChange);
        }

        if (exists player = mediaPlayer) {
            configMediaPlayerState(player);
        }
    }

    MediaPlayer createMediaPlayerIfNeeded() {
//        LogHelper.d(tag, "createMediaPlayerIfNeeded. needed? ", !mediaPlayer exists);

        MediaPlayer player;
        if (exists mediaPlayer = this.mediaPlayer) {
            player = mediaPlayer;
            player.reset();
        } else {
            player = MediaPlayer();
            mediaPlayer = player;
        }

        player.setWakeMode(context.applicationContext, PowerManager.partialWakeLock);

        player.setOnPreparedListener(configMediaPlayerState);

        player.setOnCompletionListener((player) {
            callback?.onCompletion();
        });

        player.setOnErrorListener((player, what, extra) {
            callback?.onError("MediaPlayer error ``what``` (``extra```)");
            return true;
        });

        player.setOnSeekCompleteListener((player) {
            currentPosition = player.currentPosition;
            if (state == PlaybackStateCompat.stateBuffering) {
                registerAudioNoisyReceiver();
                player.start();
                state = PlaybackStateCompat.statePlaying;
            }
            callback?.onPlaybackStatusChanged(state);
        });

        return player;
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
