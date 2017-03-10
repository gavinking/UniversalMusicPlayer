import android.media {
    MediaMetadata
}
import android.text {
    TextUtils
}

shared class MutableMediaMetadata(trackId, metadata) {

    shared String trackId;
    shared variable MediaMetadata metadata;

    equals(Object that)
            => if (is MutableMediaMetadata that)
            then this===that
              || TextUtils.equals(trackId, that.trackId)
            else false;

    hash => trackId.hash;

}