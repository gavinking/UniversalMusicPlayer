import android.app {
    Activity,
    UiModeManager
}
import android.content {
    Intent
}
import android.content.res {
    Configuration
}
import android.os {
    Bundle
}
//import com.example.android.uamp.ui.tv {
//    TvPlaybackActivity
//}
import com.example.android.uamp.utils {
    LogHelper
}

shared class NowPlayingActivity() extends Activity() {

    value tag = LogHelper.makeLogTag(`NowPlayingActivity`);

    shared actual void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LogHelper.d(tag, "onCreate");
        assert (is UiModeManager uiModeManager = getSystemService(uiModeService));
        Intent newIntent;
        if (uiModeManager.currentModeType == Configuration.uiModeTypeTelevision) {
            LogHelper.d(tag, "Running on a TV Device");
//            newIntent = Intent(this, `TvPlaybackActivity`);
            "No TV"
            assert (false);
        } else {
            LogHelper.d(tag, "Running on a non-TV Device");
            newIntent = Intent(this, `MusicPlayerActivity`);
        }
        startActivity(newIntent);
        finish();
    }

}
