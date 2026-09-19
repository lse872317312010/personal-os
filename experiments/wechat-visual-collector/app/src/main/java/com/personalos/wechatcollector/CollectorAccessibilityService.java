package com.personalos.wechatcollector;

import android.accessibilityservice.AccessibilityService;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class CollectorAccessibilityService extends AccessibilityService {
    private static final String WECHAT = "com.tencent.mm";
    private WindowManager windowManager;
    private TextView bubble;
    private WindowManager.LayoutParams params;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean running;
    private int currentPage;
    private int targetPages;
    private long intervalMs;
    private String sessionId;
    private String groupLabel;

    @Override public void onServiceConnected() {
        super.onServiceConnected();
        showBubble();
    }

    @Override public void onAccessibilityEvent(AccessibilityEvent event) { }
    @Override public void onInterrupt() { }

    @Override public void onDestroy() {
        if (windowManager != null && bubble != null) windowManager.removeView(bubble);
        super.onDestroy();
    }

    private void showBubble() {
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        bubble = new TextView(this);
        bubble.setText("采");
        bubble.setTextColor(Color.WHITE);
        bubble.setTextSize(18);
        bubble.setGravity(Gravity.CENTER);
        int size = dp(52);
        GradientDrawable background = new GradientDrawable();
        background.setColor(Color.rgb(37, 99, 235));
        background.setShape(GradientDrawable.OVAL);
        bubble.setBackground(background);
        params = new WindowManager.LayoutParams(
                size, size,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.END;
        params.x = dp(12);
        params.y = dp(220);
        bubble.setClickable(true);
        bubble.setOnClickListener(v -> toggleCollection());
        windowManager.addView(bubble, params);
    }

    private void toggleCollection() {
        if (running) {
            stopCollection("已手动停止");
            return;
        }
        android.content.SharedPreferences preferences =
                getSharedPreferences("collector_settings", MODE_PRIVATE);
        targetPages = Math.max(1, Math.min(30, preferences.getInt("pages", 5)));
        intervalMs = Math.max(800L, Math.min(10_000L, preferences.getLong("interval_ms", 1600L)));
        groupLabel = preferences.getString("group_label", "未命名群");
        sessionId = UUID.randomUUID().toString();
        currentPage = 0;
        running = true;
        bubble.setText("停");
        toast("开始连续采集 " + targetPages + " 屏；再次点击可停止");
        captureCycle();
    }

    private void captureCycle() {
        if (!running) return;
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || root.getPackageName() == null || !WECHAT.contentEquals(root.getPackageName())) {
            stopCollection("已停止：请保持在微信目标群聊");
            return;
        }
        List<String> lines = new ArrayList<>();
        collect(root, lines);
        try {
            int inserted = ArchiveStore.append(
                    this, sessionId, groupLabel, currentPage, lines);
            currentPage++;
            toast("第 " + currentPage + "/" + targetPages + " 屏，新增 " + inserted + " 条");
        } catch (Exception error) {
            stopCollection("保存失败：" + error.getMessage());
            return;
        }
        if (currentPage >= targetPages) {
            stopCollection("采集完成，共 " + currentPage + " 屏");
            return;
        }
        AccessibilityNodeInfo scrollable = findScrollable(root);
        if (scrollable == null) {
            stopCollection("已停止：当前页面没有找到可滚动区域");
            return;
        }
        boolean accepted = scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
        if (!accepted) {
            stopCollection("已停止：微信未接受翻页动作");
            return;
        }
        handler.postDelayed(this::captureCycle, intervalMs);
    }

    private void stopCollection(String message) {
        running = false;
        handler.removeCallbacksAndMessages(null);
        if (bubble != null) bubble.setText("采");
        toast(message);
    }

    private void collect(AccessibilityNodeInfo node, List<String> output) {
        CharSequence text = node.getText();
        if (text != null && !text.toString().trim().isEmpty()) output.add(text.toString());
        CharSequence description = node.getContentDescription();
        if (description != null && !description.toString().trim().isEmpty()) output.add(description.toString());
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child != null) collect(child, output);
        }
    }

    private AccessibilityNodeInfo findScrollable(AccessibilityNodeInfo node) {
        if (node.isScrollable()) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo child = node.getChild(i);
            if (child == null) continue;
            AccessibilityNodeInfo result = findScrollable(child);
            if (result != null) return result;
        }
        return null;
    }

    private void toast(String message) {
        handler.post(() -> Toast.makeText(this, message, Toast.LENGTH_SHORT).show());
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

}
