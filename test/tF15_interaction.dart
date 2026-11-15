/// F15 · v2.0.0 交付界面真实交互验收门禁。
///
/// 背景：F0–F14 的纯 Dart 规则函数只验证 lib/ 下的领域逻辑，
/// 没有一条验证「点一下有没有反馈 / AI 能不能调通 / 硬编码是否真的移除」。
/// 本文件把 tools/interaction_check.mjs（CDP 真实点击 / 输入 / 上传 / 勾选 /
/// AI 失败链路 / 无静默操作 / 三档视口）纳入全量回归，并对交付件做静态契约断言。
///
/// 单独运行：dart test/tF15_interaction.dart
import 'dart:io';

import 'framework.dart';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    throw StateError('缺少交付件 $path（cwd=${Directory.current.path}）');
  }
  return f.readAsStringSync();
}

void runF15(Harness h) {
  // -------------------------------------------------------------- 验收① 去硬编码 + 可交互骨架
  h.group('F15 验收① 去硬编码基线 + 可交互骨架（非静态说明页）', () {
    final html = _read('web/index.html');

    h.test('全局反馈条 + toast（每个操作都有出口）', () {
      h.contains(html, 'id="feedback"');
      h.contains(html, "function feedback(");
      h.contains(html, "classList.add('show')");
    });

    h.test('手机底栏 / 平板顶栏双形态切换', () {
      h.contains(html, 'function setDevice(');
      h.contains(html, 'id="dev-phone"');
      h.contains(html, 'id="dev-pad"');
      h.contains(html, "document.querySelector('.nav-top').style.display");
      h.contains(html, "document.querySelector('.nav-bottom').style.display");
    });

    h.test('5 个导航 tab（今日/规划/日历/知识库/我的）', () {
      h.contains(html, "const NAV=[");
      h.contains(html, "id:'today'");
      h.contains(html, "id:'plan'");
      h.contains(html, "id:'calendar'");
      h.contains(html, "id:'kb'");
      h.contains(html, "id:'mine'");
    });

    h.test('默认学情基线为空（地区/学校/教材均未预置）', () {
      h.contains(html, "profile:{region:''");
      h.contains(html, "blank:{region:''");
    });

    h.test('知识库作为收纳实体进入导出包（14 实体之一）', () {
      h.contains(html, "'knowledge_base.json':[S.knowledgeBase]");
    });

    h.test('多格式上传 + 截图分析入口齐备', () {
      h.contains(html, 'function handleFiles(');
      h.contains(html, 'function handleShots(');
      h.contains(html, "id=\"fileIn\"");
      h.contains(html, "id=\"shotIn\"");
      h.contains(html,
          'accept=".pdf,.doc,.docx,.xlsx,.pptx,.txt,.md,.png,.jpg,.jpeg"');
      h.contains(html, 'function analyzeShot(');
      h.contains(html, 'function fileToDataUrl(');
    });
  });

  // -------------------------------------------------------------- 验收② 多模型 AI 真实接入，失败不伪造
  h.group('F15 验收② 多模型 AI 通道真实接入，失败不伪造', () {
    final html = _read('web/index.html');

    h.test('内置 9 个可插拔 Provider 预设（无硬编码单一模型）', () {
      h.contains(html, 'const PROVIDER_PRESETS={');
      for (final p in <String>[
        'deepseek', 'openai', 'claude', 'qwen', 'kimi',
        'doubao', 'glm', 'gemini', 'ollama'
      ]) {
        h.contains(html, '$p:{', '缺预设 $p');
      }
      h.contains(html, "activeProvider:'deepseek'");
    });

    h.test('原生桥接 / 浏览器直连双通道契约与 v0.2.0 一致', () {
      h.contains(html, 'window.StudyAgentNative.callAi');
      h.contains(html, 'JSON.stringify(payload),cb');
      h.contains(html, 'window.__saAiResult=function');
      h.contains(html, "/chat/completions");
      h.contains(html, "'Authorization':'Bearer '+cfg.key");
    });

    h.test('未配置时明确失败（不伪造回复）', () {
      h.contains(html, '未填写 API Key（我的→AI 设置）');
      h.contains(html, '未配置 Base URL（我的→AI 设置）');
      h.contains(html, "function aiRequest(");
    });

    h.test('API Key 按 Provider 单独存本机，绝不进 state / 导出包', () {
      h.contains(html, "const KP='studyagent.v2.key.'");
      h.contains(html, "localStorage.getItem(KP+S.activeProvider)");
      h.contains(html, 'localStorage.setItem(KP+id,k)');
      h.contains(html, "note:'Key 不在此包内'");
      h.contains(html, "feedback('已导出（已剔除 API Key）','ok')");
    });
  });

  // -------------------------------------------------------------- 验收③ Android 原生 AI 桥接与联网权限
  h.group('F15 验收③ Android 原生 AI 桥接与联网权限', () {
    final bridge = _read(
        'android/app/src/main/java/com/studyagent/app/AiBridge.java');
    final activity = _read(
        'android/app/src/main/java/com/studyagent/app/MainActivity.java');
    final manifest = _read('android/app/src/main/AndroidManifest.xml');

    h.test('AiBridge 用 HttpURLConnection 真实 POST 并回调 JS', () {
      h.contains(bridge, '@JavascriptInterface');
      h.contains(bridge, 'HttpURLConnection');
      h.contains(bridge, 'setRequestProperty("Authorization", "Bearer " + key)');
      h.contains(bridge, 'window.__saAiResult');
      h.contains(bridge, 'evaluateJavascript');
    });

    h.test('失败如实回传，不伪造回复', () {
      h.contains(bridge, '"ok", false');
      h.contains(bridge, '"error"');
      h.contains(bridge, 'clip(text, 300)');
      h.isFalse(bridge.contains('模拟回复'));
    });

    h.test('Key 不落盘、不写日志、不进包', () {
      h.isFalse(bridge.contains('Log.'));
      h.isFalse(bridge.contains('openFileOutput'));
      h.isFalse(bridge.contains('SharedPreferences'));
    });

    h.test('MainActivity 注册 StudyAgentNative', () {
      h.contains(activity,
          'addJavascriptInterface(new AiBridge(webView), "StudyAgentNative")');
    });

    h.test('Manifest 仅申请 INTERNET（AI 请求用），无其它权限', () {
      h.contains(manifest, 'android.permission.INTERNET');
      h.isFalse(manifest.contains('READ_CONTACTS'));
      h.isFalse(manifest.contains('ACCESS_FINE_LOCATION'));
      h.isFalse(manifest.contains('READ_SMS'));
    });

    h.test('APK 内置界面与交付界面逐字节一致', () {
      final a = File('web/index.html').readAsBytesSync();
      final b =
          File('android/app/src/main/assets/index.html').readAsBytesSync();
      h.eq(a.length, b.length);
      var same = true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          same = false;
          break;
        }
      }
      h.isTrue(same);
    });
  });

  // -------------------------------------------------------------- 验收④ 旧规格基准页未被删除（不降低旧断言）
  h.group('F15 验收④ 旧规格基准页未被删除（不降低旧断言）', () {
    h.test('web/spec.html 保留 F14 静态规格页', () {
      final s = _read('web/spec.html');
      h.contains(s, '基本不等式');
      h.contains(s, 'studypack');
      h.contains(s, 'id="page-today"');
    });

    h.test('生成脚本改为输出 spec.html，不覆盖交付界面', () {
      final g = _read('tools/gen_viewer.dart');
      h.contains(g, "File('web/spec.html')");
      h.isFalse(g.contains("File('web/index.html')"));
    });
  });

  // -------------------------------------------------------------- 验收⑤ 真实点击验收纳入全量门禁（CDP 实测）
  h.group('F15 验收⑤ 真实点击验收纳入全量门禁（CDP 实测）', () {
    h.test('node tools/interaction_check.mjs 返回 ALL_GREEN', () {
      final r = Process.runSync('node', <String>['tools/interaction_check.mjs']);
      final out = '${r.stdout}${r.stderr}';
      stdout.writeln(out
          .split('\n')
          .where((l) =>
              l.startsWith('FAIL') ||
              l.startsWith('结论:') ||
              l.startsWith('断言通过') ||
              l.startsWith('INFO  DeepSeek'))
          .join('\n'));
      h.eq(r.exitCode, 0);
      h.isTrue(out.contains('ALL_GREEN 真实交互验收通过'));
      h.isFalse(out.contains('FAIL  '));
      h.isTrue(File('docs/交互验收报告.md').existsSync());
    });
  });
}

void main() {
  final h = Harness();
  runF15(h);
  h.report();
}
