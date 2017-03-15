import android.app {
    Activity
}
import android.content {
    Context
}
import android.content.res {
    ColorStateList
}
import android.graphics.drawable {
    AnimationDrawable,
    Drawable
}
import android.support.v4.media {
    MediaBrowser=MediaBrowserCompat
}
import android.support.v4.media.session {
    PlaybackState=PlaybackStateCompat,
    MediaController=MediaControllerCompat
}
import android.view {
    LayoutInflater,
    View,
    ViewGroup
}
import android.widget {
    ImageView,
    TextView
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    MediaIDHelper
}

shared class State {
    shared new stateInvalid {}
    shared new stateNone {}
    shared new statePlayable {}
    shared new statePaused {}
    shared new statePlaying {}
}

shared class MediaItemViewHolder {

    static variable Boolean initialized = false;

    static late ColorStateList? colorStatePlaying;
    static late ColorStateList? colorStateNotPlaying;

    static void initializeColorStateLists(Context ctx) {
        if (!initialized) {
            function color(Integer code)
                    => ColorStateList.valueOf(
                        ctx.resources.getColor(
                            code, ctx.theme));
            colorStateNotPlaying = color(R.Color.media_item_icon_not_playing);
            colorStatePlaying = color(R.Color.media_item_icon_playing);
            initialized = true;
        }
    }

    shared static Drawable? getDrawableByState(Context context, State state) {
        initializeColorStateLists(context);

        switch (state)
        case (State.statePlayable) {
            value pauseDrawable
                    = context.getDrawable(R.Drawable.ic_play_arrow_black_36dp);
            pauseDrawable.setTintList(colorStateNotPlaying);
            return pauseDrawable;
        }
        case (State.statePlaying) {
            assert (is AnimationDrawable playingAnimation
                    = context.getDrawable(R.Drawable.ic_equalizer_white_36dp));
            playingAnimation.setTintList(colorStatePlaying);
            playingAnimation.start();
            return playingAnimation;
        }
        case (State.statePaused) {
            value playDrawable
                    = context.getDrawable(R.Drawable.ic_equalizer1_white_36dp);
            playDrawable.setTintList(colorStatePlaying);
            return playDrawable;
        }
        else {
            return null;
        }
    }

    suppressWarnings("caseNotDisjoint")
    shared static State getStateFromController(Context context) {
        assert (is Activity context,
                exists controller = MediaController.getMediaController(context));
        if (exists state = controller.playbackState?.state) {
            return switch (state)
            case (PlaybackState.statePlaying) State.statePlaying
            case (PlaybackState.stateError) State.stateNone
            else State.statePaused;
        }
        else {
            return State.stateNone;
        }
    }

    shared static State getMediaItemState(Context context, MediaBrowser.MediaItem mediaItem) {
        if (mediaItem.playable) {
            return MediaIDHelper.isMediaItemPlaying(context, mediaItem)
                then getStateFromController(context)
                else State.statePlayable;
        }
        else {
            return State.stateNone;
        }
    }

    shared static View setupListView(Activity activity, View? view, ViewGroup parent, MediaBrowser.MediaItem item) {
        initializeColorStateLists(activity);

        MediaItemViewHolder holder;
        State? cachedState;
        View convertView;
        if (exists givenView = view) {
            convertView = givenView;
            assert (is MediaItemViewHolder tag
                    = convertView.tag);
            holder = tag;
            assert (is State? state
                    = convertView.getTag(R.Id.tag_mediaitem_state_cache));
            cachedState = state;
        } else {
            convertView
                    = LayoutInflater.from(activity)
                    .inflate(R.Layout.media_list_item, parent, false);
            holder = MediaItemViewHolder();
            assert (is ImageView image
                    = convertView.findViewById(R.Id.play_eq));
            holder.imageView = image;
            assert (is TextView title
                    = convertView.findViewById(R.Id.title));
            holder.titleView = title;
            assert (is TextView description
                    = convertView.findViewById(R.Id.description));
            holder.descriptionView = description;
            convertView.tag = holder;
            cachedState = State.stateInvalid;
        }

        value description = item.description;
        holder.titleView.setText(description.title);
        holder.descriptionView.setText(description.subtitle);
        value state = getMediaItemState(activity, item);
        value changed
                = if (exists cachedState)
                then cachedState != state
                else true;
        if (changed) {
            if (exists drawable = getDrawableByState(activity, state)) {
                holder.imageView.setImageDrawable(drawable);
                holder.imageView.setVisibility(View.visible);
            } else {
                holder.imageView.setVisibility(View.gone);
            }
            convertView.setTag(R.Id.tag_mediaitem_state_cache, state);
        }
        return convertView;
    }

    shared new() {}

    late ImageView imageView;
    late TextView titleView;
    late TextView descriptionView;

}
