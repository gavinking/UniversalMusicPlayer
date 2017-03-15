import android.support.v4.media {
    MediaBrowserCompat
}

shared interface MediaBrowserProvider {
    shared formal MediaBrowserCompat mediaBrowser;
}

shared interface MediaFragmentListener satisfies MediaBrowserProvider {
    shared formal void onMediaItemSelected(MediaBrowserCompat.MediaItem item);
    shared formal void setToolbarTitle(String? title);
}
