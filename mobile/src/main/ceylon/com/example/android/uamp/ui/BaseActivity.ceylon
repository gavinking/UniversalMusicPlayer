import android {
    AndroidR=R
}
import android.app {
    ActivityManager
}
import android.content {
    ComponentName,
    Context
}
import android.graphics {
    BitmapFactory
}
import android.net {
    ConnectivityManager
}
import android.os {
    Bundle,
    Build,
    RemoteException
}
import android.support.v4.media {
    MediaMetadataCompat,
    MediaBrowserCompat
}
import android.support.v4.media.session {
    PlaybackStateCompat,
    MediaControllerCompat,
    MediaSessionCompat
}

import com.example.android.uamp {
    R,
    MusicService
}
import com.example.android.uamp.utils {
    themeColor
}

shared abstract class BaseActivity()
        extends ActionBarCastActivity()
        satisfies MediaBrowserProvider {

//    value tag = LogHelper.makeLogTag(`BaseActivity`);

    shared actual late MediaBrowserCompat mediaBrowser;
    shared variable PlaybackControlsFragment? controlsFragment = null;

    shared Boolean online {
        assert (is ConnectivityManager connMgr
                = getSystemService(Context.connectivityService));
        return if (exists networkInfo = connMgr.activeNetworkInfo)
            then networkInfo.connected
            else false;
    }

    void showPlaybackControls() {
//        LogHelper.d(tag, "showPlaybackControls");
        if (online) {
            fragmentManager.beginTransaction()
                .setCustomAnimations(
                R.Animator.slide_in_from_bottom,
                R.Animator.slide_out_to_bottom,
                R.Animator.slide_in_from_bottom,
                R.Animator.slide_out_to_bottom)
                .show(controlsFragment)
                .commit();
        }
    }

    void hidePlaybackControls() {
//        LogHelper.d(tag, "hidePlaybackControls");
        fragmentManager.beginTransaction()
            .hide(controlsFragment)
            .commit();
    }

    function shouldShowControls() {
        if (exists mediaController = this.mediaController,
            mediaController.metadata exists,
            exists state = mediaController.playbackState?.state) {
            return state != PlaybackStateCompat.stateError
                && state != PlaybackStateCompat.stateNone
                && state != PlaybackStateCompat.stateStopped;
        }
        else {
            return false;
        }
    }

    object mediaControllerCallback
            extends MediaControllerCompat.Callback() {
        shared actual void onPlaybackStateChanged(PlaybackStateCompat? state) {
            if (shouldShowControls()) {
                showPlaybackControls();
            } else {
//                LogHelper.d(tag, "mediaControllerCallback.onPlaybackStateCompatChanged: hiding controls because state is ", state.state);
                hidePlaybackControls();
            }
        }
        shared actual void onMetadataChanged(MediaMetadataCompat? metadata) {
            if (shouldShowControls()) {
                showPlaybackControls();
            } else {
//                LogHelper.d(tag, "mediaControllerCallback.onMetadataChanged: hiding controls because metadata is null");
                hidePlaybackControls();
            }
        }
    }

    shared default void onMediaControllerConnected() {}

    void connectToSession(MediaSessionCompat.Token token) {
        value controller = MediaControllerCompat(this, token);
        MediaControllerCompat.setMediaController(this, controller);
        controller.registerCallback(mediaControllerCallback);
        if (shouldShowControls()) {
            showPlaybackControls();
        } else {
//            LogHelper.d(tag, "connectionCallback.onConnected: hiding controls because metadata is null");
            hidePlaybackControls();
        }
        controlsFragment?.onConnected();
        onMediaControllerConnected();
    }

    shared actual default void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
//        LogHelper.d(tag, "Activity onCreate");
        if (Build.VERSION.sdkInt >= 21) {
            value taskDesc
                    = ActivityManager.TaskDescription(title.string,
                BitmapFactory.decodeResource(resources, R.Drawable.ic_launcher_white),
                themeColor(this, R.Attr.colorPrimary, AndroidR.Color.darker_gray));
            setTaskDescription(taskDesc);
        }
        mediaBrowser = MediaBrowserCompat(this,
            ComponentName(this, `MusicService`),
            object extends MediaBrowserCompat.ConnectionCallback() {
                shared actual void onConnected() {
//                    LogHelper.d(tag, "onConnected");
                    try {
                        connectToSession(mediaBrowser.sessionToken);
                    }
                    catch (RemoteException e) {
                        //LogHelper.e(tag, e, "could not connect media controller");
                        hidePlaybackControls();
                    }
                }
            },
            null);
    }

    shared actual void onStart() {
        super.onStart();
//        LogHelper.d(tag, "Activity onStart");
        "Mising fragment with id 'controls'. Cannot continue."
        assert (is PlaybackControlsFragment fragment
                = fragmentManager.findFragmentById(R.Id.fragment_playback_controls));
        controlsFragment = fragment;
        hidePlaybackControls();
        mediaBrowser.connect();
    }

    shared actual void onStop() {
        super.onStop();
//        LogHelper.d(tag, "Activity onStop");
        MediaControllerCompat.getMediaController(this)?.unregisterCallback(mediaControllerCallback);
        mediaBrowser.disconnect();
    }

}
