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
import android.media {
    MediaMetadata
}
import android.media.browse {
    MediaBrowser
}
import android.media.session {
    MediaController,
    PlaybackState
}
import android.net {
    ConnectivityManager
}
import android.os {
    Bundle
}
import android.view {
    LayoutInflater,
    View,
    ViewGroup
}
import android.widget {
    AdapterView,
    ArrayAdapter,
    ListView,
    TextView,
    Toast,
    Adapter
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    LogHelper,
    MediaIDHelper,
    NetworkHelper
}

import java.util {
    ArrayList,
    List,
    Objects
}

class BrowseAdapter(Activity context)
        extends ArrayAdapter<MediaBrowser.MediaItem>
        (context, R.Layout.media_list_item, ArrayList<MediaBrowser.MediaItem>()) {
    getView(Integer position, View convertView, ViewGroup parent)
            => MediaItemViewHolder.setupListView(context, convertView, parent, getItem(position));
}

shared class MediaBrowserFragment() extends Fragment() {

    value tag = LogHelper.makeLogTag(`MediaBrowserFragment`);
    value argMediaId = "media_id";

    variable String? currentMediaId = null;
    variable MediaFragmentListener? mediaFragmentListener = null;

    late BrowseAdapter browserAdapter;
    late View errorView;
    late TextView errorMessage;

    function showError(Boolean forceError) {
        if (!NetworkHelper.isOnline(activity)) {
            errorMessage.setText(R.String.error_no_connection);
            return true;
        }
        else if (exists controller = activity.mediaController,
                controller.metadata exists,
                exists playbackState = controller.playbackState,
                playbackState.state == PlaybackState.stateError,
                playbackState.errorMessage exists) {
            errorMessage.setText(playbackState.errorMessage);
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
        Boolean showError = this.showError(forceError);
        errorView.visibility
                = showError then View.visible else View.gone;
        LogHelper.d(tag, "checkForUserVisibleErrors. forceError=", forceError, " showError=", showError, " isOnline=", NetworkHelper.isOnline(activity));
    }

    object connectivityChangeReceiver extends BroadcastReceiver() {
        variable Boolean oldOnline = false;
        shared actual void onReceive(Context context, Intent intent) {
            if (currentMediaId exists) {
                Boolean isOnline = NetworkHelper.isOnline(context);
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
            super.onMetadataChanged(metadata);
            if (exists metadata) {
                LogHelper.d(tag, "Received metadata change to media ", metadata.description.mediaId);
                browserAdapter.notifyDataSetChanged();
            }
        }
        shared actual void onPlaybackStateChanged(PlaybackState state) {
            super.onPlaybackStateChanged(state);
            LogHelper.d(tag, "Received state change: ", state);
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
        LogHelper.d(tag, "fragment.onCreateView");
        value rootView = inflater.inflate(R.Layout.fragment_list, container, false);
        errorView = rootView.findViewById(R.Id.playback_error);
        assert (is TextView error = errorView.findViewById(R.Id.error_message));
        errorMessage = error;
        browserAdapter = BrowseAdapter(activity);
        assert (is ListView listView = rootView.findViewById(R.Id.list_view));
        listView.setAdapter(browserAdapter);
        listView.setOnItemClickListener(object satisfies OnItemClickBase {
            shared actual void onItemClick(AdapterView<out Adapter>? parent, View? view, Integer position, Integer id) {
                checkForUserVisibleErrors(false);
                value item = browserAdapter.getItem(position);
                mediaFragmentListener?.onMediaItemSelected(item);
            }
        });
        return rootView;
    }

    shared actual void onStart() {
        super.onStart();
        if (exists mediaBrowser = mediaFragmentListener?.mediaBrowser) {
            LogHelper.d(tag, "fragment.onStart, mediaId=", currentMediaId, "  onConnected=", mediaBrowser.connected);
            if (mediaBrowser.connected) {
                onConnected();
            }
        }
        this.activity.registerReceiver(connectivityChangeReceiver,
            IntentFilter(ConnectivityManager.connectivityAction));
    }

    shared actual void onStop() {
        super.onStop();
        if (exists mediaBrowser = mediaFragmentListener?.mediaBrowser,
            mediaBrowser.connected, exists id=currentMediaId) {
            mediaBrowser.unsubscribe(id);
        }
        if (exists controller = activity?.mediaController) {
            controller.unregisterCallback(mediaControllerCallback);
        }
        this.activity.unregisterReceiver(connectivityChangeReceiver);
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

        this.currentMediaId = mediaId else mediaFragmentListener?.mediaBrowser?.root;

        updateTitle();
        mediaFragmentListener?.mediaBrowser?.unsubscribe(currentMediaId);
        mediaFragmentListener?.mediaBrowser?.subscribe(currentMediaId,
            object extends MediaBrowser.SubscriptionCallback() {
                shared actual void onChildrenLoaded(String parentId, List<MediaBrowser.MediaItem> children) {
                    try {
                        LogHelper.d(tag, "fragment onChildrenLoaded, parentId=", parentId, "  count=", children.size());
                        checkForUserVisibleErrors(children.empty);
                        browserAdapter.clear();
                        for (item in children) {
                            browserAdapter.add(item);
                        }
                        browserAdapter.notifyDataSetChanged();
                    }
                    catch (Throwable t) {
                        LogHelper.e(tag, "Error on childrenloaded", t);
                    }
                }
                shared actual void onError(String id) {
                    LogHelper.e(tag, "browse fragment subscription onError, id=" + id);
                    Toast.makeText(activity, R.String.error_loading_media, Toast.lengthLong).show();
                    checkForUserVisibleErrors(true);
                }
            });

        if (exists controller = activity.mediaController) {
            controller.registerCallback(mediaControllerCallback);
        }
    }

    void updateTitle() {
        if (Objects.equals(MediaIDHelper.mediaIdRoot,currentMediaId)) {
            mediaFragmentListener?.setToolbarTitle(null);
        }
        else {
            mediaFragmentListener?.mediaBrowser
                ?.getItem(currentMediaId, object extends MediaBrowser.ItemCallback() {
                onItemLoaded(MediaBrowser.MediaItem item)
                        => mediaFragmentListener?.setToolbarTitle(item.description.title.string);
            });
        }
    }

}

shared interface MediaFragmentListener satisfies MediaBrowserProvider {
    shared formal void onMediaItemSelected(MediaBrowser.MediaItem item) ;
    shared formal void setToolbarTitle(String? title) ;
}
