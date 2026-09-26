package com.personalos.wechatcollector;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class ArchiveStore {
    private static final String FILE_NAME = "wechat_visible_text.jsonl";
    private ArchiveStore() {}

    static File file(Context context) { return new File(context.getFilesDir(), FILE_NAME); }

    static synchronized int append(
            Context context,
            String sessionId,
            String groupLabel,
            int pageIndex,
            List<String> lines) throws Exception {
        Set<String> existing = hashes(context);
        int inserted = 0;
        try (FileOutputStream stream = context.openFileOutput(FILE_NAME, Context.MODE_APPEND)) {
            for (String line : lines) {
                String normalized = line.replaceAll("\\s+", " ").trim();
                if (normalized.length() < 2) continue;
                String hash = sha256(normalized);
                if (!existing.add(hash)) continue;
                JSONObject object = new JSONObject();
                object.put("capturedAt", System.currentTimeMillis());
                object.put("sessionId", sessionId);
                object.put("groupLabel", groupLabel);
                object.put("pageIndex", pageIndex);
                object.put("text", normalized);
                object.put("sha256", hash);
                stream.write((object.toString() + "\n").getBytes(StandardCharsets.UTF_8));
                inserted++;
            }
        }
        return inserted;
    }

    static synchronized String read(Context context) throws Exception {
        File file = file(context);
        if (!file.exists()) return "（还没有采集记录）";
        StringBuilder output = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) output.append(line).append('\n');
        }
        return output.toString();
    }

    static synchronized void clear(Context context) {
        File file = file(context);
        if (file.exists()) file.delete();
    }

    static synchronized File export(Context context) throws Exception {
        File directory = new File(context.getFilesDir(), "exports");
        if (!directory.exists() && !directory.mkdirs()) throw new IllegalStateException("无法创建导出目录");
        File target = new File(directory, "wechat-visible-text.jsonl");
        try (FileOutputStream out = new FileOutputStream(target)) {
            out.write(read(context).getBytes(StandardCharsets.UTF_8));
        }
        return target;
    }

    private static Set<String> hashes(Context context) throws Exception {
        Set<String> values = new HashSet<>();
        File file = file(context);
        if (!file.exists()) return values;
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                JSONObject object = new JSONObject(line);
                values.add(object.optString("sha256"));
            }
        }
        return values;
    }

    private static String sha256(String value) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder();
        for (byte b : digest) hex.append(String.format("%02x", b));
        return hex.toString();
    }
}
