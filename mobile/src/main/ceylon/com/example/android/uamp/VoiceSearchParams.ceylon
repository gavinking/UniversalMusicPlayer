import android.os {
    Build,
    Bundle
}
import android.provider {
    MediaStore
}
import android.text {
    TextUtils
}

import com.example.android.uamp.utils {
    MediaIDHelper {
        equalIds
    }
}

shared class VoiceSearchParams(query, Bundle? extras) {

    shared String query;

    shared variable Boolean isAny = false;
    shared variable Boolean isUnstructured = false;
    shared variable Boolean isGenreFocus = false;
    shared variable Boolean isArtistFocus = false;
    shared variable Boolean isAlbumFocus = false;
    shared variable Boolean isSongFocus = false;
    shared variable String genre = "";
    shared variable String artist = "";
    shared variable String album = "";
    shared variable String song = "";

    if (TextUtils.isEmpty(query)) {
        isAny = true;
    } else {
        if (!exists extras) {
            isUnstructured = true;
        } else {
            variable String genreKey;
            if (Build.VERSION.sdkInt>=21) {
                genreKey = MediaStore.extraMediaGenre;
            } else {
                genreKey = "android.intent.extra.genre";
            }
            String mediaFocus = extras.getString(MediaStore.extraMediaFocus);
            if (equalIds(mediaFocus, MediaStore.Audio.Genres.entryContentType)) {
                isGenreFocus = true;
                genre = extras.getString(genreKey);
                if (TextUtils.isEmpty(genre)) {
                    genre = query;
                }
            } else if (equalIds(mediaFocus, MediaStore.Audio.Artists.entryContentType)) {
                isArtistFocus = true;
                genre = extras.getString(genreKey);
                artist = extras.getString(MediaStore.extraMediaArtist);
            } else if (equalIds(mediaFocus, MediaStore.Audio.Albums.entryContentType)) {
                isAlbumFocus = true;
                album = extras.getString(MediaStore.extraMediaAlbum);
                genre = extras.getString(genreKey);
                artist = extras.getString(MediaStore.extraMediaArtist);
            } else if (equalIds(mediaFocus, MediaStore.Audio.Media.entryContentType)) {
                isSongFocus = true;
                song = extras.getString(MediaStore.extraMediaTitle);
                album = extras.getString(MediaStore.extraMediaAlbum);
                genre = extras.getString(genreKey);
                artist = extras.getString(MediaStore.extraMediaArtist);
            } else {
                isUnstructured = true;
            }
        }
    }

    string => "query=``query````" isAny="````isAny`` isUnstructured=``isUnstructured`` isGenreFocus=``isGenreFocus`` isArtistFocus=``isArtistFocus`` isAlbumFocus=``isAlbumFocus`` isSongFocus=``isSongFocus`` genre=``genre`` artist=``artist`` album=``album`` song=``song``";

}
