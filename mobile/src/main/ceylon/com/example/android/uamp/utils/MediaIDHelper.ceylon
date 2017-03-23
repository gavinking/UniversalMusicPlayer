import android.app {
    Activity
}
import android.content {
    Context
}
import android.support.v4.media {
    MediaBrowser=MediaBrowserCompat
}
import android.support.v4.media.session {
    MediaController=MediaControllerCompat
}

import java.util {
    Objects
}

shared class MediaIDHelper {

    shared static String mediaIdEmptyRoot = "__EMPTY_ROOT__";
    shared static String mediaIdRoot = "__ROOT__";
    shared static String mediaIdMusicsByGenre = "__BY_GENRE__";
    shared static String mediaIdMusicsBySearch = "__BY_SEARCH__";

    static value categorySeparator = '/';
    static value leafSeparator = '|';

    shared static Boolean equalIds(String? x, String ? y) => Objects.equals(x, y);

    static Boolean isValidCategory(String category)
            => !categorySeparator in category
            && !leafSeparator in category;

    shared static String createMediaID(String? musicID, String* categories) {
        value mediaID = StringBuilder();
        for (cat in categories) {
            if (!mediaID.empty) {
                mediaID.appendCharacter(categorySeparator);
            }
            "Invalid category: ``cat``"
            assert (isValidCategory(cat));
            mediaID.append(cat);
        }
        if (exists musicID) {
            mediaID.appendCharacter(leafSeparator)
                .append(musicID);
        }
        return mediaID.string;
    }

    shared static String? extractMusicIDFromMediaID(String? mediaID) {
        if (exists mediaID) {
            value pos = mediaID.firstOccurrence(leafSeparator);
            return if (exists pos) then mediaID[pos + 1...] else null;
        }
        else {
            return null;
        }
    }

    shared static String[] getHierarchy(String mediaID) {
        value pos = mediaID.firstOccurrence(leafSeparator);
        value initial = if (exists pos) then mediaID[0:pos] else mediaID;
        return initial.split(categorySeparator.equals).sequence();
    }

    shared static String? extractBrowseCategoryValueFromMediaID(String mediaID)
            => getHierarchy(mediaID)[1];

    shared static Boolean isBrowseable(String mediaID)
            => !leafSeparator in mediaID;

//    shared static String getParentMediaID(String mediaID) {
//        value hierarchy = getHierarchy(mediaID);
//        if (!isBrowseable(mediaID)) {
//            return createMediaID(null, *hierarchy);
//        }
//        if (hierarchy.size <= 1) {
//            return mediaIdRoot;
//        }
//        value parentHierarchy = hierarchy.initial(hierarchy.size-1);
//        return createMediaID(null, *parentHierarchy);
//    }

    shared static Boolean isMediaItemPlaying(Context context, MediaBrowser.MediaItem mediaItem)
            => if (is Activity context,
                    exists metadata = MediaController.getMediaController(context)?.metadata,
                    exists itemMusicId = extractMusicIDFromMediaID(mediaItem.description.mediaId),
                    exists currentPlayingMediaId = metadata.description.mediaId)
            then equalIds(currentPlayingMediaId, itemMusicId)
            else false;

    shared new () {}

}
