import android {
    AndroidR=R
}
import android.app {
    ActivityOptions,
    ActivityManager
}
import android.content {
    Intent,
    ComponentName
}
import android.content.res {
    Configuration
}
import android.graphics {
    BitmapFactory
}
import android.media {
    MediaMetadata
}
import android.media.browse {
    MediaBrowser
}
import android.media.session {
    MediaController,
    PlaybackState,
    MediaSession
}
import android.os {
    Bundle,
    Handler,
    Build,
    RemoteException
}
import android.support.design.widget {
    NavigationView
}
import android.support.v4.view {
    GravityCompat
}
import android.support.v4.widget {
    DrawerLayout
}
import android.support.v7.app {
    ActionBarDrawerToggle,
    AppCompatActivity,
    MediaRouteButton
}
import android.support.v7.widget {
    Toolbar
}
import android.view {
    Menu,
    MenuItem,
    View
}

import com.example.android.uamp {
    R,
    MusicService
}
import com.example.android.uamp.utils {
    LogHelper,
    ResourceHelper,
    isOnline
}
import com.google.android.gms.cast.framework {
    CastButtonFactory,
    CastContext,
    CastState,
    IntroductoryOverlay
}

import java.lang {
    CharSequence
}
import ceylon.language.meta.model {
    Class
}

shared abstract class BaseActivity()
        extends ActionBarCastActivity()
        satisfies MediaBrowserProvider {

    value tag = LogHelper.makeLogTag(`BaseActivity`);

    shared actual late MediaBrowser mediaBrowser;
    late variable PlaybackControlsFragment controlsFragment;

    void showPlaybackControls() {
        LogHelper.d(tag, "showPlaybackControls");
        if (isOnline(this)) {
            fragmentManager.beginTransaction()
                .setCustomAnimations(
                    R.Animator.slide_in_from_bottom,
                    R.Animator.slide_out_to_bottom,
                    R.Animator.slide_in_from_bottom,
                    R.Animator.slide_out_to_bottom)
                .show(controlsFragment)
                .commit();
        }
    }

    void hidePlaybackControls() {
        LogHelper.d(tag, "hidePlaybackControls");
        fragmentManager.beginTransaction()
            .hide(controlsFragment)
            .commit();
    }

    function shouldShowControls() {
        if (exists mediaController = this.mediaController,
            mediaController.metadata exists,
            mediaController.playbackState exists) {
            return mediaController.playbackState.state != PlaybackState.stateError;
        }
        else {
            return false;
        }
    }

    class MediaControllerCallback()
            extends MediaController.Callback() {
        shared actual void onPlaybackStateChanged(PlaybackState state) {
            if (shouldShowControls()) {
                showPlaybackControls();
            } else {
                LogHelper.d(tag, "mediaControllerCallback.onPlaybackStateChanged: hiding controls because state is ", state.state);
                hidePlaybackControls();
            }
        }
        shared actual void onMetadataChanged(MediaMetadata metadata) {
            if (shouldShowControls()) {
                showPlaybackControls();
            } else {
                LogHelper.d(tag, "mediaControllerCallback.onMetadataChanged: hiding controls because metadata is null");
                hidePlaybackControls();
            }
        }
    }

    shared default void onMediaControllerConnected() {}

    void connectToSession(MediaSession.Token token) {
        mediaController = MediaController(this, token);
        mediaController.registerCallback(MediaControllerCallback());
        if (shouldShowControls()) {
            showPlaybackControls();
        } else {
            LogHelper.d(tag, "connectionCallback.onConnected: hiding controls because metadata is null");
            hidePlaybackControls();
        }
        controlsFragment.onConnected();
        onMediaControllerConnected();
    }

    shared actual default void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LogHelper.d(tag, "Activity onCreate");
        if (Build.VERSION.sdkInt >= 21) {
            value taskDesc
                    = ActivityManager.TaskDescription(title.string,
                        BitmapFactory.decodeResource(resources, R.Drawable.ic_launcher_white),
                        ResourceHelper.getThemeColor(this, R.Attr.colorPrimary, AndroidR.Color.darker_gray));
            setTaskDescription(taskDesc);
        }
        mediaBrowser = MediaBrowser(this,
            ComponentName(this, `MusicService`),
            object extends MediaBrowser.ConnectionCallback() {
                shared actual void onConnected() {
                    LogHelper.d(tag, "onConnected");
                    try {
                        connectToSession(mediaBrowser.sessionToken);
                    }
                    catch (RemoteException e) {
                        //LogHelper.e(tag, e, "could not connect media controller");
                        hidePlaybackControls();
                    }
                }
            },
            null);
    }

    shared actual void onStart() {
        super.onStart();
        LogHelper.d(tag, "Activity onStart");
        "Mising fragment with id 'controls'. Cannot continue."
        assert (is PlaybackControlsFragment fragment
                = fragmentManager.findFragmentById(R.Id.fragment_playback_controls));
        controlsFragment = fragment;
        hidePlaybackControls();
        mediaBrowser.connect();
    }

    shared actual void onStop() {
        super.onStop();
        LogHelper.d(tag, "Activity onStop");
        mediaController?.unregisterCallback(MediaControllerCallback());
        mediaBrowser.disconnect();
    }

}


shared abstract class ActionBarCastActivity()
        extends AppCompatActivity() {

    value tag = LogHelper.makeLogTag(`ActionBarCastActivity`);
    value delayMillis = 1000;

    variable CastContext? castContext = null;
    variable MenuItem? routeMenuItem = null;
    variable Toolbar? toolbar = null;
    variable ActionBarDrawerToggle? mDrawerToggle = null;
    variable DrawerLayout? drawerLayout = null;
    variable Boolean toolbarInitialized = false;
    variable Integer itemToOpenWhenDrawerCloses = -1;

    shared void onCastStateChanged(Integer newState) {
        if (newState != CastState.noDevicesAvailable) {
            Handler()
                .postDelayed(() {
                    assert (exists item = routeMenuItem);
                    if (item.visible) {
                        LogHelper.d(tag, "Cast Icon is visible");
                        showFtu();
                    }
                },
                delayMillis);
        }
    }

    shared actual default void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LogHelper.d(tag, "Activity onCreate");
        castContext = CastContext.getSharedInstance(this);
    }

    shared actual default void onStart() {
        super.onStart();
        "You must run super.initializeToolbar at the end of your onCreate method"
        assert (toolbarInitialized);
    }

    shared actual void onPostCreate(Bundle savedInstanceState) {
        super.onPostCreate(savedInstanceState);
        mDrawerToggle?.syncState();
    }

    shared actual void onResume() {
        super.onResume();
        castContext?.addCastStateListener(onCastStateChanged);
        fragmentManager.addOnBackStackChangedListener(updateDrawerToggle);
    }

    shared actual void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        mDrawerToggle?.onConfigurationChanged(newConfig);
    }

    shared actual void onPause() {
        super.onPause();
        castContext?.removeCastStateListener(onCastStateChanged);
        fragmentManager.removeOnBackStackChangedListener(updateDrawerToggle);
    }

    shared actual Boolean onCreateOptionsMenu(Menu menu) {
        super.onCreateOptionsMenu(menu);
        menuInflater.inflate(R.Menu.main, menu);
        routeMenuItem
                = CastButtonFactory.setUpMediaRouteButton(applicationContext,
                    menu, R.Id.media_route_menu_item);
        return true;
    }

    shared actual Boolean onOptionsItemSelected(MenuItem? item) {
        if (exists toggle = mDrawerToggle,
            toggle.onOptionsItemSelected(item)) {
            return true;
        }
        if (exists item,
            item.itemId == AndroidR.Id.home) {
            onBackPressed();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    shared actual void onBackPressed() {
        if (exists layout = drawerLayout,
            layout.isDrawerOpen(GravityCompat.start)) {
            layout.closeDrawers();
        }
        else {
            value fragmentManager = this.fragmentManager;
            if (fragmentManager.backStackEntryCount>0) {
                fragmentManager.popBackStack();
            } else {
                super.onBackPressed();
            }
        }
    }

    shared actual void setTitle(CharSequence title) {
        super.setTitle(title);
        toolbar?.setTitle(title);
    }

    shared actual void setTitle(Integer titleId) {
        super.setTitle(titleId);
        toolbar?.setTitle(titleId);
    }

    shared void initializeToolbar() {
        "Layout is required to include a Toolbar with id 'toolbar'"
        assert (is Toolbar toolbar = findViewById(R.Id.toolbar));
        this.toolbar = toolbar;
        toolbar.inflateMenu(R.Menu.main);
        assert (is DrawerLayout? layout = findViewById(R.Id.drawer_layout));
        drawerLayout = layout;
        if (exists layout) {
            "Layout requires a NavigationView with id 'nav_view'"
            assert (is NavigationView navigationView = findViewById(R.Id.nav_view));
            mDrawerToggle
                    = ActionBarDrawerToggle(this, drawerLayout, toolbar,
                        R.String.open_content_drawer,
                        R.String.close_content_drawer);

            layout.addDrawerListener(object satisfies DrawerLayout.DrawerListener {
                shared actual void onDrawerClosed(View drawerView) {
                    mDrawerToggle?.onDrawerClosed(drawerView);
                    if (itemToOpenWhenDrawerCloses>=0,
                        exists activityClass
                                = if (itemToOpenWhenDrawerCloses == R.Id.navigation_allmusic)
                                    then `MusicPlayerActivity`
                                else if (itemToOpenWhenDrawerCloses == R.Id.navigation_playlists)
                                    then `PlaceholderActivity`
                                else null) {
                        value extras
                                = ActivityOptions.makeCustomAnimation(outer,
                                    R.Anim.fade_in,
                                    R.Anim.fade_out)
                                .toBundle();
                        startActivity(Intent(outer, activityClass of Class<Object>), extras);
                        finish();
                    }
                }
                shared actual void onDrawerStateChanged(Integer newState)
                        => mDrawerToggle?.onDrawerStateChanged(newState);
                shared actual void onDrawerSlide(View drawerView, Float slideOffset)
                        => mDrawerToggle?.onDrawerSlide(drawerView, slideOffset);
                shared actual void onDrawerOpened(View drawerView) {
                    mDrawerToggle?.onDrawerOpened(drawerView);
                    supportActionBar?.setTitle(R.String.app_name);
                }
            });

            populateDrawerItems(navigationView);
            setSupportActionBar(toolbar);
            updateDrawerToggle();
        }
        else {
            setSupportActionBar(toolbar);
        }
        toolbarInitialized = true;
    }

    void populateDrawerItems(NavigationView navigationView) {
        navigationView.setNavigationItemSelectedListener((menuItem) {
            menuItem.setChecked(true);
            itemToOpenWhenDrawerCloses = menuItem.itemId;
            drawerLayout?.closeDrawers();
            return true;
        });

        Object self = this; //TODO: remove temp hack
        if (self is MusicPlayerActivity) {
            navigationView.setCheckedItem(R.Id.navigation_allmusic);
        }
        else if (self is PlaceholderActivity) {
            navigationView.setCheckedItem(R.Id.navigation_playlists);
        }
    }

    void updateDrawerToggle() {
        if (exists toggle = mDrawerToggle) {
            value isRoot = fragmentManager.backStackEntryCount == 0;
            toggle.drawerIndicatorEnabled = isRoot;
            if (exists supportActionBar = this.supportActionBar) {
                supportActionBar.setDisplayShowHomeEnabled(!isRoot);
                supportActionBar.setDisplayHomeAsUpEnabled(!isRoot);
                supportActionBar.setHomeButtonEnabled(!isRoot);
            }
            if (isRoot) {
                toggle.syncState();
            }
        }
    }

    void showFtu() {
        if (toolbar?.menu?.findItem(R.Id.media_route_menu_item)?.actionView
                is MediaRouteButton) {
            IntroductoryOverlay.Builder(this, routeMenuItem)
                .setTitleText(R.String.touch_to_cast)
                .setSingleTime()
                .build()
                .show();
        }
    }

}
