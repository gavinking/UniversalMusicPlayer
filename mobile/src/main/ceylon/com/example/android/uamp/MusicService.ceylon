import android.app {
    PendingIntent
}
import android.content {
    BroadcastReceiver,
    Context,
    Intent,
    IntentFilter
}
import android.media {
    MediaMetadata
}
import android.media.browse {
    MediaBrowser {
        MediaItem
    }
}
import android.media.session {
    MediaSession,
    PlaybackState
}
import android.os {
    Bundle,
    Handler,
    Message
}
import android.service.media {
    MediaBrowserService
}
import android.support.v4.media.session {
    MediaButtonReceiver,
    MediaSessionCompat
}
import android.support.v7.media {
    MediaRouter
}

import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.playback {
    CastPlayback,
    LocalPlayback,
    PlaybackManager,
    PlaybackServiceCallback,
    QueueManager,
    MetadataUpdateListener
}
import com.example.android.uamp.ui {
    NowPlayingActivity
}
import com.example.android.uamp.utils {
    LogHelper,
    CarHelper,
    TvHelper,
    WearHelper,
    MediaIDHelper
}
import com.google.android.gms.cast.framework {
    CastContext,
    CastSession,
    SessionManager,
    SessionManagerListener
}

import java.lang.ref {
    WeakReference
}
import java.util {
    ArrayList,
    List
}

shared class MusicService
        extends MediaBrowserService
        satisfies PlaybackServiceCallback {

    static shared String extraConnectedCast = "com.example.android.uamp.CAST_NAME";
    static shared String actionCmd = "com.example.android.uamp.ACTION_CMD";
    static shared String cmdName = "CMD_NAME";
    static shared String cmdPause = "CMD_PAUSE";
    static shared String cmdStopCasting = "CMD_STOP_CASTING";

    shared new () extends MediaBrowserService() {}

    value stopDelay = 30000;

    value tag = LogHelper.makeLogTag(`MusicService`);

    late MusicProvider mMusicProvider;
    late PackageValidator mPackageValidator;
    late MediaNotificationManager mMediaNotificationManager;
    late PlaybackManager mPlaybackManager;
    late MediaSession mSession;
    late Bundle mSessionExtras;
    late MediaRouter mMediaRouter;
    late SessionManager? mCastSessionManager;
    late SessionManagerListener<CastSession>? mCastSessionManagerListener;

    late Handler mDelayedStopHandler;

    variable Boolean mIsConnectedToCar;
    variable BroadcastReceiver? mCarConnectionReceiver = null;

    shared actual void onCreate() {
        super.onCreate();

        mDelayedStopHandler = object extends Handler() {
            value mWeakReference = WeakReference(service);
            shared actual void handleMessage(Message msg) {
                if (exists service = mWeakReference.get()) {
                    if (mPlaybackManager.playback.playing) {
                    //LogHelper.d(tag, "Ignoring delayed stop since the media player is in use.");
                        return;
                    }
                    //LogHelper.d(tag, "Stopping service with delay handler.");
                    stopSelf();
                }
            }
        };

        LogHelper.d(tag, "onCreate");
        mMusicProvider = MusicProvider();
        mMusicProvider.retrieveMediaAsync(noop);
        mPackageValidator = PackageValidator(this);

        value queueManager
                = QueueManager(mMusicProvider, resources,
            object satisfies MetadataUpdateListener {
                shared actual void onMetadataChanged(MediaMetadata metadata)
                        => mSession.setMetadata(metadata);
                shared actual void onMetadataRetrieveError()
                        => mPlaybackManager.updatePlaybackState(getString(R.String.error_no_metadata));
                shared actual void onCurrentQueueIndexUpdated(Integer queueIndex)
                        => mPlaybackManager.handlePlayRequest();
                shared actual void onQueueUpdated(String title, List<MediaSession.QueueItem>? newQueue) {
                    mSession.setQueue(newQueue);
                    mSession.setQueueTitle(title);
                }
            });
        mPlaybackManager
                = PlaybackManager(this, resources, mMusicProvider, queueManager,
                    LocalPlayback(this, mMusicProvider));
        mSessionExtras = Bundle();
        CarHelper.setSlotReservationFlags(mSessionExtras, true, true, true);
        WearHelper.setSlotReservationFlags(mSessionExtras, true, true);
        WearHelper.setUseBackgroundFromTheme(mSessionExtras, true);

        mSession = MediaSession(this, "MusicService");
        sessionToken = mSession.sessionToken;
        mSession.setCallback(mPlaybackManager);
        mSession.setFlags(MediaSession.flagHandlesMediaButtons.or(MediaSession.flagHandlesTransportControls));
        value intent = Intent(applicationContext, `NowPlayingActivity`);
        value pi = PendingIntent.getActivity(applicationContext, 99, intent, PendingIntent.flagUpdateCurrent);
        mSession.setSessionActivity(pi);
        mSession.setExtras(mSessionExtras);

        mPlaybackManager.updatePlaybackState(null);

        mMediaNotificationManager = MediaNotificationManager(this);
        if (!TvHelper.isTvUiMode(this)) {
            value manager = CastContext.getSharedInstance(this).sessionManager;
            mCastSessionManager = manager;
            mCastSessionManagerListener
                    = object satisfies SessionManagerListener<CastSession> {

                shared actual void onSessionEnded(CastSession session, Integer error) {
                    LogHelper.d(tag, "onSessionEnded");
                    mSessionExtras.remove(extraConnectedCast);
                    mSession.setExtras(mSessionExtras);
                    value playback = LocalPlayback(outer, mMusicProvider);
                    mMediaRouter.setMediaSession(null);
                    mPlaybackManager.switchToPlayback(playback, false);
                }

                shared actual void onSessionStarted(CastSession session, String sessionId) {
                    mSessionExtras.putString(extraConnectedCast, session.castDevice.friendlyName);
                    mSession.setExtras(mSessionExtras);
                    value playback = CastPlayback(mMusicProvider,outer);
                    mMediaRouter.setMediaSession(mSession);
                    mPlaybackManager.switchToPlayback(playback, true);
                }

                shared actual void onSessionEnding(CastSession session)
                        => mPlaybackManager.playback.updateLastKnownStreamPosition();

                shared actual void onSessionResumed(CastSession session, Boolean wasSuspended) {}
                shared actual void onSessionStarting(CastSession session) {}
                shared actual void onSessionStartFailed(CastSession session, Integer error) {}
                shared actual void onSessionResuming(CastSession session, String sessionId) {}
                shared actual void onSessionResumeFailed(CastSession session, Integer error) {}
                shared actual void onSessionSuspended(CastSession session, Integer reason) {}

            };
            manager.addSessionManagerListener(mCastSessionManagerListener, `CastSession`);
        }
        else {
            mCastSessionManager = null;
            mCastSessionManagerListener = null;
        }

        mMediaRouter = MediaRouter.getInstance(applicationContext);
        registerCarConnectionReceiver();
    }

    shared actual Integer onStartCommand(Intent? startIntent, Integer flags, Integer startId) {
        if (exists startIntent) {
            if (exists action = startIntent.action,
                actionCmd==action) {
                value command = startIntent.getStringExtra(cmdName);
                if (cmdPause==command) {
                    mPlaybackManager.handlePauseRequest();
                } else if (cmdStopCasting==command) {
                    CastContext.getSharedInstance(this).sessionManager.endCurrentSession(true);
                }
            } else {
                MediaButtonReceiver.handleIntent(MediaSessionCompat.fromMediaSession(this, mSession), startIntent);
            }
        }
        mDelayedStopHandler.removeCallbacksAndMessages(null);
        mDelayedStopHandler.sendEmptyMessageDelayed(0, stopDelay);
        return startSticky;
    }

    shared actual void onDestroy() {
        LogHelper.d(tag, "onDestroy");
        unregisterCarConnectionReceiver();
        mPlaybackManager.handleStopRequest(null);
        mMediaNotificationManager.stopNotification();
        if (exists mCastSessionManager) {
            mCastSessionManager.removeSessionManagerListener(mCastSessionManagerListener, `CastSession`);
        }
        mDelayedStopHandler.removeCallbacksAndMessages(null);
        mSession.release();
    }

    shared actual BrowserRoot onGetRoot(String clientPackageName, Integer clientUid, Bundle rootHints) {
//        LogHelper.d(tag, "OnGetRoot: clientPackageName=" + clientPackageName, "; clientUid=" + clientUid + " ; rootHints=", rootHints);
        if (!mPackageValidator.isCallerAllowed(this, clientPackageName, clientUid)) {
            LogHelper.i(tag, "OnGetRoot: Browsing NOT ALLOWED for unknown caller. " + "Returning empty browser root so all apps can use MediaController." + clientPackageName);
            return MediaBrowserService.BrowserRoot(MediaIDHelper.mediaIdEmptyRoot, null);
        }
//        if (CarHelper.isValidCarPackage(clientPackageName)) {
//        }
//        if (WearHelper.isValidWearCompanionPackage(clientPackageName)) {
//        }
        return BrowserRoot(MediaIDHelper.mediaIdRoot, null);
    }

    shared actual void onLoadChildren(String parentMediaId,
            MediaBrowserService.Result<List<MediaBrowser.MediaItem>> result) {
        LogHelper.d(tag, "OnLoadChildren: parentMediaId=", parentMediaId);
        if (MediaIDHelper.mediaIdEmptyRoot==parentMediaId) {
            result.sendResult(ArrayList<MediaItem>());
        } else if (mMusicProvider.initialized) {
            result.sendResult(mMusicProvider.getChildren(parentMediaId, resources));
        } else {
            result.detach();
            mMusicProvider.retrieveMediaAsync((success)
                    => result.sendResult(mMusicProvider.getChildren(parentMediaId, resources)));
        }
    }

    shared actual void onPlaybackStart() {
        mSession.active = true;
        mDelayedStopHandler.removeCallbacksAndMessages(null);
        startService(Intent(applicationContext, `MusicService`));
    }

    shared actual void onPlaybackStop() {
        mSession.active = false;
        mDelayedStopHandler.removeCallbacksAndMessages(null);
        mDelayedStopHandler.sendEmptyMessageDelayed(0, stopDelay);
        stopForeground(true);
    }

    shared actual void onNotificationRequired()
            => mMediaNotificationManager.startNotification();

    shared actual void onPlaybackStateUpdated(PlaybackState newState)
            => mSession.setPlaybackState(newState);

    void registerCarConnectionReceiver() {
        value filter = IntentFilter(CarHelper.actionMediaStatus);
        mCarConnectionReceiver = object extends BroadcastReceiver() {
            shared actual void onReceive(Context context, Intent intent) {
                String connectionEvent = intent.getStringExtra(CarHelper.mediaConnectionStatus);
                mIsConnectedToCar = CarHelper.mediaConnected==connectionEvent;
                LogHelper.i(tag, "Connection event to Android Auto: ", connectionEvent, " isConnectedToCar=", mIsConnectedToCar);
            }
        };
        registerReceiver(mCarConnectionReceiver, filter);
    }

    void unregisterCarConnectionReceiver()
            => unregisterReceiver(mCarConnectionReceiver);

}
