import android.app {
    Notification,
    PendingIntent,
    NotificationManager
}
import android.content {
    BroadcastReceiver,
    Context,
    Intent,
    IntentFilter
}
import android.graphics {
    Bitmap,
    BitmapFactory,
    Color
}
import android.media {
    MediaDescription,
    MediaMetadata
}
import android.media.session {
    MediaController,
    MediaSession,
    PlaybackState
}
import android.os {
    RemoteException
}

import com.example.android.uamp.ui {
    MusicPlayerActivity
}
import com.example.android.uamp.utils {
    themeColor
}

import java.lang {
    IllegalArgumentException,
    System
}
import java.util {
    Objects
}
import android.graphics.drawable {
    Icon
}

shared class MediaNotificationManager(MusicService service) {

    value notificationId = 412;
    value requestCode = 100;

    value actionPause = "com.example.android.uamp.pause";
    value actionPlay = "com.example.android.uamp.play";
    value actionPrev = "com.example.android.uamp.prev";
    value actionNext = "com.example.android.uamp.next";
    value actionStopCasting = "com.example.android.uamp.stop_cast";

//    value tag = LogHelper.makeLogTag(`MediaNotificationManager`);

    value notificationColor = themeColor(service, R.Attr.colorPrimary, Color.dkgray);
    value notificationManager = service.getSystemService(`NotificationManager`);
    notificationManager.cancelAll();

    value pkg = service.packageName;

    value pauseIntent = PendingIntent.getBroadcast(service, requestCode,
        Intent(actionPause).setPackage(pkg), PendingIntent.flagCancelCurrent);

    value playIntent = PendingIntent.getBroadcast(service, requestCode,
        Intent(actionPlay).setPackage(pkg), PendingIntent.flagCancelCurrent);

    value previousIntent = PendingIntent.getBroadcast(service, requestCode,
        Intent(actionPrev).setPackage(pkg), PendingIntent.flagCancelCurrent);

    value nextIntent = PendingIntent.getBroadcast(service, requestCode,
        Intent(actionNext).setPackage(pkg), PendingIntent.flagCancelCurrent);

    value stopCastIntent = PendingIntent.getBroadcast(service, requestCode,
        Intent(actionStopCasting).setPackage(pkg), PendingIntent.flagCancelCurrent);

    variable MediaSession.Token? sessionToken = null;
    variable MediaController? controller = null;
    variable MediaController.TransportControls? transportControls = null;
    variable MediaMetadata? metadata = null;
    variable PlaybackState? playbackState = null;

    variable Boolean started = false;

    function createAction(Integer icon, String label, PendingIntent intent)
            => Notification.Action.Builder(Icon.createWithResource("", icon), label, intent)
            .build();

    void addPlayPauseAction(Notification.Builder builder) {
//        LogHelper.d(tag, "updatePlayPauseAction");

        String label;
        Integer icon;
        PendingIntent intent;
        if (exists playback = playbackState,
            playback.state == PlaybackState.statePlaying) {
            label = service.getString(R.String.label_pause);
            icon = R.Drawable.uamp_ic_pause_white_24dp;
            intent = pauseIntent;
        } else {
            label = service.getString(R.String.label_play);
            icon = R.Drawable.uamp_ic_play_arrow_white_24dp;
            intent = playIntent;
        }

        builder.addAction(createAction(icon, label, intent));
    }

    function createContentIntent(MediaDescription? description) {
        value openUI = Intent(service, `MusicPlayerActivity`);
        openUI.setFlags(Intent.flagActivitySingleTop);
        openUI.putExtra(MusicPlayerActivity.extraStartFullscreen, true);
        if (exists description) {
            openUI.putExtra(MusicPlayerActivity.extraCurrentMediaDescription, description);
        }
        return PendingIntent.getActivity(service, requestCode, openUI, PendingIntent.flagCancelCurrent);
    }

    void setNotificationPlaybackState(Notification.Builder builder) {
        value playback = playbackState;

//        LogHelper.d(tag, "updateNotificationPlaybackState. mPlaybackState=" + mPlaybackState);
        if (!exists playback) {
//            LogHelper.d(tag, "updateNotificationPlaybackState. cancelling notification!");
            service.stopForeground(true);
            return;
        }
        if (!started) {
//            LogHelper.d(tag, "updateNotificationPlaybackState. cancelling notification!");
            service.stopForeground(true);
            return;
        }

        if (playback.state == PlaybackState.statePlaying, playback.position>=0) {
//            LogHelper.d(tag, "updateNotificationPlaybackState. updating playback position to ",
//                (System.currentTimeMillis() - playback.position) / 1000, " seconds");
            builder.setWhen(System.currentTimeMillis() - playback.position)
                .setShowWhen(true)
                .setUsesChronometer(true);
        } else {
//            LogHelper.d(tag, "updateNotificationPlaybackState. hiding playback position");
            builder.setWhen(0).setShowWhen(false).setUsesChronometer(false);
        }
        builder.setOngoing(playback.state == PlaybackState.statePlaying);
    }

    void fetchBitmapFromURLAsync(String bitmapUrl, Notification.Builder builder) {
        AlbumArtCache.instance.fetch(bitmapUrl, (artUrl, bitmap, icon) {
            if (exists artUrl,
                exists uri = metadata?.description?.iconUri,
                uri.string==artUrl) {
//                LogHelper.d(tag, "fetchBitmapFromURLAsync: set bitmap to ", artUrl);
                builder.setLargeIcon(bitmap);
                notificationManager.notify(notificationId, builder.build());
            }
        });
    }

    Notification? createNotification() {
//        LogHelper.d(tag, "updateNotificationMetadata. mMetadata=" + mMetadata);
        if (exists metadata = metadata,
            exists playbackState = playbackState) {

            value notificationBuilder = Notification.Builder(service);
            variable Integer playPauseButtonPosition = 0;
            if (playbackState.actions.and(PlaybackState.actionSkipToPrevious) != 0) {
                notificationBuilder.addAction(createAction(R.Drawable.ic_skip_previous_white_24dp,
                    service.getString(R.String.label_previous), previousIntent));
                playPauseButtonPosition = 1;
            }
            addPlayPauseAction(notificationBuilder);
            if (playbackState.actions.and(PlaybackState.actionSkipToNext) != 0) {
                notificationBuilder.addAction(createAction(R.Drawable.ic_skip_next_white_24dp,
                    service.getString(R.String.label_next), nextIntent));
            }

            value description = metadata.description;

            String? fetchArtUrl;
            Bitmap? art;
            if (exists artUrl = description.iconUri?.string) {
                if (exists image = AlbumArtCache.instance.getBigImage(artUrl)) {
                    art = image;
                    fetchArtUrl = null;
                } else {
                    fetchArtUrl = artUrl;
                    art = BitmapFactory.decodeResource(service.resources, R.Drawable.ic_default_art);
                }
            }
            else {
                fetchArtUrl = null;
                art = null;
            }

            notificationBuilder.setStyle(Notification.MediaStyle()
                .setShowActionsInCompactView(playPauseButtonPosition)
                .setMediaSession(sessionToken))
                .setColor(notificationColor).setSmallIcon(R.Drawable.ic_notification)
                .setVisibility(Notification.visibilityPublic)
                .setUsesChronometer(true)
                .setContentIntent(createContentIntent(description))
                .setContentTitle(description.title)
                .setContentText(description.subtitle)
                .setLargeIcon(art);
            if (exists castName = controller?.extras?.getString(MusicService.extraConnectedCast)) {
                String castInfo = service.resources.getString(R.String.casting_to_device, castName);
                notificationBuilder.setSubText(castInfo);
                notificationBuilder.addAction(createAction(R.Drawable.ic_close_black_24dp,
                    service.getString(R.String.stop_casting), stopCastIntent));
            }
            setNotificationPlaybackState(notificationBuilder);
            if (exists fetchArtUrl) {
                fetchBitmapFromURLAsync(fetchArtUrl, notificationBuilder);
            }
            return notificationBuilder.build();
        }
        else {
            return null;
        }
    }

    object broadcastReceiver extends BroadcastReceiver() {
        shared actual void onReceive(Context context, Intent intent) {
            value action = intent.action;

//            LogHelper.d(tag, "Received intent with action " + action);

            if (action == actionPause) {
                transportControls?.pause();
            } else if (action == actionPlay) {
                transportControls?.play();
            } else if (action == actionNext) {
                transportControls?.skipToNext();
            } else if (action == actionPrev) {
                transportControls?.skipToPrevious();
            } else if (action == actionStopCasting) {
                value i = Intent(context, `MusicService`);
                i.setAction(MusicService.actionCmd);
                i.putExtra(MusicService.cmdName, MusicService.cmdStopCasting);
                service.startService(i);
            } else {
//                LogHelper.w(tag, "Unknown intent ignored. Action=", action);
            }
        }
    }

    late MediaController.Callback mediaControllerCallback;

    shared void startNotification() {
        if (!started) {
            metadata = controller?.metadata;
            playbackState = controller?.playbackState;
            if (exists notification = createNotification()) {
                controller?.registerCallback(mediaControllerCallback);
                value filter = IntentFilter();
                filter.addAction(actionNext);
                filter.addAction(actionPause);
                filter.addAction(actionPlay);
                filter.addAction(actionPrev);
                filter.addAction(actionStopCasting);
                service.registerReceiver(broadcastReceiver, filter);
                service.startForeground(notificationId, notification);
                started = true;
            }
        }
    }

    shared void stopNotification() {
        if (started) {
            started = false;
            controller?.unregisterCallback(mediaControllerCallback);
            try {
                notificationManager.cancel(notificationId);
                service.unregisterReceiver(broadcastReceiver);
            }
            catch (IllegalArgumentException ex) {}
            service.stopForeground(true);
        }
    }

    shared void updateSessionToken(MusicService musicService) {
        value freshToken = musicService.sessionToken;
        if (!Objects.equals(sessionToken, freshToken)) {
            controller?.unregisterCallback(mediaControllerCallback);
            sessionToken = freshToken;
            if (exists freshToken) {
                controller = MediaController(musicService, freshToken);
                transportControls = controller?.transportControls;
                if (started) {
                    controller?.registerCallback(mediaControllerCallback);
                }
            }
        }
    }

    mediaControllerCallback = object extends MediaController.Callback() {

        shared actual void onPlaybackStateChanged(PlaybackState state) {
            playbackState = state;
//            LogHelper.d(tag, "Received new playback state", state);
            if (state.state == PlaybackState.stateStopped
             || state.state == PlaybackState.stateNone) {
                stopNotification();
            } else if (exists notification = createNotification()) {
                notificationManager.notify(notificationId, notification);
            }
        }

        shared actual void onMetadataChanged(MediaMetadata metadata) {
            outer.metadata = metadata;
//            LogHelper.d(tag, "Received new metadata ", metadata);
            if (exists notification = createNotification()) {
                notificationManager.notify(notificationId, notification);
            }
        }

        shared actual void onSessionDestroyed() {
//            LogHelper.d(tag, "Session was destroyed, resetting to the new session token");
            try {
                updateSessionToken(service);
            }
            catch (RemoteException e) {
                //LogHelper.e(tag, e, "could not connect media controller");
            }
        }
    };

    updateSessionToken(service);

}
