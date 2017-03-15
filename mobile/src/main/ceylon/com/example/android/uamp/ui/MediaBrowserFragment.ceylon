import android.app {
    Activity,
    Fragment
}
import android.content {
    BroadcastReceiver,
    Context,
    Intent,
    IntentFilter
}
import android.net {
    ConnectivityManager
}
import android.os {
    Bundle
}
import android.support.v4.media {
    MediaMetadata=MediaMetadataCompat,
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
    ArrayAdapter,
    ListView,
    TextView,
    Toast
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    MediaIDHelper,
    networkOnline
}

import java.util {
    ArrayList,
    List
}

shared class MediaBrowserFragment() extends Fragment() {

//    value tag = LogHelper.makeLogTag(`MediaBrowserFragment`);
    value argMediaId = "media_id";

    variable String? currentMediaId = null;
    variable MediaFragmentListener? mediaFragmentListener = null;

    late variable ArrayAdapter<MediaBrowser.MediaItem> browserAdapter;
    late variable View errorView;
    late variable TextView errorMessage;

    MediaBrowser? mediaBrowser => mediaFragmentListener?.mediaBrowser;
    MediaController? mediaController => MediaController.getMediaController(activity);

    function showError(Boolean forceError) {
        if (!networkOnline(activity)) {
            errorMessage.setText(R.String.error_no_connection);
            return true;
        }
        else if (exists controller = mediaController,
                controller.metadata exists,
                exists playbackState = controller.playbackState,
                playbackState.state == PlaybackState.stateError,
                playbackState.errorMessage exists) {
            errorMessage.text = playbackState.errorMessage;
            return true;
        }
        else if (forceError) {
            errorMessage.setText(R.String.error_loading_media);
            return true;
        }
        else {
            return false;
        }
    }

    void checkForUserVisibleErrors(Boolean forceError) {
        errorView.visibility
                = showError(forceError)
                then View.visible
                else View.gone;
//        LogHelper.d(tag, "checkForUserVisibleErrors. forceError=", forceError, " showError=", showError, " isOnline=", NetworkHelper.isOnline(activity));
    }

    object connectivityChangeReceiver extends BroadcastReceiver() {
        variable value oldOnline = false;
        shared actual void onReceive(Context context, Intent intent) {
            if (currentMediaId exists) {
                value isOnline = networkOnline(context);
                if (isOnline != oldOnline) {
                    oldOnline = isOnline;
                    checkForUserVisibleErrors(false);
                    if (isOnline) {
                        browserAdapter.notifyDataSetChanged();
                    }
                }
            }
        }
    }

    object mediaControllerCallback extends MediaController.Callback() {
        shared actual void onMetadataChanged(MediaMetadata? metadata) {
            if (exists metadata) {
//                LogHelper.d(tag, "Received metadata change to media ", metadata.description.mediaId);
                browserAdapter.notifyDataSetChanged();
            }
        }
        shared actual void onPlaybackStateChanged(PlaybackState? state) {
//            LogHelper.d(tag, "Received state change: ", state);
            checkForUserVisibleErrors(false);
            browserAdapter.notifyDataSetChanged();
        }
    }

    suppressWarnings("deprecation")
    shared actual void onAttach(Activity activity) {
        super.onAttach(activity);
        assert (is MediaFragmentListener? activity);
        mediaFragmentListener = activity;
    }

    shared actual View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
//        LogHelper.d(tag, "fragment.onCreateView");
        browserAdapter = object extends ArrayAdapter<MediaBrowser.MediaItem>
                (activity, R.Layout.media_list_item, ArrayList<MediaBrowser.MediaItem>()) {
            getView(Integer position, View convertView, ViewGroup parent)
                    => MediaItemViewHolder.setupListView(activity, convertView, parent, getItem(position));
        };

        value rootView = inflater.inflate(R.Layout.fragment_list, container, false);

        errorView = rootView.findViewById(R.Id.playback_error);

        assert (is TextView error = errorView.findViewById(R.Id.error_message));
        errorMessage = error;

        assert (is ListView listView = rootView.findViewById(R.Id.list_view));
        listView.setAdapter(browserAdapter);
        listView.setOnItemClickListener((parent, view, position, id) {
            checkForUserVisibleErrors(false);
            value item = browserAdapter.getItem(position);
            mediaFragmentListener?.onMediaItemSelected(item);
        });

        return rootView;
    }

    shared actual void onStart() {
        super.onStart();
        if (exists mediaBrowser = this.mediaBrowser) {
//            LogHelper.d(tag, "fragment.onStart, mediaId=", currentMediaId, "  onConnected=", mediaBrowser.connected);
            if (mediaBrowser.connected) {
                onConnected();
            }
        }
        activity?.registerReceiver(connectivityChangeReceiver,
            IntentFilter(ConnectivityManager.connectivityAction));
    }

    shared actual void onStop() {
        super.onStop();
        if (exists mediaBrowser = this.mediaBrowser,
            mediaBrowser.connected,
            exists id = currentMediaId) {
            mediaBrowser.unsubscribe(id);
        }
        mediaController?.unregisterCallback(mediaControllerCallback);
        activity?.unregisterReceiver(connectivityChangeReceiver);
    }

    shared actual void onDetach() {
        super.onDetach();
        mediaFragmentListener = null;
    }

    shared String? mediaId => arguments?.getString(argMediaId);

    assign mediaId {
        value args = Bundle(1);
        args.putString(argMediaId, mediaId);
        arguments = args;
    }

    shared void onConnected() {
        if (detached) {
            return;
        }

        currentMediaId = mediaId else mediaBrowser?.root;

        updateTitle();

        assert (exists id = currentMediaId);
        mediaBrowser?.unsubscribe(id);
        mediaBrowser?.subscribe(id,
            object extends MediaBrowser.SubscriptionCallback() {
                shared actual void onChildrenLoaded(String parentId, List<MediaBrowser.MediaItem> children) {
                    try {
//                        LogHelper.d(tag, "fragment onChildrenLoaded, parentId=", parentId, "  count=", children.size());
                        checkForUserVisibleErrors(children.empty);
                        browserAdapter.clear();
                        for (item in children) {
                            browserAdapter.add(item);
                        }
                        browserAdapter.notifyDataSetChanged();
                    }
                    catch (Throwable t) {
//                        LogHelper.e(tag, "Error on childrenloaded", t);
                    }
                }
                shared actual void onError(String id) {
//                    LogHelper.e(tag, "browse fragment subscription onError, id=" + id);
                    Toast.makeText(activity, R.String.error_loading_media, Toast.lengthLong).show();
                    checkForUserVisibleErrors(true);
                }
            });

        mediaController?.registerCallback(mediaControllerCallback);
    }

    void updateTitle() {
        if (MediaIDHelper.equalIds(MediaIDHelper.mediaIdRoot, currentMediaId)) {
            mediaFragmentListener?.setToolbarTitle(null);
        }
        else if (exists id = currentMediaId) {
            mediaBrowser?.getItem(id, object extends MediaBrowser.ItemCallback() {
                onItemLoaded(MediaBrowser.MediaItem item)
                        => mediaFragmentListener?.setToolbarTitle(item.description.title?.string);
            });
        }
        else {
            mediaFragmentListener?.setToolbarTitle(null);
        }
    }

}
