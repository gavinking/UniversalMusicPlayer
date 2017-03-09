import android.content {
    Context
}

import com.google.android.gms.cast.framework {
    CastOptions,
    OptionsProvider
}

shared class CastOptionsProvider() satisfies OptionsProvider {

    getCastOptions(Context context)
            => CastOptions.Builder()
            .setReceiverApplicationId(context.getString(R.String.cast_application_id))
            .build();

    getAdditionalSessionProviders(Context context) => null;

}
