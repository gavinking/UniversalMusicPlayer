import android.app {
    Activity
}
import android.content {
    Context
}
import android.media.browse {
    MediaBrowser
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
            => category.indexOf(categorySeparator.string) < 0
            && category.indexOf(leafSeparator.string) < 0;

    shared static String createMediaID(String? musicID, String* categories) {
        value sb = StringBuilder();
        variable value i = 0;
        while (i<categories.size) {
            assert (exists cat = categories.get(i));
            "Invalid category: ``cat``"
            assert (isValidCategory(cat));
            sb.append(cat);
            if (i<categories.size - 1) {
                sb.appendCharacter(categorySeparator);
            }
            i++;
        }
        if (exists musicID) {
            sb.appendCharacter(leafSeparator).append(musicID);
        }
        return sb.string;
    }

    shared static String? extractMusicIDFromMediaID(String mediaID) {
        value pos = mediaID.indexOf(leafSeparator.string);
        return pos>=0 then mediaID.substring(pos + 1);
    }

    shared static String[] getHierarchy(variable String mediaID) {
        value pos = mediaID.indexOf(leafSeparator.string);
        if (pos>=0) {
            mediaID = mediaID.substring(0, pos);
        }
        return mediaID.split(categorySeparator.equals).sequence();
    }

    shared static String? extractBrowseCategoryValueFromMediaID(String mediaID) {
        value hierarchy = getHierarchy(mediaID);
        return if (hierarchy.size == 2) then hierarchy[1] else null;
    }

    shared static Boolean isBrowseable(String mediaID)
            => mediaID.indexOf(leafSeparator.string) < 0;

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

    shared static Boolean isMediaItemPlaying(Context context, MediaBrowser.MediaItem mediaItem) {
        if (is Activity context,
            exists metadata = context.mediaController?.metadata) {
            value itemMusicId = extractMusicIDFromMediaID(mediaItem.description.mediaId);
            if (exists currentPlayingMediaId = metadata.description.mediaId,
                MediaIDHelper.equalIds(currentPlayingMediaId, itemMusicId)) {
                return true;
            }
        }
        return false;
    }

    shared new () {}

}
