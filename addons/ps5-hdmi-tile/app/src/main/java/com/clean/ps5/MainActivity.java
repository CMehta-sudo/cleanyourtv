package com.clean.ps5;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            Uri uri = Uri.parse("content://android.media.tv/passthrough/com.realtek.tv.passthrough%2F.hdmiinput.HDMITvInputService%2FHW151519232");
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            intent.setDataAndType(uri, "vnd.android.cursor.item/channel");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (Exception ignored) {
        }
        finish();
    }
}
