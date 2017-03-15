import android.support.v4.media.session {
    MediaSessionCompat
}

shared interface Callback {
    shared formal void onCompletion() ;
    shared formal void onPlaybackStatusChanged(Integer state) ;
    shared formal void onError(String error) ;
    shared formal void setCurrentMediaId(String mediaId) ;
}

shared interface Playback {
    shared formal void start();
    shared formal void stop(Boolean notifyListeners);
    shared formal variable Integer state;
    shared formal Boolean connected;
    shared formal Boolean playing;
    shared formal variable Integer currentStreamPosition;
    shared formal void updateLastKnownStreamPosition();
    shared formal void play(MediaSessionCompat.QueueItem item);
    shared formal void pause();
    shared formal void seekTo(Integer position);

    shared formal variable String? currentMediaId;

    shared formal variable Callback? callback;
}
