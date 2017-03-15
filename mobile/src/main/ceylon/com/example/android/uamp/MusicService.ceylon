import android.app {
    PendingIntent
}
import android.content {
    BroadcastReceiver,
    Context,
    Intent,
    IntentFilter
}
import android.os {
    Bundle,
    Handler,
    Message
}
import android.support.v4.media {
    MediaBrowserService=MediaBrowserServiceCompat,
    MediaMetadata=MediaMetadataCompat,
    MediaBrowser=MediaBrowserCompat
}
import android.support.v4.media.session {
    MediaButtonReceiver,
    MediaSession=MediaSessionCompat,
    PlaybackState=PlaybackStateCompat
}
import android.support.v7.media {
    MediaRouter
}

import com.example.android.uamp.model {
    MusicProvider
}
import com.example.android.uamp.playback {
    LocalPlayback,
    PlaybackManager,
    PlaybackServiceCallback,
    QueueManager,
    MetadataUpdateListener,
    CastPlayback
}
import com.example.android.uamp.ui {
    NowPlayingActivity
}
import com.example.android.uamp.utils {
    CarHelper,
    WearHelper,
    MediaIDHelper,
    tvUiMode
}
import com.google.android.gms.cast.framework {
    CastContext,
    CastSession,
    SessionManagerListener,
    SessionManager
}

import java.lang.ref {
    WeakReference
}
import java.util {
    List,
    Collections
}

shared class MusicService
        extends MediaBrowserService
        satisfies PlaybackServiceCallback {

    static shared String extraConnectedCast = "com.example.android.uamp.CAST_NAME";
    static shared String actionCmd = "com.example.android.uamp.ACTION_CMD";
    static shared String cmdName = "CMD_NAME";
    static shared String cmdPause = "CMD_PAUSE";
    static shared String cmdStopCasting = "CMD_STOP_CASTING";

    static value stopDelay = 30000;

    static class DelayedStopHandler(MusicService service)
            extends Handler() {
        value serviceReference = WeakReference(service);
        shared actual void handleMessage(Message msg) {
            if (exists service = serviceReference.get(),
                !service.playbackManager.playback.playing) {
                service.stopSelf();
            }
        }
    }

    shared new () extends MediaBrowserService() {}

//    value tag = LogHelper.makeLogTag(`MusicService`);

    late MusicProvider musicProvider;
    late PackageValidator packageValidator;
    late MediaNotificationManager mediaNotificationManager;
    late PlaybackManager playbackManager;
    late MediaSession session;
    late Bundle sessionExtras;
    late MediaRouter mediaRouter;

    late SessionManager? castSessionManager;
    late SessionManagerListener<CastSession>? castSessionManagerListener;

    late Handler delayedStopHandler;

    variable Boolean connectedToCar;
    variable BroadcastReceiver? carConnectionReceiver = null;

    shared MediaSession.Token? currentToken {
//        assert (is MediaSession.Token? token = sessionToken?.token);
//        return token;
        return sessionToken;
    }

    shared actual void onCreate() {
        super.onCreate();

        delayedStopHandler = DelayedStopHandler(this);

//        LogHelper.d(tag, "onCreate");
        musicProvider = MusicProvider();
        musicProvider.retrieveMediaAsync(noop);
        packageValidator = PackageValidator(this);
        playbackManager
                = PlaybackManager(this, resources, musicProvider,
                    QueueManager(musicProvider, resources,
                        object satisfies MetadataUpdateListener {
                            onMetadataChanged(MediaMetadata metadata)
                                    => session.setMetadata(metadata);
                            onMetadataRetrieveError()
                                    => playbackManager.updatePlaybackState(
                                        getString(R.String.error_no_metadata));
                            onCurrentQueueIndexUpdated(Integer queueIndex)
                                    => playbackManager.handlePlayRequest();
                            shared actual void onQueueUpdated(String title,
                                    List<MediaSession.QueueItem>? newQueue) {
                                session.setQueue(newQueue);
                                session.setQueueTitle(title);
                            }
                        }),
                    LocalPlayback(this, musicProvider));
        sessionExtras = Bundle();
        CarHelper.setSlotReservationFlags(sessionExtras, true, true, true);
        WearHelper.setSlotReservationFlags(sessionExtras, true, true);
        WearHelper.setUseBackgroundFromTheme(sessionExtras, true);

        session = MediaSession(this, "MusicService");
//        session = MediaSession.fromMediaSession(this, sess);
//        assert (is MediaSession.Token token = session.sessionToken.token);
//        sessionToken = session.sessionToken;
//        session.setCallback(playbackManager);
        sessionToken = session.sessionToken;
        session.setCallback(playbackManager);
        session.setFlags(MediaSession.flagHandlesMediaButtons.or(MediaSession.flagHandlesTransportControls));
        value intent = Intent(applicationContext, `NowPlayingActivity`);
        value pi = PendingIntent.getActivity(applicationContext, 99, intent, PendingIntent.flagUpdateCurrent);
        session.setSessionActivity(pi);
        session.setExtras(sessionExtras);

        playbackManager.updatePlaybackState(null);

        mediaNotificationManager = MediaNotificationManager(this);
        if (!tvUiMode(this)) {
            value manager = CastContext.getSharedInstance(this).sessionManager;
            castSessionManager = manager;
            castSessionManagerListener
                    = object satisfies SessionManagerListener<CastSession> {

                shared actual void onSessionEnded(CastSession session, Integer error) {
                    sessionExtras.remove(extraConnectedCast);
                    outer.session.setExtras(sessionExtras);
                    value playback = LocalPlayback(outer, musicProvider);
                    mediaRouter.setMediaSession(null);
                    playbackManager.switchToPlayback(playback, false);
                }

                shared actual void onSessionStarted(CastSession session, String sessionId) {
                    sessionExtras.putString(extraConnectedCast, session.castDevice.friendlyName);
                    outer.session.setExtras(sessionExtras);
                    value playback = CastPlayback(musicProvider, outer);
                    mediaRouter.setMediaSession(session);
                    playbackManager.switchToPlayback(playback, true);
                }

                shared actual void onSessionEnding(CastSession session)
                        => playbackManager.playback.updateLastKnownStreamPosition();

                shared actual void onSessionResumed(CastSession session, Boolean wasSuspended) {}
                shared actual void onSessionStarting(CastSession session) {}
                shared actual void onSessionStartFailed(CastSession session, Integer error) {}
                shared actual void onSessionResuming(CastSession session, String sessionId) {}
                shared actual void onSessionResumeFailed(CastSession session, Integer error) {}
                shared actual void onSessionSuspended(CastSession session, Integer reason) {}

            };
            manager.addSessionManagerListener(castSessionManagerListener, `CastSession`);
        }
        else {
            castSessionManager = null;
            castSessionManagerListener = null;
        }

        mediaRouter = MediaRouter.getInstance(applicationContext);
        registerCarConnectionReceiver();
    }

    suppressWarnings("caseNotDisjoint")
    shared actual Integer onStartCommand(Intent? startIntent, Integer flags, Integer startId) {
        if (exists startIntent) {
            if (exists action = startIntent.action,
                actionCmd==action) {
                switch (command = startIntent.getStringExtra(cmdName))
                case (cmdPause) {
                    playbackManager.handlePauseRequest();
                }
                case (cmdStopCasting) {
                    CastContext.getSharedInstance(this).sessionManager.endCurrentSession(true);
                }
                else {}
            } else {
                MediaButtonReceiver.handleIntent(session, startIntent);
            }
        }
        delayedStopHandler.removeCallbacksAndMessages(null);
        delayedStopHandler.sendEmptyMessageDelayed(0, stopDelay);
        return startSticky;
    }

    shared actual void onDestroy() {
//        LogHelper.d(tag, "onDestroy");
        unregisterReceiver(carConnectionReceiver);
        playbackManager.handleStopRequest(null);
        mediaNotificationManager.stopNotification();
        castSessionManager?.removeSessionManagerListener(castSessionManagerListener, `CastSession`);
        delayedStopHandler.removeCallbacksAndMessages(null);
        session.release();
    }

    shared actual BrowserRoot onGetRoot(String clientPackageName, Integer clientUid, Bundle rootHints) {
//        LogHelper.d(tag, "OnGetRoot: clientPackageName=" + clientPackageName, "; clientUid=" + clientUid + " ; rootHints=", rootHints);
        if (!packageValidator.isCallerAllowed(this, clientPackageName, clientUid)) {
//            LogHelper.i(tag, "OnGetRoot: Browsing NOT ALLOWED for unknown caller. " + "Returning empty browser root so all apps can use MediaController." + clientPackageName);
            return BrowserRoot(MediaIDHelper.mediaIdEmptyRoot, null);
        }
//        if (CarHelper.isValidCarPackage(clientPackageName)) {
//        }
//        if (WearHelper.isValidWearCompanionPackage(clientPackageName)) {
//        }
        return BrowserRoot(MediaIDHelper.mediaIdRoot, null);
    }

//    function repackage(MediaBrowser.MediaItem* list)
//            => Arrays.asList(for (item in list)
//                    MediaBrowser.MediaItem.fromMediaItem(item));

    shared actual void onLoadChildren(String parentMediaId,
            Result<List<MediaBrowser.MediaItem>> result) {
//        LogHelper.d(tag, "OnLoadChildren: parentMediaId=", parentMediaId);
        if (MediaIDHelper.mediaIdEmptyRoot == parentMediaId) {
            result.sendResult(Collections.emptyList<MediaBrowser.MediaItem>());
        } else if (musicProvider.initialized) {
            result.sendResult(musicProvider.getChildren(parentMediaId, resources));
        } else {
            result.detach();
            musicProvider.retrieveMediaAsync((success)
                    => result.sendResult(musicProvider.getChildren(parentMediaId, resources)));
        }
    }

    shared actual void onPlaybackStart() {
        session.active = true;
        delayedStopHandler.removeCallbacksAndMessages(null);
        startService(Intent(applicationContext, `MusicService`));
    }

    shared actual void onPlaybackStop() {
        session.active = false;
        delayedStopHandler.removeCallbacksAndMessages(null);
        delayedStopHandler.sendEmptyMessageDelayed(0, stopDelay);
        stopForeground(true);
    }

    shared actual void onNotificationRequired()
            => mediaNotificationManager.startNotification();

    shared actual void onPlaybackStateUpdated(PlaybackState newState)
            => session.setPlaybackState(newState);
//            => session.setPlaybackState(PlaybackStateCompat.fromPlaybackState(newState));

    void registerCarConnectionReceiver() {
        value filter = IntentFilter(CarHelper.actionMediaStatus);
        carConnectionReceiver
                = object extends BroadcastReceiver() {
                    onReceive(Context context, Intent intent)
                            => connectedToCar
                                = CarHelper.mediaConnected
                                == intent.getStringExtra(CarHelper.mediaConnectionStatus);
                };
        registerReceiver(carConnectionReceiver, filter);
    }

}
