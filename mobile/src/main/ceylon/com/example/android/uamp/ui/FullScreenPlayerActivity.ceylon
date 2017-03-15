import android.content {
    ComponentName,
    Intent
}
import android.graphics.drawable {
    Drawable
}
import android.os {
    Bundle,
    Handler,
    RemoteException,
    SystemClock
}
import android.support.v4.media {
    MediaMetadataCompat,
    MediaDescriptionCompat,
    MediaBrowserCompat
}
import android.support.v4.media.session {
    PlaybackStateCompat,
    MediaControllerCompat,
    MediaSessionCompat
}
import android.text.format {
    DateUtils
}
import android.view {
    View {
        invisible,
        visible
    }
}
import android.widget {
    ImageView,
    ProgressBar,
    SeekBar,
    TextView
}

import com.example.android.uamp {
    AlbumArtCache,
    MusicService,
    R
}

import java.util.concurrent {
    Executors,
    ScheduledFuture,
    TimeUnit
}

shared class FullScreenPlayerActivity()
        extends ActionBarCastActivity() {

//    value tag = LogHelper.makeLogTag(`FullScreenPlayerActivity`);

    value progressUpdateInternal = 1000;
    value progressUpdateInitialInterval = 100;

    late ImageView mSkipPrev;
    late ImageView mSkipNext;
    late ImageView mPlayPause;

    late TextView mStart;
    late TextView mEnd;
    late SeekBar mSeekbar;
    late TextView mLine1;
    late TextView mLine2;
    late TextView mLine3;
    late ProgressBar mLoading;
    late View mControllers;
    late Drawable mPauseDrawable;
    late Drawable mPlayDrawable;
    late ImageView mBackgroundImage;
    late MediaBrowserCompat mMediaBrowser;

    variable String mCurrentArtUrl;

    value mHandler = Handler();
    value mExecutorService = Executors.newSingleThreadScheduledExecutor();

    variable ScheduledFuture<out Object>? mScheduleFuture = null;
    variable PlaybackStateCompat? mLastPlaybackStateCompat = null;

    void updateProgress() {
        if (exists playbackState = mLastPlaybackStateCompat) {
            Integer currentPosition;
            if (playbackState.state != PlaybackStateCompat.statePaused) {
                value timeDelta
                        = SystemClock.elapsedRealtime()
                        - playbackState.lastPositionUpdateTime;
                currentPosition
                        = playbackState.position
                        + (timeDelta * playbackState.playbackSpeed).integer;
            }
            else {
                currentPosition = playbackState.position;
            }
            mSeekbar.progress = currentPosition;
        }
    }

    void stopSeekbarUpdate() => mScheduleFuture?.cancel(false);

    void scheduleSeekbarUpdate() {
        stopSeekbarUpdate();
        if (!mExecutorService.shutdown) {
            mScheduleFuture
                    = mExecutorService.scheduleAtFixedRate(() => mHandler.post(updateProgress),
                        progressUpdateInitialInterval, progressUpdateInternal,
                        TimeUnit.milliseconds);
        }
    }

    suppressWarnings("caseNotDisjoint")
    void updatePlaybackStateCompat(PlaybackStateCompat state) {
        mLastPlaybackStateCompat = state;
        if (exists extras = mediaController?.extras) {
            value line3Text
                    = if (exists castName= extras.getString(MusicService.extraConnectedCast))
                    then resources.getString(R.String.casting_to_device, castName)
                    else "";
            mLine3.setText(line3Text);
        }

        switch (state.state)
        case (PlaybackStateCompat.statePlaying) {
            mLoading.visibility = invisible;
            mPlayPause.visibility = visible;
            mPlayPause.setImageDrawable(mPauseDrawable);
            mControllers.visibility = visible;
            scheduleSeekbarUpdate();
        }
        case (PlaybackStateCompat.statePaused) {
            mControllers.visibility = visible;
            mLoading.visibility = invisible;
            mPlayPause.visibility = visible;
            mPlayPause.setImageDrawable(mPlayDrawable);
            stopSeekbarUpdate();
        }
        case (PlaybackStateCompat.stateNone |
              PlaybackStateCompat.stateStopped) {
            mLoading.visibility = invisible;
            mPlayPause.visibility = visible;
            mPlayPause.setImageDrawable(mPlayDrawable);
            stopSeekbarUpdate();
        }
        case (PlaybackStateCompat.stateBuffering) {
            mPlayPause.visibility = invisible;
            mLoading.visibility = visible;
            mLine3.setText(R.String.loading);
            stopSeekbarUpdate();
        }
        else {
//            LogHelper.d(tag, "Unhandled state ", state.state);
        }
        mSkipNext.setVisibility(state.actions.and(PlaybackStateCompat.actionSkipToNext) == 0
                                then invisible else visible);
        mSkipPrev.setVisibility(state.actions.and(PlaybackStateCompat.actionSkipToPrevious) == 0
                                then invisible else visible);
    }

    void fetchImageAsync(MediaDescriptionCompat description) {
        if (exists uri = description.iconUri) {
            value artUrl = uri.string;
            mCurrentArtUrl = artUrl;
            if (exists art
                    = AlbumArtCache.instance.getBigImage(artUrl)
                    else description.iconBitmap) {
                mBackgroundImage.setImageBitmap(art);
            } else {
                AlbumArtCache.instance.fetch(artUrl, (artUrl, bitmap, icon) {
                    if (exists artUrl, artUrl == mCurrentArtUrl) {
                        mBackgroundImage.setImageBitmap(bitmap);
                    }
                });
            }
        }
    }

    void updateMediaDescription(MediaDescriptionCompat? description) {
        if (exists description) {
//            LogHelper.d(tag, "updateMediaDescription called ");
            mLine1.setText(description.title);
            mLine2.setText(description.subtitle);
            fetchImageAsync(description);
        }
    }

    void updateDuration(MediaMetadataCompat? metadata) {
        if (exists metadata) {
//            LogHelper.d(tag, "updateDuration called ");
            value duration = metadata.getLong(MediaMetadataCompat.metadataKeyDuration);
            mSeekbar.setMax(duration);
            mEnd.setText(DateUtils.formatElapsedTime(duration / 1000));
        }
    }

    object callback extends MediaControllerCompat.Callback() {
        shared actual void onPlaybackStateChanged(PlaybackStateCompat state) {
//            LogHelper.d(tag, "onPlaybackStateCompat changed", state);
            updatePlaybackStateCompat(state);
        }
        shared actual void onMetadataChanged(MediaMetadataCompat? metadata) {
            if (exists metadata) {
                updateMediaDescription(metadata.description);
                updateDuration(metadata);
            }
        }
    }

    void connectToSession(MediaSessionCompat.Token token) {
        value mediaController = MediaControllerCompat(this, token);
        if (exists metadata = mediaController.metadata) {
            MediaControllerCompat.setMediaController(this, mediaController);
            mediaController.registerCallback(callback);
            value state = mediaController.playbackState;
            updatePlaybackStateCompat(state);
            updateMediaDescription(metadata.description);
            updateDuration(metadata);
            updateProgress();
            if (state exists,
                state.state == PlaybackStateCompat.statePlaying
                || state.state == PlaybackStateCompat.stateBuffering) {
                scheduleSeekbarUpdate();
            }
        }
        else {
            finish();
        }
    }

    suppressWarnings("caseNotDisjoint")
    shared actual void onCreate(Bundle? savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.Layout.activity_full_player);
        initializeToolbar();
        if (exists bar = supportActionBar) {
            bar.setDisplayHomeAsUpEnabled(true);
            bar.setTitle("");
        }
        assert (is ImageView backgroundImage = findViewById(R.Id.background_image));
        mBackgroundImage = backgroundImage;
        mPauseDrawable = getDrawable(R.Drawable.uamp_ic_pause_white_48dp);
        mPlayDrawable = getDrawable(R.Drawable.uamp_ic_play_arrow_white_48dp);
        assert (is ImageView playPause = findViewById(R.Id.play_pause));
        mPlayPause = playPause;
        assert (is ImageView skipNext = findViewById(R.Id.next));
        mSkipNext = skipNext;
        assert (is ImageView skipPrev = findViewById(R.Id.prev));
        mSkipPrev = skipPrev;
        assert (is TextView start = findViewById(R.Id.startText));
        mStart = start;
        assert (is TextView end = findViewById(R.Id.endText));
        mEnd = end;
        assert (is SeekBar seekbar = findViewById(R.Id.seekBar1));
        mSeekbar = seekbar;
        assert (is TextView line1 = findViewById(R.Id.line1));
        mLine1 = line1;
        assert (is TextView line2 = findViewById(R.Id.line2));
        mLine2 = line2;
        assert (is TextView line3 = findViewById(R.Id.line3));
        mLine3 = line3;
        assert (is ProgressBar progress = findViewById(R.Id.progressBar1));
        mLoading = progress;
        mControllers = findViewById(R.Id.controllers);

        mSkipNext.setOnClickListener((v) => mediaController.transportControls.skipToNext());
        mSkipPrev.setOnClickListener((v) => mediaController.transportControls.skipToPrevious());

        mPlayPause.setOnClickListener((v) {
            if (exists state = mediaController.playbackState) {
                value controls = mediaController.transportControls;
                switch (state.state)
                case (PlaybackStateCompat.statePlaying
                    | PlaybackStateCompat.stateBuffering) {
                    controls.pause();
                    stopSeekbarUpdate();
                }
                case (PlaybackStateCompat.statePaused
                    | PlaybackStateCompat.stateStopped) {
                    controls.play();
                    scheduleSeekbarUpdate();
                }
                else {
//                    LogHelper.d(tag, "onClick with state ", state.state);
                }
            }
        });

        mSeekbar.setOnSeekBarChangeListener(object satisfies SeekBar.OnSeekBarChangeListener {
            shared actual void onProgressChanged(SeekBar seekBar, Integer progress, Boolean fromUser)
                    => mStart.setText(DateUtils.formatElapsedTime(progress / 1000));
            shared actual void onStartTrackingTouch(SeekBar seekBar)
                    => stopSeekbarUpdate();
            shared actual void onStopTrackingTouch(SeekBar seekBar) {
                mediaController.transportControls.seekTo(seekBar.progress);
                scheduleSeekbarUpdate();
            }
        });

        if (!exists savedInstanceState) {
            updateFromParams(intent);
        }

        mMediaBrowser
                = MediaBrowserCompat(this,
                    ComponentName(this, `MusicService`),
                    object extends MediaBrowserCompat.ConnectionCallback() {
                        shared actual void onConnected() {
//                            LogHelper.d(tag, "onConnected");
                            try {
                                connectToSession(mMediaBrowser.sessionToken);
                            }
                            catch (RemoteException e) {
                                //LogHelper.e(tag, e, "could not connect media controller");
                            }
                        }
                    },
                    null);
    }

    void updateFromParams(Intent? intent) {
        if (exists description
                    = intent?.getParcelableExtra<MediaDescriptionCompat>
                    (MusicPlayerActivity.extraCurrentMediaDescription)) {
            updateMediaDescription(description);
        }
    }

    shared actual void onStart() {
        super.onStart();
        mMediaBrowser.connect();
    }

    shared actual void onStop() {
        super.onStop();
        mMediaBrowser.disconnect();
        MediaControllerCompat.getMediaController(this)?.unregisterCallback(callback);
    }

    shared actual void onDestroy() {
        super.onDestroy();
        stopSeekbarUpdate();
        mExecutorService.shutdown();
    }

}
