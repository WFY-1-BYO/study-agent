package com.studyagent.app;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;
import android.webkit.JavascriptInterface;

import org.json.JSONObject;

/**
 * 暴露给网页的提醒接口：window.StudyAgentReminder。
 *
 * JS 侧负责「算什么时间提醒」，这里负责「真的排进系统闹钟」。
 * 另外提供权限体检 —— 这是本产品最容易被静默破坏的地方：
 * 通知权限没给、精确闹钟没授权、被厂商省电策略限制，
 * 都会表现为「它就是不响」，所以必须能自查并把用户送到对应的系统开关。
 */
public class ReminderBridge {

    private final Activity activity;

    ReminderBridge(Activity activity) {
        this.activity = activity;
    }

    // ------------------------------------------------------------ 排程

    @JavascriptInterface
    public void syncReminders(String json) {
        try {
            String previous = ReminderStore.loadItems(activity);
            ReminderScheduler.replaceAll(activity, previous, json);
        } catch (Exception ignored) {
            // 排程失败时保留旧清单，不影响界面
        }
    }

    /** 原生侧收到的「完成 / 稍后」事件，JS 启动时取走。 */
    @JavascriptInterface
    public String drainEvents() {
        try {
            return ReminderStore.drainEvents(activity);
        } catch (Exception e) {
            return "[]";
        }
    }

    // ------------------------------------------------------------ 体检

    @JavascriptInterface
    public String checkStatus() {
        JSONObject out = new JSONObject();
        try {
            out.put("sdk", Build.VERSION.SDK_INT);
            out.put("notifications", notificationsEnabled());
            out.put("exactAlarm", exactAlarmAllowed());
            out.put("battery", ignoringBattery());
            out.put("pending", pendingCount());
        } catch (Exception ignored) {
            // 返回空对象也能让前端降级显示
        }
        return out.toString();
    }

    private boolean notificationsEnabled() {
        NotificationManager nm = (NotificationManager) activity.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return nm.areNotificationsEnabled();
        }
        return true;
    }

    private boolean exactAlarmAllowed() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true;
        }
        AlarmManager am = (AlarmManager) activity.getSystemService(Context.ALARM_SERVICE);
        return am != null && am.canScheduleExactAlarms();
    }

    private boolean ignoringBattery() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }
        PowerManager pm = (PowerManager) activity.getSystemService(Context.POWER_SERVICE);
        return pm != null && pm.isIgnoringBatteryOptimizations(activity.getPackageName());
    }

    private int pendingCount() {
        try {
            org.json.JSONArray items = new JSONObject(ReminderStore.loadItems(activity))
                    .optJSONArray("items");
            return items == null ? 0 : items.length();
        } catch (Exception e) {
            return 0;
        }
    }

    // ------------------------------------------------------------ 授权

    @JavascriptInterface
    public void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return;
        }
        activity.runOnUiThread(() -> {
            if (activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(
                        new String[]{android.Manifest.permission.POST_NOTIFICATIONS}, 1001);
            }
        });
    }

    @JavascriptInterface
    public void openNotificationSettings() {
        open(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.getPackageName()));
    }

    @JavascriptInterface
    public void openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            open(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:" + activity.getPackageName())));
        } else {
            openAppSettings();
        }
    }

    @JavascriptInterface
    public void openBatterySettings() {
        try {
            open(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:" + activity.getPackageName())));
        } catch (Exception e) {
            open(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
        }
    }

    @JavascriptInterface
    public void openAppSettings() {
        open(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + activity.getPackageName())));
    }

    /**
     * 国产 ROM 的自启动白名单没有统一入口，只能逐个试；
     * 全部失败时退回应用详情页，至少用户能自己找到「自启动」。
     */
    @JavascriptInterface
    public void openAutostartSettings() {
        String[][] candidates = {
                {"com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"},
                {"com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"},
                {"com.lenovo.security", "com.lenovo.security.purebackground.PureBackgroundActivity"},
                {"com.lenovo.safecenter", "com.lenovo.safecenter.permission.startup.StartupAppListActivity"},
                {"com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"},
                {"com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"},
                {"com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"},
                {"com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"},
        };
        for (String[] c : candidates) {
            try {
                Intent i = new Intent();
                i.setClassName(c[0], c[1]);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                if (activity.getPackageManager().resolveActivity(i, 0) != null) {
                    activity.startActivity(i);
                    return;
                }
            } catch (Exception ignored) {
                // 试下一个
            }
        }
        openAppSettings();
    }

    // ------------------------------------------------------------ 自测

    /** 「测试提醒」：立刻弹一条，确认通道、声音、全屏是否真的可用。 */
    @JavascriptInterface
    public void testNotification(String title) {
        try {
            JSONObject item = new JSONObject();
            item.put("taskId", "sa-test");
            item.put("title", title == null || title.isEmpty() ? "测试提醒" : title);
            item.put("body", "能看到这条，说明通知通道正常。");
            item.put("level", "strong");
            item.put("mode", "sound");
            item.put("fullScreen", false);
            item.put("triggerAt", System.currentTimeMillis());
            Intent i = new Intent(activity, ReminderReceiver.class);
            i.setAction(ReminderScheduler.ACTION_FIRE);
            i.putExtra(ReminderScheduler.EXTRA_ITEM, item.toString());
            activity.sendBroadcast(i);
        } catch (Exception ignored) {
            // 测试失败不抛出到网页
        }
    }

    private void open(Intent intent) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity.startActivity(intent);
        } catch (Exception e) {
            openAppSettings();
        }
    }
}
