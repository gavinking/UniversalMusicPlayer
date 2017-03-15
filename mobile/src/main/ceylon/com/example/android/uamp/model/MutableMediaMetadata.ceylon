import android.support.v4.media {
    MediaMetadata=MediaMetadataCompat
}

import com.example.android.uamp.utils {
    MediaIDHelper
}

shared class MutableMediaMetadata(trackId, metadata) {

    shared String trackId;
    shared variable MediaMetadata metadata;

    equals(Object that)
            => if (is MutableMediaMetadata that)
            then this===that
              || MediaIDHelper.equalIds(trackId, that.trackId)
            else false;

    hash => trackId.hash;

}