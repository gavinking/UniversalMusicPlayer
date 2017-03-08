package com.example.android.uamp.ui;

import android.annotation.TargetApi;
import android.os.Build;
import android.view.View;
import android.widget.AdapterView;

public interface OnItemClickBase extends AdapterView.OnItemClickListener {
    @Override @TargetApi(Build.VERSION_CODES.JELLY_BEAN)
    public void onItemClick(AdapterView adapterView, View view, int i, long l);
}
