package com.studyagent.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * 学习助手 App 容器。
 *
 * 界面本体是仓库 web/index.html（随 APK 打进 assets），三档断点由 WebView 的
 * CSS 视口驱动；所有交互（任务 / 规划 / 会话 / 笔记 / L0）都在页面内真实可用，
 * 每个操作都写全局反馈条。
 *
 * AI 能力通过 AiBridge 原生桥接：页面调用 window.StudyAgentNative.callAi，
 * 由本进程用 HttpURLConnection 真实请求 OpenAI 兼容接口，再回调 JS。
 * 这样绕开 file:// 页面直连 API 的跨域限制；API Key 只由用户在设置页填写并
 * 存于本机 WebView localStorage，不写入本容器、不落盘、不进包、不进导出。
 *
 * 除 AI 请求外不联网；不上报任何数据；不申请定位 / 通讯录 / 存储等权限。
 */
public class MainActivity extends Activity {

    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        // v2.1.0：业务数据以 IndexedDB 为真源，显式开启 WebView 本地数据库能力。
        settings.setDatabaseEnabled(true);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);

        // 注册 AI 原生通道；页面内 window.StudyAgentNative 即指向该对象。
        webView.addJavascriptInterface(new AiBridge(webView), "StudyAgentNative");

        webView.setWebViewClient(new WebViewClient());
        webView.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
