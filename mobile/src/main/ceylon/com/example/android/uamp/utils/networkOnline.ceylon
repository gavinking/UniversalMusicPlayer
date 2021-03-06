import android.content {
    Context
}
import android.net {
    ConnectivityManager
}

shared Boolean networkOnline(Context context) {
    assert (is ConnectivityManager connMgr = context.getSystemService(Context.connectivityService));
    return if (exists networkInfo = connMgr.activeNetworkInfo) then networkInfo.connected else false;
}
