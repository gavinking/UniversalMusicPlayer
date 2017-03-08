import android.app {
    SearchManager
}
import android.content {
    Intent
}
import android.media.browse {
    MediaBrowser
}
import android.os {
    Bundle,
    Parcelable
}
import android.provider {
    MediaStore
}

import com.example.android.uamp {
    R
}
import com.example.android.uamp.utils {
    LogHelper
}

import java.util {
    Objects
}

shared class MusicPlayerActivity
        extends BaseActivity
        satisfies MediaFragmentListener {

    static String savedMediaId = "com.example.android.uamp.MEDIA_ID";
    static String fragmentTag = "uamp_list_container";

    shared static String extraStartFullscreen = "com.example.android.uamp.EXTRA_START_FULLSCREEN";
    shared static String extraCurrentMediaDescription = "com.example.android.uamp.CURRENT_MEDIA_DESCRIPTION";

    variable Bundle? mVoiceSearchParams = null;

    value tag = LogHelper.makeLogTag(`MusicPlayerActivity`);

    value browseFragment {
        assert (is MediaBrowserFragment? fragment
                = fragmentManager.findFragmentByTag(fragmentTag));
        return fragment;
    }

    shared new () extends BaseActivity() {}

    shared actual void onCreate(Bundle? savedInstanceState) {
        super.onCreate(savedInstanceState);
        LogHelper.d(tag, "Activity onCreate");
        setContentView(R.Layout.activity_player);
        initializeToolbar();
        initializeFromParams(savedInstanceState, intent);
        if (!exists savedInstanceState) {
            startFullScreenActivityIfNeeded(intent);
        }
    }

    shared actual void onSaveInstanceState(Bundle outState) {
        if (exists mediaId = mediaId) {
            outState.putString(savedMediaId, mediaId);
        }
        super.onSaveInstanceState(outState);
    }

    shared actual void onMediaItemSelected(MediaBrowser.MediaItem item) {
        LogHelper.d(tag, "onMediaItemSelected, mediaId=" + item.mediaId);
        if (item.playable) {
            mediaController.transportControls
                .playFromMediaId(item.mediaId, null);
        } else if (item.browsable) {
            navigateToBrowser(item.mediaId);
        } else {
            LogHelper.w(tag, "Ignoring MediaItem that is neither browsable nor playable: ", "mediaId=", item.mediaId);
        }
    }

    shared actual void setToolbarTitle(String? title) {
        LogHelper.d(tag, "Setting toolbar title to ", title);
        if (exists titleString = getString(R.String.app_name)) {
            setTitle(titleString);
        }
    }

    shared actual void onNewIntent(Intent intent) {
        LogHelper.d(tag, "onNewIntent, intent=``intent``");
        initializeFromParams(null, intent);
        startFullScreenActivityIfNeeded(intent);
    }

    void startFullScreenActivityIfNeeded(Intent? intent) {
        if (exists intent, intent.getBooleanExtra(extraStartFullscreen, false)) {
            value fullScreenIntent
                    = Intent(this, `FullScreenPlayerActivity`)
                    .setFlags(Intent.flagActivitySingleTop.or(Intent.flagActivityClearTop))
                    .putExtra(extraCurrentMediaDescription,
                        intent.getParcelableExtra<Parcelable>
                            (extraCurrentMediaDescription));
            startActivity(fullScreenIntent);
        }
    }

    void initializeFromParams(Bundle? savedInstanceState, Intent intent) {
        String? mediaId;
        if (intent.action exists,
            intent.action==MediaStore.intentActionMediaPlayFromSearch) {
            mVoiceSearchParams = intent.extras;
            LogHelper.d(tag, "Starting from voice search query=",
                mVoiceSearchParams?.getString(SearchManager.query));
            mediaId = null;
        } else if (exists savedInstanceState) {
            mediaId = savedInstanceState.getString(savedMediaId);
        }
        else {
            mediaId = null;
        }
        navigateToBrowser(mediaId);
    }

    void navigateToBrowser(String? mediaId) {
//        LogHelper.d(tag, "navigateToBrowser, mediaId=``mediaId``");
        if (!browseFragment exists || !Objects.equals(browseFragment?.mediaId, mediaId)) {
            value fragment = MediaBrowserFragment();
            fragment.mediaId = mediaId;
            value transaction = fragmentManager.beginTransaction();
            transaction.setCustomAnimations(
                R.Animator.slide_in_from_right,
                R.Animator.slide_out_to_left,
                R.Animator.slide_in_from_left,
                R.Animator.slide_out_to_right);
            transaction.replace(R.Id.container, fragment, fragmentTag);
            if (exists mediaId) {
                transaction.addToBackStack(null);
            }
            transaction.commit();
        }
    }

    shared String? mediaId {
        if (exists fragment = browseFragment) {
            return fragment.mediaId;
        }
        else {
            return null;
        }
    }

    shared actual void onMediaControllerConnected() {
        if (exists params = mVoiceSearchParams) {
            value query = params.getString(SearchManager.query);
            mediaController.transportControls.playFromSearch(query, mVoiceSearchParams);
            mVoiceSearchParams = null;
        }
        browseFragment?.onConnected();
    }

}
