import android.content {
    Context
}
import android.app {
    UiModeManager
}
import android.content.res {
    Configuration
}

shared Boolean tvUiMode(Context context) {
    assert (is UiModeManager modeManager = context.getSystemService(Context.uiModeService));
    return modeManager.currentModeType == Configuration.uiModeTypeTelevision;
}