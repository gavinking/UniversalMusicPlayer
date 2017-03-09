import android.app {
    Fragment
}
import android.content {
    Intent
}
import android.graphics {
    Bitmap
}
import android.media {
    MediaMetadata
}
import android.media.session {
    MediaController,
    PlaybackState
}
import android.os {
    Bundle
}
import android.support.v4.content {
    ContextCompat
}
import android.view {
    LayoutInflater,
    View,
    ViewGroup
}
import android.widget {
    ImageButton,
    ImageView,
    TextView,
    Toast
}

import com.example.android.uamp {
    AlbumArtCache,
    MusicService,
    R
}
import com.example.android.uamp.utils {
    LogHelper
}

import java.util {
    Objects
}

shared class PlaybackControlsFragment() extends Fragment() {

    value tag = LogHelper.makeLogTag(`PlaybackControlsFragment`);

    late ImageButton mPlayPause;
    late TextView mTitle;
    late TextView mSubtitle;
    late TextView mExtraInfo;
    late ImageView mAlbumArt;

    variable String? mArtUrl = null;

    object mCallback extends MediaController.Callback() {
        shared actual void onPlaybackStateChanged(PlaybackState state) {
            LogHelper.d(tag, "Received playback state change to state ", state.state);
            super.onPlaybackStateChanged(state);
        }
        shared actual void onMetadataChanged(MediaMetadata? metadata) {
            if (exists metadata) {
                LogHelper.d(tag, "Received metadata state change to mediaId=", metadata.description.mediaId, " song=", metadata.description.title);
                super.onMetadataChanged(metadata);
            }
        }
    }

    shared actual View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        value rootView = inflater.inflate(R.Layout.fragment_playback_controls, container, false);

        assert (is ImageButton playPause = rootView.findViewById(R.Id.play_pause));
        mPlayPause = playPause;
        mPlayPause.enabled = true;
        mPlayPause.setOnClickListener((v) {
            value state =
                    if (exists stateObj = activity.mediaController.playbackState)
                    then stateObj.state
                    else PlaybackState.stateNone;
//            LogHelper.d(tag, "Button pressed, in state " + state);

            if (v.id == R.Id.play_pause) {
//                LogHelper.d(tag, "Play button pressed, in state " + state);
                if (state == PlaybackState.statePaused
                || state == PlaybackState.stateStopped
                || state == PlaybackState.stateNone) {
                    playMedia();
                }
                else if (state == PlaybackState.statePlaying
                || state == PlaybackState.stateBuffering
                || state == PlaybackState.stateConnecting) {
                    pauseMedia();
                }
            }

        });

        assert (is TextView title = rootView.findViewById(R.Id.title));
        mTitle = title;
        assert (is TextView subtitle = rootView.findViewById(R.Id.artist));
        mSubtitle = subtitle;
        assert (is TextView extraInfo = rootView.findViewById(R.Id.extra_info));
        mExtraInfo = extraInfo;
        assert (is ImageView albumArt = rootView.findViewById(R.Id.album_art));
        mAlbumArt = albumArt;

        rootView.setOnClickListener((v) {
            value intent = Intent(activity, `FullScreenPlayerActivity`);
            intent.setFlags(Intent.flagActivitySingleTop);
            value controller = activity.mediaController;
            if (exists metadata = controller.metadata) {
                intent.putExtra(MusicPlayerActivity.extraCurrentMediaDescription, metadata.description);
            }
            startActivity(intent);
        });
        return rootView;
    }

    shared actual void onStart() {
        super.onStart();
        LogHelper.d(tag, "fragment.onStart");
        if (exists controller = activity.mediaController) {
            onConnected();
        }
    }

    shared actual void onStop() {
        super.onStop();
        LogHelper.d(tag, "fragment.onStop");
        if (exists controller = activity.mediaController) {
            controller.unregisterCallback(mCallback);
        }
    }

    shared void onConnected() {
//        LogHelper.d(tag, "onConnected, mediaController==null? ", !controller exists);
        if (exists controller = activity.mediaController) {
            onMetadataChanged(controller.metadata);
            onPlaybackStateChanged(controller.playbackState);
            controller.registerCallback(mCallback);
        }
    }

    void onMetadataChanged(MediaMetadata? metadata) {
        LogHelper.d(tag, "onMetadataChanged ", metadata);
        if (!activity exists) {
            LogHelper.w(tag, "onMetadataChanged called when getActivity null," + "this should not happen if the callback was properly unregistered. Ignoring.");
            return;
        }
        if (!exists metadata) {
            return;
        }
        mTitle.setText(metadata.description.title);
        mSubtitle.setText(metadata.description.subtitle);
        value artUrl = metadata.description.iconUri?.string;
        if (!Objects.equals(artUrl, mArtUrl)) {
            mArtUrl = artUrl;
            value cache = AlbumArtCache.instance;
            if (exists art = metadata.description.iconBitmap else cache.getIconImage(mArtUrl)) {
                mAlbumArt.setImageBitmap(art);
            }
            else {
                cache.fetch(artUrl, object extends AlbumArtCache.FetchListener() {
                    shared actual void onFetched(String? artUrl, Bitmap? bitmap, Bitmap? icon) {
                        if (exists icon) {
                            LogHelper.d(tag, "album art icon of w=", icon.width, " h=", icon.height);
                            if (added) {
                                mAlbumArt.setImageBitmap(icon);
                            }
                        }
                    }
                });
            }
        }
    }

    shared void setExtraInfo(String? extraInfo) {
        if (exists extraInfo) {
            mExtraInfo.setText(extraInfo);
            mExtraInfo.visibility = View.visible;
        }
        else {
            mExtraInfo.visibility = View.gone;
        }
    }

    void onPlaybackStateChanged(PlaybackState? state) {
        LogHelper.d(tag, "onPlaybackStateChanged ", state);
        if (!activity exists) {
            LogHelper.w(tag, "onPlaybackStateChanged called when getActivity null," + "this should not happen if the callback was properly unregistered. Ignoring.");
            return ;
        }
        if (!exists state) {
            return;
        }

        Boolean enablePlay;
        if (state.state == PlaybackState.statePaused) {
            enablePlay = true;
        }
        else if (state.state == PlaybackState.stateError) {
            LogHelper.e(tag, "error playbackstate: ", state.errorMessage);
            Toast.makeText(activity, state.errorMessage, Toast.lengthLong).show();
            enablePlay = false;
        }
        else {
            enablePlay = false;
        }

        mPlayPause.setImageDrawable(ContextCompat.getDrawable(activity,
            enablePlay then R.Drawable.ic_play_arrow_black_36dp else R.Drawable.ic_pause_black_36dp));

        value extraInfo
                = if (exists castName
                            = activity?.mediaController?.extras
                            ?.getString(MusicService.extraConnectedCast))
                then resources.getString(R.String.casting_to_device, castName)
                else null;
        setExtraInfo(extraInfo);
    }

    void playMedia() {
        if (exists controller = activity.mediaController) {
            controller.transportControls.play();
        }
    }

    void pauseMedia() {
        if (exists controller = activity.mediaController) {
            controller.transportControls.pause();
        }
    }

}
