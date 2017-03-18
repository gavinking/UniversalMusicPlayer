import android.graphics {
    Bitmap
}
import android.os {
    AsyncTask
}
import android.util {
    LruCache
}

import com.example.android.uamp.utils {
    BitmapHelper
}

import java.io {
    IOException
}
import java.lang {
    ObjectArray,
    Runtime
}

shared class AlbumArtCache {

    static value maxAlbumArtCacheSize = 12 * 1024 * 1024;
    static value maxArtWidth = 800;
    static value maxArtHeight = 480;
    static value maxArtWidthIcon = 128;
    static value maxArtHeightIcon = 128;
    static value bigBitmapIndex = 0;
    static value iconBitmapIndex = 1;

//    value tag = LogHelper.makeLogTag(`AlbumArtCache`);

    value max = min {
        maxAlbumArtCacheSize,
        runtime.maxIntegerValue,
        Runtime.runtime.maxMemory() / 4
    };
    object cache extends LruCache<String,ObjectArray<Bitmap>>(max) {
        sizeOf(String key, ObjectArray<Bitmap> array)
                => array.get(bigBitmapIndex).byteCount
                 + array.get(iconBitmapIndex).byteCount;
    }

    shared new instance {}

    shared Bitmap? getBigImage(String? artUrl)
            => if (exists result = cache.get(artUrl))
            then result.get(bigBitmapIndex)
            else null;

    shared Bitmap? getIconImage(String? artUrl)
            => if (exists result = cache.get(artUrl))
            then result.get(iconBitmapIndex)
            else null;

    shared void fetch(String? artUrl, onFetched) {
        void onFetched(String? artUrl, Bitmap? bigImage, Bitmap? iconImage);

        if (exists bitmap = cache.get(artUrl)) {
//            LogHelper.d(tag, "getOrFetch: album art is in cache, using it", artUrl);
            onFetched(artUrl, bitmap.get(bigBitmapIndex), bitmap.get(iconBitmapIndex));
        }
        else {
//            LogHelper.d(tag, "getOrFetch: starting asynctask to fetch ", artUrl);

            object extends AsyncTask<Anything,Anything,ObjectArray<Bitmap>>() {

                shared actual ObjectArray<Bitmap>? doInBackground(Anything* objects) {
                    try {
                        value bitmap = BitmapHelper.fetchAndRescaleBitmap(artUrl, maxArtWidth, maxArtHeight);
                        value icon = BitmapHelper.scaleBitmap(bitmap, maxArtWidthIcon, maxArtHeightIcon);
                        value bitmaps = ObjectArray<Bitmap>.with { bitmap, icon };
                        cache.put(artUrl, bitmaps);
                        return bitmaps;
                    }
                    catch (IOException e) {
                        return null;
                    }
                    //LogHelper.d(tag, "doInBackground: putting bitmap in cache. cache size=" +mCache.size());

                }

                shared actual void onPostExecute(ObjectArray<Bitmap>? bitmaps) {
                    if (exists bitmaps) {
                        onFetched(artUrl, bitmaps.get(bigBitmapIndex), bitmaps.get(iconBitmapIndex));
                    } else {
                        //listener.onError(artUrl, IllegalArgumentException("got null bitmaps"));
                    }
                }

            }.execute();

        }
    }

}
