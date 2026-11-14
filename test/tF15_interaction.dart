/// F15 · 交付界面真实交互验收门禁。
///
/// 背景：F0–F14 的 436 用例测的是 lib/ 下的纯 Dart 规则函数，
/// 没有一条验证「点一下有没有反馈 / AI 能不能调通」。
/// 本文件把 tools/interaction_check.mjs（CDP 真实点击 / 输入 / 勾选 /
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
  h.group('F15 验收① 交付界面必须是可交互 App，不是静态说明页', () {
    final html = _read('web/index.html');

    h.test('存在全局反馈条与 toast（每个操作都有出口）', () {
      h.contains(html, 'id="statusbar"');
      h.contains(html, 'id="toast"');
      h.contains(html, 'function feedback(');
      h.contains(html, 'function fail(');
    });

    h.test('中央事件委托：所有 data-action 都走同一反馈出口', () {
      h.contains(html, "document.addEventListener('click'");
      h.contains(html, "closest('[data-action]')");
      h.contains(html, 'var HANDLERS=');
      h.isTrue('data-action='.allMatches(html).length >= 25);
    });

    h.test('11 类页面可切换、当前页被记住', () {
      h.contains(html, 'function showPage(');
      h.contains(html, "section[data-page].active");
      h.contains(html, 'S.page=id;save()');
    });

    h.test('状态与倒计时真实运行并落本机', () {
      h.contains(html, 'localStorage.setItem');
      h.contains(html, 'setInterval(tick,1000)');
      h.contains(html, "data-tick");
      h.contains(html, 'function tick(');
    });

    h.test('真实业务动作齐全（任务 / 规划 / 会话 / 复习 / 笔记 / L0 / 导出）', () {
      for (final a in <String>[
        'openHabit', 'createPlan', 'skipPretest', 'submitQuiz', 'stageNext',
        'reviewNext', 'saveMyNote', 'linkNotes', 'prefLead5', 'tryChangeReview',
        'exportPack', 'clearAll',
      ]) {
        h.contains(html, a, '缺动作 $a');
      }
    });

    h.test('双层 75% 与固定复习模式 2 仍在界面规则里', () {
      h.contains(html, 'v>=75');
      h.contains(html, '固定模式 2');
      h.contains(html, '不可配置');
    });

    h.test('绿色只表示可学习时段；达标用墨蓝 + 文字', () {
      h.contains(html, '绿色只表示可学习空闲时段');
      h.contains(html, '✓ 已达标');
      h.contains(html, '--pine:#2E7D5B');
    });

    h.test('打印态含非颜色标记（▲ / 描边 / 文字标签）', () {
      h.contains(html, '@media print');
      h.contains(html, 'border:2px dashed #000');
      h.contains(html, '▲ 描边 · 文字标签');
    });
  });

  h.group('F15 验收② AI 通道真实接入，失败不伪造', () {
    final html = _read('web/index.html');

    h.test('页面提供可配置 Provider 与 Key 输入（Key 只存本机）', () {
      h.contains(html, 'id="aiBase"');
      h.contains(html, 'id="aiModel"');
      h.contains(html, 'id="aiKey"');
      h.contains(html, 'api.deepseek.com');
      h.contains(html, 'type="password"');
      h.contains(html, "localStorage.getItem(AIKEY)");
    });

    h.test('原生桥接 / 浏览器直连双通道 + 回调入口', () {
      h.contains(html, 'StudyAgentNative');
      h.contains(html, 'window.__saAiResult');
      h.contains(html, '/chat/completions');
      h.contains(html, "'Authorization':'Bearer '");
    });

    h.test('请求中 → 成功/失败两态反馈，失败明确标注不编造内容', () {
      h.contains(html, '请求中…');
      h.contains(html, '未获得 AI 回复');
      h.contains(html, '不会编造内容');
      h.contains(html, 'function aiRun(');
    });

    h.test('AI 能力落到三个真实调用点', () {
      h.contains(html, 'aiResources');
      h.contains(html, 'aiCorrect');
      h.contains(html, 'aiNote');
      h.contains(html, 'testAi');
    });

    h.test('API Key 不进导出包', () {
      h.contains(html, 'function buildPack(');
      h.contains(html, 'Key 不在包内');
      h.isFalse(html.contains('S.aiKey'));
    });
  });

  h.group('F15 验收③ Android 原生 AI 桥接与联网权限', () {
    final bridge = _read('android/app/src/main/java/com/studyagent/app/AiBridge.java');
    final activity =
        _read('android/app/src/main/java/com/studyagent/app/MainActivity.java');
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
      final b = File('android/app/src/main/assets/index.html').readAsBytesSync();
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

  h.group('F15 验收④ 旧规格基准页未被删除（不降低旧断言）', () {
    h.test('web/spec.html 保留 F14 静态规格页', () {
      final s = _read('web/spec.html');
      h.contains(s, '基本不等式');
      h.contains(s, '.studypack');
      h.contains(s, 'id="page-today"');
    });

    h.test('生成脚本改为输出 spec.html，不覆盖交付界面', () {
      final g = _read('tools/gen_viewer.dart');
      h.contains(g, "File('web/spec.html')");
      h.isFalse(g.contains("File('web/index.html')"));
    });
  });

  h.group('F15 验收⑤ 真实点击验收纳入全量门禁（CDP 实测）', () {
    h.test('node tools/interaction_check.mjs 返回 ALL_GREEN', () {
      final r = Process.runSync('node', <String>['tools/interaction_check.mjs']);
      final out = '${r.stdout}${r.stderr}';
      // 把关键结果留在测试日志里，便于追溯
      stdout.writeln(out.split('\n').where((l) =>
          l.startsWith('FAIL') ||
          l.startsWith('结论:') ||
          l.startsWith('断言通过') ||
          l.startsWith('INFO  DeepSeek')).join('\n'));
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
