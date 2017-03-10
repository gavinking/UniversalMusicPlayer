import android.media {
    MediaMetadata
}

import java.io {
    BufferedReader,
    InputStreamReader
}
import java.net {
    URL
}
import java.util {
    ArrayList,
    Iterator
}

import org.json {
    JSONObject,
    JSONException
}

shared class RemoteJSONSource satisfies MusicProviderSource {

//    static value tag = LogHelper.makeLogTag(`RemoteJSONSource`);

    static value catalogUrl = "http://storage.googleapis.com/automotive-media/music.json";
    static value jsonMusic = "music";
    static value jsonTitle = "title";
    static value jsonAlbum = "album";
    static value jsonArtist = "artist";
    static value jsonGenre = "genre";
    static value jsonSource = "source";
    static value jsonImage = "image";
    static value jsonTrackNumber = "trackNumber";
    static value jsonTotalTrackCount = "totalTrackCount";
    static value jsonDuration = "duration";

    shared new () {}

    function buildFromJSON(JSONObject json, String basePath) {

        value title = json.getString(jsonTitle);
        value album = json.getString(jsonAlbum);
        value artist = json.getString(jsonArtist);
        value genre = json.getString(jsonGenre);
        variable value source = json.getString(jsonSource);
        variable value iconUrl = json.getString(jsonImage);
        value trackNumber = json.getInt(jsonTrackNumber);
        value totalTrackCount = json.getInt(jsonTotalTrackCount);
        value duration = json.getInt(jsonDuration) * 1000;
//        LogHelper.d(tag, "Found music track: ", json);
        if (!source.startsWith("http")) {
            source = basePath + source;
        }
        if (!iconUrl.startsWith("http")) {
            iconUrl = basePath + iconUrl;
        }

        return MediaMetadata.Builder()
            .putString(MediaMetadata.metadataKeyMediaId, source.hash.string)
            .putString(customMetadataTrackSource, source)
            .putString(MediaMetadata.metadataKeyAlbum, album)
            .putString(MediaMetadata.metadataKeyArtist, artist)
            .putLong(MediaMetadata.metadataKeyDuration, duration)
            .putString(MediaMetadata.metadataKeyGenre, genre)
            .putString(MediaMetadata.metadataKeyAlbumArtUri, iconUrl)
            .putString(MediaMetadata.metadataKeyTitle, title)
            .putLong(MediaMetadata.metadataKeyTrackNumber, trackNumber)
            .putLong(MediaMetadata.metadataKeyNumTracks, totalTrackCount)
            .build();
    }

    function fetchJSONFromUrl(String urlString) {
        try {
            value urlConnection = URL(urlString).openConnection();
            try (reader = BufferedReader(InputStreamReader(urlConnection.inputStream, "iso-8859-1"))) {
                value sb = StringBuilder();
                while (exists line = reader.readLine()) {
                    sb.append(line);
                }
                return JSONObject(sb.string);
            }
        }
        catch (JSONException e) {
            throw e;
        }
        catch (e) {
//            LogHelper.e(tag, "Failed to parse the json for media list", e);
            return null;
        }
    }

    shared actual Iterator<MediaMetadata> iterator() {
//        try {
        value slashPos = catalogUrl.lastIndexOf("/");
        value path = catalogUrl.substring(0, slashPos+1);
        value tracks = ArrayList<MediaMetadata>();
        if (exists jsonObj = fetchJSONFromUrl(catalogUrl),
            exists jsonTracks = jsonObj.getJSONArray(jsonMusic)) {
            for (j in 0:jsonTracks.length()) {
                tracks.add(buildFromJSON(jsonTracks.getJSONObject(j), path));
            }
        }
        return tracks.iterator();
//        }
//        catch (JSONException e) {
//            LogHelper.e(tag, e, "Could not retrieve music list");
//            throw Exception("Could not retrieve music list", e);
//        }
    }

}
