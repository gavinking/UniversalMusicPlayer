import android.app {
    Fragment
}
import android.content {
    Intent
}
import android.os {
    Bundle
}
import android.support.v4.media {
    MediaMetadataCompat
}
import android.support.v4.media.session {
    PlaybackStateCompat,
    MediaControllerCompat
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
    MediaIDHelper
}

shared class PlaybackControlsFragment() extends Fragment() {

//    value tag = LogHelper.makeLogTag(`PlaybackControlsFragment`);

    late ImageButton mPlayPause;
    late TextView title;
    late TextView subtitle;
    late TextView extraInfo;
    late ImageView albumArt;

    variable String? mArtUrl = null;

    MediaControllerCompat? mediaController => MediaControllerCompat.getMediaController(activity);

    suppressWarnings("caseNotDisjoint")
    shared actual View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        value rootView = inflater.inflate(R.Layout.fragment_playback_controls, container, false);

        assert (is ImageButton playPause = rootView.findViewById(R.Id.play_pause));
        mPlayPause = playPause;
        mPlayPause.enabled = true;
        mPlayPause.setOnClickListener((v) {
            value state =
                    mediaController?.playbackState?.state
                    else PlaybackStateCompat.stateNone;
//            LogHelper.d(tag, "Button pressed, in state " + state);

//            if (v.id == R.Id.play_pause) {
//                LogHelper.d(tag, "Play button pressed, in state " + state);
            value controls = mediaController?.transportControls;
            switch (state)
            case (PlaybackStateCompat.statePaused
                | PlaybackStateCompat.stateStopped
                | PlaybackStateCompat.stateNone) {
                controls?.play();
            }
            case (PlaybackStateCompat.statePlaying
                | PlaybackStateCompat.stateBuffering
                | PlaybackStateCompat.stateConnecting) {
                controls?.pause();
            }
            else {}
//            }

        });

        assert (is TextView title = rootView.findViewById(R.Id.title));
        this.title = title;
        assert (is TextView subtitle = rootView.findViewById(R.Id.artist));
        this.subtitle = subtitle;
        assert (is TextView extraInfo = rootView.findViewById(R.Id.extra_info));
        this.extraInfo = extraInfo;
        assert (is ImageView albumArt = rootView.findViewById(R.Id.album_art));
        this.albumArt = albumArt;

        rootView.setOnClickListener((v) {
            value intent = Intent(activity, `FullScreenPlayerActivity`);
            intent.setFlags(Intent.flagActivitySingleTop);
            if (exists metadata = mediaController?.metadata) {
                intent.putExtra(MusicPlayerActivity.extraCurrentMediaDescription, metadata.description);
            }
            startActivity(intent);
        });
        return rootView;
    }

    void onMetadataChanged(MediaMetadataCompat? metadata) {
//        LogHelper.d(tag, "onMetadataChanged ", metadata);
        if (!activity exists) {
//            LogHelper.w(tag, "onMetadataChanged called when getActivity null," + "this should not happen if the callback was properly unregistered. Ignoring.");
            return;
        }
        if (!exists metadata) {
            return;
        }

        title.setText(metadata.description.title);
        subtitle.setText(metadata.description.subtitle);
        value artUrl = metadata.description.iconUri?.string;
        if (!MediaIDHelper.equalIds(artUrl, mArtUrl)) {
            mArtUrl = artUrl;
            if (exists art
                    = metadata.description.iconBitmap
                    else AlbumArtCache.instance.getIconImage(mArtUrl)) {
                albumArt.setImageBitmap(art);
            }
            else {
                AlbumArtCache.instance.fetch(artUrl, (artUrl, bitmap, icon) {
                    if (exists icon) {
//                        LogHelper.d(tag, "album art icon of w=", icon.width, " h=", icon.height);
                        if (added) {
                            albumArt.setImageBitmap(icon);
                        }
                    }
                });
            }
        }
    }

    shared void setExtraInfo(String? info) {
        if (exists info) {
            extraInfo.setText(info);
            extraInfo.visibility = View.visible;
        }
        else {
            extraInfo.visibility = View.gone;
        }
    }

    suppressWarnings("caseNotDisjoint")
    void onPlaybackStateChanged(PlaybackStateCompat? state) {
//        LogHelper.d(tag, "onPlaybackStateCompatChanged ", state);
        if (!activity exists) {
//            LogHelper.w(tag, "onPlaybackStateCompatChanged called when getActivity null," + "this should not happen if the callback was properly unregistered. Ignoring.");
            return ;
        }
        if (!exists state) {
            return;
        }

        Boolean enablePlay;
        switch (state.state)
        case (PlaybackStateCompat.statePaused
            | PlaybackStateCompat.stateStopped) {
            enablePlay = true;
        }
        case (PlaybackStateCompat.stateError) {
//            LogHelper.e(tag, "error PlaybackStateCompat: ", state.errorMessage);
            Toast.makeText(activity, state.errorMessage, Toast.lengthLong).show();
            enablePlay = false;
        }
        else {
            enablePlay = false;
        }

        mPlayPause.setImageDrawable(
            activity.getDrawable(enablePlay
                then R.Drawable.ic_play_arrow_black_36dp
                else R.Drawable.ic_pause_black_36dp));

        value extraInfo
                = if (exists castName
                            = mediaController?.extras
                            ?.getString(MusicService.extraConnectedCast))
                then resources.getString(R.String.casting_to_device, castName)
                else null;
        setExtraInfo(extraInfo);
    }

    object callback extends MediaControllerCompat.Callback() {
        shared actual void onPlaybackStateChanged(PlaybackStateCompat state) {
//            LogHelper.d(tag, "Received playback state change to state ", state.state);
            outer.onPlaybackStateChanged(state);
        }
        shared actual void onMetadataChanged(MediaMetadataCompat? metadata) {
            if (exists metadata) {
//                LogHelper.d(tag, "Received metadata state change to mediaId=", metadata.description.mediaId, " song=", metadata.description.title);
                outer.onMetadataChanged(metadata);
            }
        }
    }

    shared actual void onStart() {
        super.onStart();
//        LogHelper.d(tag, "fragment.onStart");
        onConnected();
    }

    shared actual void onStop() {
        super.onStop();
//        LogHelper.d(tag, "fragment.onStop");
        mediaController?.unregisterCallback(callback);
    }

    shared void onConnected() {
//        LogHelper.d(tag, "onConnected, mediaController==null? ", !controller exists);
        if (exists controller = mediaController) {
            onMetadataChanged(controller.metadata);
            onPlaybackStateChanged(controller.playbackState);
            controller.registerCallback(callback);
        }
    }

}
