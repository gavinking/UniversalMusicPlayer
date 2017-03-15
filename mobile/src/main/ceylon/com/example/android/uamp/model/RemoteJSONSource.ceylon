import android.support.v4.media {
    MediaMetadata=MediaMetadataCompat
}

import java.io {
    BufferedReader,
    InputStreamReader
}
import java.net {
    URL
}

import org.json {
    JSONObject,
    JSONException
}

shared class RemoteJSONSource() satisfies {MediaMetadata*} {

//    static value tag = LogHelper.makeLogTag(`RemoteJSONSource`);

    value catalogUrl = "http://storage.googleapis.com/automotive-media/music.json";

    function buildFromJSON(JSONObject json, String basePath) {

        function withBasePath(String path)
                => path.startsWith("http") then path
                else basePath + path;

        value title = json.getString("title");
        value album = json.getString("album");
        value artist = json.getString("artist");
        value genre = json.getString("genre");
        value source = withBasePath(json.getString("source"));
        value iconUrl = withBasePath(json.getString("image"));
        value trackNumber = json.getInt("trackNumber");
        value totalTrackCount = json.getInt("totalTrackCount");
        value duration = json.getInt("duration") * 1000;
//        LogHelper.d(tag, "Found music track: ", json);

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
        try {
            value slashPos = catalogUrl.lastIndexOf("/");
            value path = catalogUrl[0:slashPos+1];
            value jsonTracks = fetchJSONFromUrl(catalogUrl)?.getJSONArray("music");
            return {
                if (exists jsonTracks)
                for (j in 0:jsonTracks.length())
                buildFromJSON(jsonTracks.getJSONObject(j), path)
            }.iterator();
        }
        catch (JSONException e) {
//            LogHelper.e(tag, e, "Could not retrieve music list");
            throw Exception("Could not retrieve music list", e);
        }
    }

}
