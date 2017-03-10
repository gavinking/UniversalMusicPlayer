import android.media {
    MediaMetadata
}
import android.text {
    TextUtils
}

shared class MutableMediaMetadata {

    shared variable MediaMetadata metadata;

    shared String trackId;

    shared new (String trackId, MediaMetadata metadata) {
        this.metadata = metadata;
        this.trackId = trackId;
    }

    equals(Object that)
            => if (is MutableMediaMetadata that)
    then this===that
    || TextUtils.equals(trackId, that.trackId)
    else false;

    hash => trackId.hash;

}