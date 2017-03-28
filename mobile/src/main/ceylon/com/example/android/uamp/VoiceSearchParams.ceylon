import android.os {
    Build,
    Bundle
}
import android.provider {
    MediaStore
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

    if (query.empty) {
        isAny = true;
    } else {
        if (!exists extras) {
            isUnstructured = true;
        } else {
            value genreKey
                    = Build.VERSION.sdkInt>=21
                    then MediaStore.extraMediaGenre
                    else "android.intent.extra.genre";
            switch (mediaFocus = extras.getString(MediaStore.extraMediaFocus))
            case (null) {
                isUnstructured = true;
            }
            else case (MediaStore.Audio.Genres.entryContentType) {
                isGenreFocus = true;
                genre = extras.getString(genreKey) else "";
                if (genre.empty) {
                    genre = query;
                }
            }
            else case (MediaStore.Audio.Artists.entryContentType) {
                isArtistFocus = true;
                genre = extras.getString(genreKey) else "";
                artist = extras.getString(MediaStore.extraMediaArtist);
            }
            else case (MediaStore.Audio.Albums.entryContentType) {
                isAlbumFocus = true;
                album = extras.getString(MediaStore.extraMediaAlbum);
                genre = extras.getString(genreKey) else "";
                artist = extras.getString(MediaStore.extraMediaArtist);
            }
            else case (MediaStore.Audio.Media.entryContentType) {
                isSongFocus = true;
                song = extras.getString(MediaStore.extraMediaTitle);
                album = extras.getString(MediaStore.extraMediaAlbum);
                genre = extras.getString(genreKey) else "";
                artist = extras.getString(MediaStore.extraMediaArtist);
            } else {
                isUnstructured = true;
            }
        }
    }

    string => "query=``query````" isAny="````isAny`` isUnstructured=``isUnstructured`` isGenreFocus=``isGenreFocus`` isArtistFocus=``isArtistFocus`` isAlbumFocus=``isAlbumFocus`` isSongFocus=``isSongFocus`` genre=``genre`` artist=``artist`` album=``album`` song=``song``";

}
