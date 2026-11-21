package com.studyagent.app;

import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * 闹钟调度。
 *
 * 关键点：用 {@link AlarmManager#setAlarmClock}，它属于「闹钟」类别：
 *   - 精确触发，不受 Doze 与多数厂商省电策略影响；
 *   - 会在状态栏显示闹钟图标，用户可以直观看到「有一个提醒挂着」；
 *   - 是 Android 14 起仍被允许使用全屏通知的少数场景之一。
 *
 * 触发器清单由 JS 计算后整体推入，这里只做「排程 / 取消」。
 */
final class ReminderScheduler {

    static final String EXTRA_ITEM = "sa_item";

    static final String ACTION_FIRE = "com.studyagent.app.action.FIRE";
    static final String ACTION_DONE = "com.studyagent.app.action.DONE";
    static final String ACTION_SNOOZE = "com.studyagent.app.action.SNOOZE";

    static final String ACTION_BOOT = "com.studyagent.app.action.BOOT";
    static final String ACTION_RESYNC = "com.studyagent.app.action.RESYNC";

    private static final String CH_NORMAL = "sa_normal";
    private static final String CH_STRONG_SOUND = "sa_strong_sound";
    private static final String CH_STRONG_VIBRATE = "sa_strong_vibrate";
    private static final String CH_SILENT = "sa_silent";

    private ReminderScheduler() {
    }

    // ---------------------------------------------------------------- 通道

    static void ensureChannels(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }

        NotificationChannel normal = new NotificationChannel(
                CH_NORMAL, "普通提醒", NotificationManager.IMPORTANCE_HIGH);
        normal.setDescription("任务开始前的普通提示");

        NotificationChannel strongSound = new NotificationChannel(
                CH_STRONG_SOUND, "强提醒（响铃）", NotificationManager.IMPORTANCE_HIGH);
        strongSound.setDescription("截止时间临近，响铃并高亮显示");
        strongSound.enableVibration(true);
        strongSound.setVibrationPattern(new long[]{0, 400, 200, 400});
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        strongSound.setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, attrs);

        NotificationChannel strongVibrate = new NotificationChannel(
                CH_STRONG_VIBRATE, "强提醒（仅振动）", NotificationManager.IMPORTANCE_HIGH);
        strongVibrate.enableVibration(true);
        strongVibrate.setVibrationPattern(new long[]{0, 400, 200, 400});
        strongVibrate.setSound(null, null);

        NotificationChannel silent = new NotificationChannel(
                CH_SILENT, "静默提醒", NotificationManager.IMPORTANCE_DEFAULT);
        silent.setSound(null, null);
        silent.enableVibration(false);

        nm.createNotificationChannel(normal);
        nm.createNotificationChannel(strongSound);
        nm.createNotificationChannel(strongVibrate);
        nm.createNotificationChannel(silent);
    }

    static String channelFor(String level, String mode) {
        boolean strong = "strong".equals(level) || "alarm".equals(level);
        if (!strong) {
            return "none".equals(mode) ? CH_SILENT : CH_NORMAL;
        }
        if ("none".equals(mode)) {
            return CH_SILENT;
        }
        return "vibration".equals(mode) ? CH_STRONG_VIBRATE : CH_STRONG_SOUND;
    }

    // ---------------------------------------------------------------- 排程

    /** 旧清单全部取消 → 新清单全部排上。 */
    static void replaceAll(Context ctx, String previousJson, String newJson) {
        cancelAll(ctx, previousJson);
        ReminderStore.saveItems(ctx, newJson);
        scheduleAll(ctx, newJson);
    }

    static void scheduleAll(Context ctx, String itemsJson) {
        ensureChannels(ctx);
        JSONArray items = parse(itemsJson);
        if (items == null) {
            return;
        }
        long now = System.currentTimeMillis();
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) {
                continue;
            }
            long at = item.optLong("triggerAt", 0L);
            if (at <= now) {
                continue; // 已过期的不补发，避免开机后一次性轰炸
            }
            arm(ctx, item, at);
        }
    }

    static void cancelAll(Context ctx, String itemsJson) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) {
            return;
        }
        JSONArray items = parse(itemsJson);
        if (items == null) {
            return;
        }
        for (int i = 0; i < items.length(); i++) {
            JSONObject item = items.optJSONObject(i);
            if (item == null) {
                continue;
            }
            PendingIntent pi = fireIntent(ctx, item, PendingIntent.FLAG_NO_CREATE);
            if (pi != null) {
                am.cancel(pi);
                pi.cancel();
            }
        }
    }

    static void arm(Context ctx, JSONObject item, long at) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) {
            return;
        }
        PendingIntent pi = fireIntent(ctx, item, PendingIntent.FLAG_UPDATE_CURRENT);
        if (pi == null) {
            return;
        }
        try {
            PendingIntent show = PendingIntent.getActivity(
                    ctx, 0, new Intent(ctx, MainActivity.class),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            am.setAlarmClock(new AlarmManager.AlarmClockInfo(at, show), pi);
        } catch (SecurityException e) {
            // 没有精确闹钟权限时退回非精确闹钟，至少不会完全静默
            try {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
            } catch (Exception ignored) {
                // 完全失败时由前端体检条提示用户去授权
            }
        }
    }

    /** 稍后提醒：把同一个条目再排到 now+delay。 */
    static void snooze(Context ctx, JSONObject item, long delayMs) {
        try {
            item.put("triggerAt", System.currentTimeMillis() + delayMs);
        } catch (Exception ignored) {
            return;
        }
        arm(ctx, item, item.optLong("triggerAt", System.currentTimeMillis() + delayMs));
    }

    private static PendingIntent fireIntent(Context ctx, JSONObject item, int flags) {
        Intent intent = new Intent(ctx, ReminderReceiver.class);
        intent.setAction(ACTION_FIRE);
        intent.putExtra(EXTRA_ITEM, item.toString());
        int requestCode = requestCodeFor(item);
        return PendingIntent.getBroadcast(
                ctx, requestCode, intent, flags | PendingIntent.FLAG_IMMUTABLE);
    }

    /** 由 taskId + triggerAt 派生，保证「排程」与「取消」用同一个 requestCode。 */
    private static int requestCodeFor(JSONObject item) {
        String key = item.optString("taskId", "") + "@" + item.optLong("triggerAt", 0L);
        return key.hashCode();
    }

    private static JSONArray parse(String json) {
        if (json == null || json.trim().isEmpty()) {
            return null;
        }
        try {
            return new JSONObject(json).optJSONArray("items");
        } catch (Exception e) {
            return null;
        }
    }
}
