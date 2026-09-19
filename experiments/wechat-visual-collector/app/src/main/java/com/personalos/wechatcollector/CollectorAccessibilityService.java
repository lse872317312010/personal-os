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

public class CollectorAccessibilityService extends AccessibilityService {
    private static final String WECHAT = "com.tencent.mm";
    private WindowManager windowManager;
    private TextView bubble;
    private WindowManager.LayoutParams params;

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
        bubble.setOnClickListener(v -> captureAndScroll());
        bubble.setOnTouchListener(new DragListener());
        windowManager.addView(bubble, params);
    }

    private void captureAndScroll() {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || root.getPackageName() == null || !WECHAT.contentEquals(root.getPackageName())) {
            toast("请先打开微信目标群聊");
            return;
        }
        List<String> lines = new ArrayList<>();
        collect(root, lines);
        try {
            int inserted = ArchiveStore.append(this, lines);
            toast("保存 " + inserted + " 条新文本，正在翻到更早消息");
        } catch (Exception error) {
            toast("保存失败：" + error.getMessage());
            return;
        }
        AccessibilityNodeInfo scrollable = findScrollable(root);
        if (scrollable == null) {
            toast("当前页面没有找到可滚动区域");
            return;
        }
        new Handler(Looper.getMainLooper()).postDelayed(
                () -> scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD), 350);
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
        new Handler(Looper.getMainLooper()).post(() -> Toast.makeText(this, message, Toast.LENGTH_SHORT).show());
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    private final class DragListener implements View.OnTouchListener {
        private int startX, startY;
        private float downX, downY;
        private boolean moved;
        @Override public boolean onTouch(View view, MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    startX = params.x; startY = params.y;
                    downX = event.getRawX(); downY = event.getRawY(); moved = false;
                    return true;
                case MotionEvent.ACTION_MOVE:
                    float dx = event.getRawX() - downX;
                    float dy = event.getRawY() - downY;
                    if (Math.abs(dx) + Math.abs(dy) > dp(8)) moved = true;
                    params.x = Math.max(0, startX - Math.round(dx));
                    params.y = Math.max(0, startY + Math.round(dy));
                    windowManager.updateViewLayout(bubble, params);
                    return true;
                case MotionEvent.ACTION_UP:
                    if (!moved) view.performClick();
                    return true;
                default: return false;
            }
        }
    }
}
