import android.os {
    Bundle
}
import com.example.android.uamp {
    R
}

shared class PlaceholderActivity() extends BaseActivity() {

    shared actual void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.Layout.activity_placeholder);
        initializeToolbar();
    }

}
