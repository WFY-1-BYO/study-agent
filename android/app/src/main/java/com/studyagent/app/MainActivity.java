package com.studyagent.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * 学习助手 App 第一版容器。
 *
 * 界面本体是仓库 web/index.html（随 APK 打进 assets），由 PRD F14 的
 * lib/ui.dart + lib/viewer.dart 生成，三档断点由 WebView 的 CSS 视口驱动。
 * 业务规则真源仍是 lib/ 下的纯 Dart 内核；本容器只负责离线承载界面，
 * 不引入任何网络请求、不申请任何权限、不上传数据。
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
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);

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
