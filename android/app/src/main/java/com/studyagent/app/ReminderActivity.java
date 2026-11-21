package com.studyagent.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

/**
 * 强提醒的全屏处理页。
 *
 * 只提供三个出口：开始（回 App）、稍后 10 分钟、已完成。
 * 不提供「返回」——避免用户误触后提醒彻底消失。
 */
public class ReminderActivity extends Activity {

    static final String EXTRA_TITLE = "sa_title";
    static final String EXTRA_BODY = "sa_body";

    private String itemJson = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        Intent intent = getIntent();
        String title = intent.getStringExtra(EXTRA_TITLE);
        String body = intent.getStringExtra(EXTRA_BODY);
        itemJson = intent.getStringExtra(ReminderScheduler.EXTRA_ITEM);
        if (title == null) {
            title = "该做这件事了";
        }
        if (body == null) {
            body = "";
        }

        setContentView(buildView(title, body));
    }

    private View buildView(String title, String body) {
        int pad = dp(28);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_VERTICAL);
        root.setPadding(pad, pad, pad, pad);

        GradientDrawable bg = new GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{Color.parseColor("#FFFDF8"), Color.parseColor("#EAF0F7")});
        root.setBackground(bg);

        TextView label = new TextView(this);
        label.setText("现在该做");
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        label.setTextColor(Color.parseColor("#6B7280"));
        root.addView(label);

        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 30);
        t.setTextColor(Color.parseColor("#1F242B"));
        t.setPadding(0, dp(10), 0, dp(10));
        root.addView(t);

        if (!body.isEmpty()) {
            TextView b = new TextView(this);
            b.setText(body);
            b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
            b.setTextColor(Color.parseColor("#4B5563"));
            b.setPadding(0, 0, 0, dp(28));
            root.addView(b);
        }

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.VERTICAL);
        buttons.setPadding(0, dp(16), 0, 0);

        buttons.addView(primary("开始", Color.parseColor("#1B4F8A"), Color.WHITE, view -> {
            startActivity(new Intent(this, MainActivity.class));
            finish();
        }));
        buttons.addView(ghost("稍后 10 分钟", view -> {
            sendAction(ReminderScheduler.ACTION_SNOOZE);
            finish();
        }));
        buttons.addView(ghost("已完成", view -> {
            sendAction(ReminderScheduler.ACTION_DONE);
            finish();
        }));

        root.addView(buttons);
        return root;
    }

    private void sendAction(String action) {
        try {
            Intent i = new Intent(this, ReminderReceiver.class);
            i.setAction(action);
            i.putExtra(ReminderScheduler.EXTRA_ITEM, itemJson);
            sendBroadcast(i);
        } catch (Exception ignored) {
            // 广播失败时至少让页面关闭，不让用户卡在这里
        }
    }

    private Button primary(String text, int bgColor, int fgColor, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        b.setTextColor(fgColor);
        GradientDrawable d = new GradientDrawable();
        d.setColor(bgColor);
        d.setCornerRadius(dp(14));
        b.setBackground(d);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(56));
        lp.bottomMargin = dp(12);
        b.setLayoutParams(lp);
        b.setOnClickListener(l);
        return b;
    }

    private Button ghost(String text, View.OnClickListener l) {
        Button b = new Button(this);
        b.setText(text);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTextColor(Color.parseColor("#1B4F8A"));
        GradientDrawable d = new GradientDrawable();
        d.setColor(Color.TRANSPARENT);
        d.setStroke(dp(1), Color.parseColor("#C7D2E0"));
        d.setCornerRadius(dp(14));
        b.setBackground(d);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(52));
        lp.bottomMargin = dp(10);
        b.setLayoutParams(lp);
        b.setOnClickListener(l);
        return b;
    }

    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    /** 处理页不允许用返回键草草消失。 */
    @Override
    public void onBackPressed() {
        // 故意留空：必须明确选择「稍后」或「已完成」
    }

    static Intent intentFor(Context context, JSONObject item) {
        return ReminderReceiver.buildReminderActivityIntent(context, item);
    }
}
