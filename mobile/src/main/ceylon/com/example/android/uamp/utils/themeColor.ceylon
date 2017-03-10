import android.content {
    Context
}
import android.content.pm {
    PackageManager
}

import java.lang {
    IntArray
}

shared Integer themeColor(Context context, Integer attribute, Integer defaultColor) {
    value packageName = context.packageName;
    try {
        value packageContext = context.createPackageContext(packageName, 0);
        value applicationInfo = context.packageManager.getApplicationInfo(packageName, 0);
        packageContext.setTheme(applicationInfo.theme);
        value theme = packageContext.theme;
        value ta = theme.obtainStyledAttributes(IntArray.with{ attribute });
        value themeColor = ta.getColor(0, defaultColor);
        ta.recycle();
        return themeColor;
    }
    catch (PackageManager.NameNotFoundException e) {
        e.printStackTrace();
        return 0;
    }
}

