package com.studyagent.app;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * 提醒触发与通知按钮处理。
 *
 * 「不点不消失」由三件事共同保证：
 *   1) 通知 setOngoing(true) —— 用户无法左右滑动清除；
 *   2) setFullScreenIntent —— 亮屏并直接弹出处理页（系统允许时）；
 *   3) 两个明确出口按钮 —— 完成 / 稍后 10 分钟，不点就一直挂着。
 */
public class ReminderReceiver extends BroadcastReceiver {

    private static final long SNOOZE_MS = 10L * 60L * 1000L;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            return;
        }
        String action = intent.getAction();
        String raw = intent.getStringExtra(ReminderScheduler.EXTRA_ITEM);
        if (raw == null) {
            return;
        }

        JSONObject item;
        try {
            item = new JSONObject(raw);
        } catch (Exception e) {
            return;
        }

        if (ReminderScheduler.ACTION_DONE.equals(action)) {
            onDone(context, item);
        } else if (ReminderScheduler.ACTION_SNOOZE.equals(action)) {
            onSnooze(context, item);
        } else {
            show(context, item);
        }
    }

    // ------------------------------------------------------------ 通知

    private static void show(Context context, JSONObject item) {
        ReminderScheduler.ensureChannels(context);

        String title = item.optString("title", "该做这件事了");
        String body = item.optString("body", "");
        String level = item.optString("level", "normal");
        String mode = item.optString("mode", "sound");
        String taskId = item.optString("taskId", "");
        boolean strong = "strong".equals(level) || "alarm".equals(level);
        boolean fullScreen = item.optBoolean("fullScreen", false);

        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return;
        }

        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(
                    context, ReminderScheduler.channelFor(level, mode));
        } else {
            builder = new Notification.Builder(context);
            builder.setPriority(strong ? Notification.PRIORITY_MAX : Notification.PRIORITY_HIGH);
        }

        builder.setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new Notification.BigTextStyle().bigText(body))
                .setAutoCancel(false)
                .setOngoing(strong)
                .setOnlyAlertOnce(false)
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true);

        PendingIntent openApp = PendingIntent.getActivity(
                context, taskId.hashCode(),
                new Intent(context, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        builder.setContentIntent(openApp);

        if (strong && fullScreen) {
            PendingIntent full = PendingIntent.getActivity(
                    context, taskId.hashCode() ^ 0x2C2C,
                    buildReminderActivityIntent(context, item),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            builder.setFullScreenIntent(full, true);
        }

        builder.addAction(action(context, item, ReminderScheduler.ACTION_DONE, "已完成", 0x11, 1));
        builder.addAction(action(context, item, ReminderScheduler.ACTION_SNOOZE, "稍后 10 分钟", 0x22, 2));

        Notification notification = builder.build();
        notification.flags |= Notification.FLAG_NO_CLEAR;

        try {
            nm.notify(notificationId(taskId), notification);
        } catch (SecurityException ignored) {
            // 没有通知权限：不崩溃，由前端体检条提示用户授权
        }
    }

    static Intent buildReminderActivityIntent(Context context, JSONObject item) {
        Intent i = new Intent(context, ReminderActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        i.putExtra(ReminderActivity.EXTRA_TITLE, item.optString("title", "该做这件事了"));
        i.putExtra(ReminderActivity.EXTRA_BODY, item.optString("body", ""));
        i.putExtra(ReminderScheduler.EXTRA_ITEM, item.toString());
        return i;
    }

    private static Notification.Action action(Context context, JSONObject item,
                                              String actionName, String label, int salt, int order) {
        Intent i = new Intent(context, ReminderReceiver.class);
        i.setAction(actionName);
        i.putExtra(ReminderScheduler.EXTRA_ITEM, item.toString());
        int requestCode = item.optString("taskId", "").hashCode() ^ salt;
        PendingIntent pi = PendingIntent.getBroadcast(
                context, requestCode, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Action.Builder(
                android.R.drawable.ic_menu_send, label, pi).build();
    }

    private static int notificationId(String taskId) {
        return taskId == null ? 0 : taskId.hashCode();
    }

    // ------------------------------------------------------------ 按钮

    private static void onDone(Context context, JSONObject item) {
        String taskId = item.optString("taskId", "");
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(notificationId(taskId));
        }
        cancelRemainingForTask(context, taskId);
        ReminderStore.pushEvent(context, event("done", taskId));
    }

    private static void onSnooze(Context context, JSONObject item) {
        String taskId = item.optString("taskId", "");
        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) {
            nm.cancel(notificationId(taskId));
        }
        ReminderScheduler.snooze(context, item, SNOOZE_MS);
        ReminderStore.pushEvent(context, event("snooze", taskId));
    }

    private static String event(String type, String taskId) {
        try {
            JSONObject e = new JSONObject();
            e.put("type", type);
            e.put("taskId", taskId);
            e.put("at", System.currentTimeMillis());
            return e.toString();
        } catch (Exception ex) {
            return "{\"type\":\"unknown\"}";
        }
    }

    /** 任务被标记完成后，把它后续还没触发的提醒一并取消。 */
    private static void cancelRemainingForTask(Context context, String taskId) {
        try {
            JSONArray items = new JSONObject(ReminderStore.loadItems(context))
                    .optJSONArray("items");
            if (items == null) {
                return;
            }
            long now = System.currentTimeMillis();
            for (int i = 0; i < items.length(); i++) {
                JSONObject it = items.optJSONObject(i);
                if (it == null || !taskId.equals(it.optString("taskId", ""))) {
                    continue;
                }
                if (it.optLong("triggerAt", 0L) <= now) {
                    continue;
                }
                JSONObject key = new JSONObject();
                key.put("taskId", taskId);
                key.put("triggerAt", it.optLong("triggerAt", 0L));
                ReminderScheduler.cancelAll(context, "{\"items\":[" + key.toString() + "]}");
            }
        } catch (Exception ignored) {
            // 取消失败不影响已弹出的通知
        }
    }
}
