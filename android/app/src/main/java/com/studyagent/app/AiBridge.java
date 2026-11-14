package com.studyagent.app;

import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;

/**
 * AI 原生桥接：WebView 内的界面通过 window.StudyAgentNative.callAi 发起请求，
 * 由本类用 HttpURLConnection 真实调用 OpenAI 兼容接口（默认 DeepSeek），
 * 再把结果回调到 window.__saAiResult(cbId, json)。
 *
 * 目的：绕开 file:// 页面直连 API 的跨域（CORS）限制。
 * 安全：API Key 只从 JS 侧参数传入，不写入文件、不进日志、不落盘、不进包。
 *       失败一律如实回传，绝不伪造 AI 回复。
 */
public class AiBridge {

    private final WebView webView;

    AiBridge(WebView webView) {
        this.webView = webView;
    }

    @JavascriptInterface
    public void callAi(final String payloadJson, final String cbId) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                String result = request(payloadJson);
                final String js =
                        "window.__saAiResult(" + JSONObject.quote(cbId)
                                + "," + JSONObject.quote(result) + ")";
                webView.post(new Runnable() {
                    @Override
                    public void run() {
                        webView.evaluateJavascript(js, null);
                    }
                });
            }
        }, "study-agent-ai").start();
    }

    private String request(String payloadJson) {
        HttpURLConnection conn = null;
        try {
            JSONObject payload = new JSONObject(payloadJson);
            String baseUrl = payload.optString("baseUrl", "https://api.deepseek.com");
            String model = payload.optString("model", "deepseek-chat");
            String key = payload.optString("key", "");
            JSONArray messages = payload.optJSONArray("messages");
            if (messages == null) messages = new JSONArray();

            if (key.isEmpty()) {
                return fail("", "未填写 API Key（设置页）");
            }

            JSONObject body = new JSONObject();
            body.put("model", model);
            body.put("messages", messages);
            body.put("stream", false);

            URL url = new URL(baseUrl.replaceAll("/+$", "") + "/chat/completions");
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(25000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("Authorization", "Bearer " + key);
            conn.setRequestProperty("Accept", "application/json");

            OutputStream os = conn.getOutputStream();
            os.write(body.toString().getBytes(StandardCharsets.UTF_8));
            os.flush();
            os.close();

            int code = conn.getResponseCode();
            InputStream is = code >= 200 && code < 300
                    ? conn.getInputStream() : conn.getErrorStream();
            String text = readAll(is);
            if (is != null) is.close();

            if (code < 200 || code >= 300) {
                return fail(String.valueOf(code),
                        "HTTP " + code + " · " + clip(text, 300));
            }

            JSONObject resp = new JSONObject(text);
            JSONArray choices = resp.optJSONArray("choices");
            String content = "";
            if (choices != null && choices.length() > 0) {
                JSONObject c0 = choices.optJSONObject(0);
                if (c0 != null) {
                    JSONObject msg = c0.optJSONObject("message");
                    if (msg != null) content = msg.optString("content", "");
                }
            }
            JSONObject out = new JSONObject();
            out.put("ok", true);
            out.put("http", code);
            out.put("content", content.isEmpty() ? "(空回复)" : content);
            return out.toString();

        } catch (Exception e) {
            return fail("", e.getClass().getSimpleName() + "：" + clip(e.getMessage(), 300));
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private static String readAll(InputStream is) throws Exception {
        if (is == null) return "";
        BufferedReader br = new BufferedReader(
                new InputStreamReader(is, StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = br.readLine()) != null) sb.append(line).append('\n');
        br.close();
        return sb.toString();
    }

    private static String clip(String s, int n) {
        if (s == null) return "";
        s = s.replaceAll("\\s+", " ").trim();
        return s.length() > n ? s.substring(0, n) + "…" : s;
    }

    private static String fail(String http, String error) {
        try {
            JSONObject out = new JSONObject();
            out.put("ok", false);
            if (!http.isEmpty()) out.put("http", Integer.parseInt(http));
            out.put("error", error);
            return out.toString();
        } catch (Exception e) {
            return "{\"ok\":false,\"error\":\"结果封装失败\"}";
        }
    }
}
