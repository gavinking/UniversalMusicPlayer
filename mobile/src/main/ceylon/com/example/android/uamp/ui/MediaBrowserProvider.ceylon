import android.support.v4.media {
    MediaBrowser=MediaBrowserCompat
}

shared interface MediaBrowserProvider {
    shared formal MediaBrowser mediaBrowser;
}

shared interface MediaFragmentListener satisfies MediaBrowserProvider {
    shared formal void onMediaItemSelected(MediaBrowser.MediaItem item);
    shared formal void setToolbarTitle(String? title);
}
