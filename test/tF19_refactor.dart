/// F19 · 2.x 重构（P0–P4）交付门禁。
///
/// 不删 / 不放宽 F1–F18 任何断言：本文件只做「新增」——
/// ① 把 tools/refactor_check.mjs 的逐功能 CDP 真实断言纳入全量回归；
/// ② 对交付界面做静态契约断言（持久化、原生交互、双端、AI、基线、导出）。
///
/// 单独运行：dart test/tF19_refactor.dart
library study_agent.tF19_refactor;

import 'dart:convert';
import 'dart:io';

import 'framework.dart';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) throw StateError('缺少交付件 $path');
  return f.readAsStringSync();
}

void runF19(Harness h) {
  h.group('F19 验收① 重构静态契约（新增断言，不改动 F1–F18）', () {
    final html = _read('web/index.html');

    h.test('P0-A 状态真源为 IndexedDB，且每次增删改即时自动保存', () {
      h.contains(html, "indexedDB.open(DB_NAME,DB_VER)");
      h.contains(html, "idbPut('state','main',snap)");
      h.contains(html, 'function scheduleSave(');
      h.contains(html, 'function autoSaveGuard(');
      h.contains(html, 'function save(){scheduleSave();}');
      h.isFalse(html.contains("localStorage.setItem(KEY,JSON.stringify(S))"));
    });

    h.test('P0-A 凭证 AES-GCM 加密隔离，且导出不含 Key', () {
      h.contains(html, "crypto.subtle.encrypt({name:'AES-GCM'");
      h.contains(html, "idbPut('secrets',id,enc)");
      h.contains(html, "const KP='studyagent.v2.key.'");
      h.contains(html, "note:'Key 不在此包内'");
      h.contains(html, "feedback('已导出（已剔除 API Key）','ok')");
    });

    h.test('P0-B 弹层 position:fixed / z-index 10000，高于 Dock', () {
      h.contains(html, 'position:fixed;inset:0;background:rgba(20,24,32,.48)');
      h.contains(html, 'justify-content:center;z-index:10000');
      h.contains(html, 'function openFormPage(');
      h.contains(html, "id=\"formHost\"");
    });

    h.test('P0-C 全局禁用网页默认交互，输入框与笔记区例外', () {
      h.contains(html, 'user-select:none;-webkit-user-select:none;-webkit-touch-callout:none');
      h.contains(html, 'user-select:text;-webkit-user-select:text;-webkit-touch-callout:default');
      h.contains(html, "document.addEventListener('contextmenu'");
      h.contains(html, "document.addEventListener('selectstart'");
    });

    h.test('P1 去套壳、全屏、按窗口宽度自适应三档布局', () {
      h.isFalse(html.contains('id="stage"'));
      h.contains(html, 'height:100dvh');
      h.contains(html, '@media (min-width:600px)');
      h.contains(html, '@media (min-width:1100px)');
      h.contains(html, 'grid-template-columns:minmax(0,210px)');
      h.contains(html, "window.addEventListener('resize',applyResponsive)");
      h.contains(html, "window.addEventListener('orientationchange'");
    });

    h.test('P2-A AI 模型设置子页 + Key 输入框', () {
      h.contains(html, "id=\"btn-open-ai-settings\"");
      h.contains(html, 'function renderAISettings(');
      h.contains(html, "id=\"aiProvSel\"");
      h.contains(html, 'API Key（仅存本机，不进导出包）');
    });

    h.test('P2-B 首启学情基线引导（含跳过 / 稍后）', () {
      h.contains(html, 'function showOnboarding(');
      h.contains(html, "id=\"btn-onboard-save\"");
      h.contains(html, "id=\"btn-onboard-skip\"");
      h.contains(html, 'if(firstBoot&&!S.onboarded)showOnboarding()');
      h.contains(html, "id=\"obBook\"");
    });

    h.test('P3 .studypack 14 实体 + 校验和 + WebDAV 同步接口', () {
      h.contains(html, "'knowledge_base.json':[S.knowledgeBase]");
      h.contains(html, 'function checksum(');
      h.contains(html, "checksum:checksum(entities)");
      h.contains(html, 'function davSync(');
      h.contains(html, "id=\"davUrl\"");
      h.contains(html, "id=\"btn-dav-upload\"");
      h.isFalse(html.contains('buildEntities().api_key'));
    });

    h.test('P4-A 新建规划完整向导：日历式时段 / 自定义时段 / 薄弱点 / 基线', () {
      h.contains(html, 'function wizardCalHtml(');
      h.contains(html, "id=\"wizardCal\"");
      h.contains(html, "id=\"btn-save-custom-slot\"");
      h.contains(html, 'function addWizardWeak(');
      h.contains(html, 'function validatePlanForm(');
      h.contains(html, "id=\"pQuant\"");
      h.contains(html, "id=\"pDays\"");
      h.contains(html, "id=\"pStart\"");
      h.contains(html, "id=\"pBook\"");
      h.contains(html, "class=\"field-err\"");
    });

    h.test('P4-B 薄弱点 / 速查卡 / 会话配置收进规划详情弹层', () {
      h.contains(html, "id=\"btn-edit-cfg\"");
      h.contains(html, 'function savePlanConfig(');
      h.contains(html, "id=\"btn-add-weakpoint\"");
      h.contains(html, "id=\"btn-add-quickcard\"");
      h.contains(html, "id:'today'");
    });

    h.test('APK 内置界面与交付界面逐字节一致', () {
      final a = File('web/index.html').readAsBytesSync();
      final b = File('android/app/src/main/assets/index.html').readAsBytesSync();
      h.eq(a.length, b.length);
      var same = true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) { same = false; break; }
      }
      h.isTrue(same);
    });
  });

  h.group('F19 验收② 逐功能真实交互（CDP）纳入全量门禁', () {
    h.test('node tools/refactor_check.mjs 返回 ALL_GREEN', () {
      final r = Process.runSync('node', <String>['tools/refactor_check.mjs'],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      final out = '${r.stdout}${r.stderr}';
      stdout.writeln(out.split('\n').where((l) =>
          l.startsWith('FAIL') || l.startsWith('结论:') ||
          l.startsWith('断言通过') || l.startsWith('===== 功能组')).join('\n'));
      h.eq(r.exitCode, 0);
      h.isTrue(out.contains('ALL_GREEN 重构验收通过'));
      h.isFalse(out.contains('FAIL  '));
    });
  });
}

void main() {
  final h = Harness();
  runF19(h);
  h.report();
}
