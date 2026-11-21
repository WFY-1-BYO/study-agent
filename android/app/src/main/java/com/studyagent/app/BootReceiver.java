package com.studyagent.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * 开机与安装更新后的闹钟重建。
 *
 * Android 的闹钟全部存活在内存里，关机 / 重启 / 应用被覆盖安装后都会消失。
 * 这里在开机完成和应用更新后，按本地保存的清单重新排一遍，
 * 保证「设过的提醒不会因为我关机就悄悄没了」。
 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) {
            return;
        }
        String action = intent.getAction();
        boolean relevant = Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || Intent.ACTION_TIME_CHANGED.equals(action)
                || Intent.ACTION_TIMEZONE_CHANGED.equals(action)
                || ReminderScheduler.ACTION_RESYNC.equals(action);
        if (!relevant) {
            return;
        }
        try {
            ReminderScheduler.ensureChannels(context);
            ReminderScheduler.scheduleAll(context, ReminderStore.loadItems(context));
        } catch (Exception ignored) {
            // 重建失败不应导致开机广播崩溃
        }
    }
}
