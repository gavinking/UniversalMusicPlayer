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
import android.media.browse {
    MediaBrowser
}
import android.media.session {
    PlaybackState
}
import android.support.v4.app {
    FragmentActivity
}
import android.support.v4.content {
    ContextCompat
}
import android.support.v4.graphics.drawable {
    DrawableCompat
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

    static late ColorStateList? sColorStatePlaying;
    static late ColorStateList? sColorStateNotPlaying;

    static void initializeColorStateLists(Context ctx) {
        if (!initialized) {
            sColorStateNotPlaying = ColorStateList.valueOf(ctx.resources.getColor(R.Color.media_item_icon_not_playing));
            sColorStatePlaying = ColorStateList.valueOf(ctx.resources.getColor(R.Color.media_item_icon_playing));
            initialized = true;
        }
    }

    shared static Drawable? getDrawableByState(Context context, State state) {
        initializeColorStateLists(context);

        switch (state)
        case (State.statePlayable) {
            value pauseDrawable = ContextCompat.getDrawable(context, R.Drawable.ic_play_arrow_black_36dp);
            DrawableCompat.setTintList(pauseDrawable, sColorStateNotPlaying);
            return pauseDrawable;
        }
        case (State.statePlaying) {
            assert (is AnimationDrawable animation
                    = ContextCompat.getDrawable(context, R.Drawable.ic_equalizer_white_36dp));
            DrawableCompat.setTintList(animation, sColorStatePlaying);
            animation.start();
            return animation;
        }
        case (State.statePaused) {
            value playDrawable = ContextCompat.getDrawable(context, R.Drawable.ic_equalizer1_white_36dp);
            DrawableCompat.setTintList(playDrawable, sColorStatePlaying);
            return playDrawable;
        }
        else {
            return null;
        }
    }

    suppressWarnings("caseNotDisjoint")
    shared static State getStateFromController(Context context) {
        assert (is FragmentActivity context);
        value pbState = context.mediaController.playbackState;
        return switch (pbState?.state)
            case (null | PlaybackState.stateError) State.stateNone
            case (PlaybackState.statePlaying) State.statePlaying
            else State.statePaused;
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
            assert (is MediaItemViewHolder tag = convertView.tag);
            holder = tag;
            assert (is State? state = convertView.getTag(R.Id.tag_mediaitem_state_cache));
            cachedState = state;
        } else {
            convertView = LayoutInflater.from(activity).inflate(R.Layout.media_list_item, parent, false);
            holder = MediaItemViewHolder();
            assert (is ImageView image = convertView.findViewById(R.Id.play_eq));
            holder.mImageView = image;
            assert (is TextView title = convertView.findViewById(R.Id.title));
            holder.mTitleView = title;
            assert (is TextView description = convertView.findViewById(R.Id.description));
            holder.mDescriptionView = description;
            convertView.tag = holder;
            cachedState = State.stateInvalid;
        }

        value description = item.description;
        holder.mTitleView.setText(description.title);
        holder.mDescriptionView.setText(description.subtitle);
        value state = getMediaItemState(activity, item);
        value changed
                = if (exists cachedState)
                then cachedState != state
                else true;
        if (changed) {
            if (exists drawable = getDrawableByState(activity, state)) {
                holder.mImageView.setImageDrawable(drawable);
                holder.mImageView.setVisibility(View.visible);
            } else {
                holder.mImageView.setVisibility(View.gone);
            }
            convertView.setTag(R.Id.tag_mediaitem_state_cache, state);
        }
        return convertView;
    }

    shared new() {}

    late ImageView mImageView;
    late TextView mTitleView;
    late TextView mDescriptionView;

}
