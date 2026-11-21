package com.studyagent.app;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * 提醒数据的本地落盘。
 *
 * 设计：业务规则（什么时候该提醒）全部由 JS 计算，原生只负责「按时间点触发」。
 * JS 每次变更后把完整的触发清单推过来，这里原样保存，用于：
 *   1) 开机后重建闹钟（BootReceiver）
 *   2) 取消旧闹钟（改时间 / 删除任务）
 *   3) 记录「完成 / 稍后」事件，等下次打开 App 交给 JS 处理
 *
 * 不保存任何凭证；清单里只有任务标题与时间。
 */
final class ReminderStore {

    private static final String PREFS = "studyagent_reminders";
    private static final String KEY_ITEMS = "items";
    private static final String KEY_EVENTS = "events";
    private static final String EMPTY_ITEMS = "{\"items\":[]}";

    private ReminderStore() {
    }

    static SharedPreferences prefs(Context ctx) {
        return ctx.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static void saveItems(Context ctx, String json) {
        if (json == null || json.trim().isEmpty()) {
            return;
        }
        prefs(ctx).edit().putString(KEY_ITEMS, json).apply();
    }

    static String loadItems(Context ctx) {
        return prefs(ctx).getString(KEY_ITEMS, EMPTY_ITEMS);
    }

    /** 原生侧产生的事件（用户在通知栏点了「完成 / 稍后」），排队等 JS 取走。 */
    static void pushEvent(Context ctx, String eventJson) {
        try {
            String raw = prefs(ctx).getString(KEY_EVENTS, "[]");
            org.json.JSONArray arr = new org.json.JSONArray(raw);
            arr.put(new org.json.JSONObject(eventJson));
            prefs(ctx).edit().putString(KEY_EVENTS, arr.toString()).apply();
        } catch (Exception ignored) {
            // 事件丢失不应影响提醒本身
        }
    }

    /** 取走并清空事件队列。 */
    static String drainEvents(Context ctx) {
        String raw = prefs(ctx).getString(KEY_EVENTS, "[]");
        prefs(ctx).edit().putString(KEY_EVENTS, "[]").apply();
        return raw;
    }
}
