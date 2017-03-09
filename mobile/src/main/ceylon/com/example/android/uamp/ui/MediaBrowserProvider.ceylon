import android.media.browse {
    MediaBrowser
}

shared interface MediaBrowserProvider {
    shared formal MediaBrowser mediaBrowser;
}

shared interface MediaFragmentListener satisfies MediaBrowserProvider {
    shared formal void onMediaItemSelected(MediaBrowser.MediaItem item) ;
    shared formal void setToolbarTitle(String? title) ;
}
