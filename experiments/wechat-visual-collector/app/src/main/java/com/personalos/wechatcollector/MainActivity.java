package com.personalos.wechatcollector;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.core.content.FileProvider;

import java.io.File;

public class MainActivity extends Activity {
    private TextView preview;
    private EditText groupInput;
    private EditText pagesInput;
    private EditText intervalInput;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(buildUi());
        refresh();
    }

    private View buildUi() {
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(28), dp(20), dp(20));

        TextView title = text("微信视觉采集实验", 24, true);
        content.addView(title);
        content.addView(text(
                "v0.2 一键连续采集\n1. 填写群标签、屏数和间隔并保存\n2. 开启无障碍服务\n3. 打开自己的目标微信群\n4. 点击蓝色“采”：自动采集和翻页；按钮变成“停”，再次点击立即停止\n5. 回到这里查看或分享JSONL\n\n本实验不自动登录、不读取微信数据库。", 16, false));

        android.content.SharedPreferences preferences =
                getSharedPreferences("collector_settings", MODE_PRIVATE);
        groupInput = input("群标签", preferences.getString("group_label", "测试群"));
        pagesInput = input("连续采集屏数（1～30）", String.valueOf(preferences.getInt("pages", 5)));
        intervalInput = input("翻页间隔毫秒（800～10000）", String.valueOf(preferences.getLong("interval_ms", 1600L)));
        content.addView(groupInput);
        content.addView(pagesInput);
        content.addView(intervalInput);
        content.addView(button("保存采集设置", v -> saveSettings()));

        content.addView(button("开启/检查无障碍权限", v ->
                startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))));
        content.addView(button("打开微信", v -> {
            Intent launch = getPackageManager().getLaunchIntentForPackage("com.tencent.mm");
            if (launch == null) toast("没有找到微信"); else startActivity(launch);
        }));
        content.addView(button("刷新记录", v -> refresh()));
        content.addView(button("分享JSONL", v -> share()));
        content.addView(button("清空全部记录", v -> { ArchiveStore.clear(this); refresh(); }));

        preview = text("", 13, false);
        preview.setTextIsSelectable(true);
        preview.setBackgroundColor(Color.rgb(245, 247, 250));
        preview.setPadding(dp(12), dp(12), dp(12), dp(12));
        content.addView(preview);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        return scroll;
    }

    private Button button(String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(listener);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(8);
        button.setLayoutParams(lp);
        return button;
    }

    private EditText input(String hint, String value) {
        EditText input = new EditText(this);
        input.setHint(hint);
        input.setText(value);
        input.setSingleLine(true);
        input.setTextSize(16);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.topMargin = dp(6);
        input.setLayoutParams(lp);
        return input;
    }

    private void saveSettings() {
        try {
            String label = groupInput.getText().toString().trim();
            if (label.isEmpty()) throw new IllegalArgumentException("群标签不能为空");
            int pages = Integer.parseInt(pagesInput.getText().toString().trim());
            long interval = Long.parseLong(intervalInput.getText().toString().trim());
            if (pages < 1 || pages > 30) throw new IllegalArgumentException("屏数必须为1～30");
            if (interval < 800 || interval > 10_000) throw new IllegalArgumentException("间隔必须为800～10000毫秒");
            getSharedPreferences("collector_settings", MODE_PRIVATE).edit()
                    .putString("group_label", label)
                    .putInt("pages", pages)
                    .putLong("interval_ms", interval)
                    .apply();
            toast("设置已保存");
        } catch (Exception error) {
            toast(error.getMessage());
        }
    }

    private TextView text(String value, int sp, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(Color.rgb(20, 27, 38));
        if (bold) view.setTypeface(view.getTypeface(), android.graphics.Typeface.BOLD);
        view.setLineSpacing(0, 1.15f);
        return view;
    }

    private void refresh() {
        if (preview == null) return;
        try { preview.setText(ArchiveStore.read(this)); }
        catch (Exception error) { preview.setText("读取失败：" + error.getMessage()); }
    }

    private void share() {
        try {
            File file = ArchiveStore.export(this);
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".files", file);
            Intent intent = new Intent(Intent.ACTION_SEND);
            intent.setType("application/x-ndjson");
            intent.putExtra(Intent.EXTRA_STREAM, uri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(Intent.createChooser(intent, "导出可见文本"));
        } catch (Exception error) { toast("导出失败：" + error.getMessage()); }
    }

    private void toast(String value) { Toast.makeText(this, value, Toast.LENGTH_SHORT).show(); }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
}
