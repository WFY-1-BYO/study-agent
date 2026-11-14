/// 零依赖测试基座。
///
/// 设计目标：每个功能一个 tFxx_*.dart，既能 `dart test/tFxx_x.dart` 单独跑，
/// 也能被 run_all.dart 自动发现并汇总。断言失败一律记录并计入 FAIL，
/// 主进程以非零退出码结束 —— 不允许「看起来跑过了」。
library study_agent.test_framework;

import 'dart:convert';
import 'dart:io';

import '../lib/core.dart' show stableStringify, ValidationError;

class Harness {
  /// quiet=true 用于「验证失败确会被记录」的子 Harness，
  /// 避免故意的 FAIL 行污染真实测试输出。
  final bool quiet;
  Harness({this.quiet = false});

  int pass = 0;
  final List<String> failures = <String>[];
  String _group = '';

  bool get allPassed => failures.isEmpty;

  void group(String name, void Function() body) {
    final prev = _group;
    _group = prev.isEmpty ? name : '$prev / $name';
    if (!quiet) stdout.writeln('\n[$_group]');
    try {
      body();
    } finally {
      _group = prev;
    }
  }

  void test(String name, void Function() body) {
    try {
      body();
      pass++;
      if (!quiet) stdout.writeln('  PASS  $name');
    } catch (e) {
      failures.add('$_group / $name :: $e');
      if (!quiet) stdout.writeln('  FAIL  $name :: $e');
    }
  }

  void eq(Object? actual, Object? expected, [String msg = '']) {
    if (actual != expected) {
      throw StateError('${msg.isEmpty ? '' : '[$msg] '}'
          'expected=<$expected> actual=<$actual>');
    }
  }

  void ok(bool value, [String msg = '']) {
    if (!value) throw StateError(msg.isEmpty ? '断言失败' : msg);
  }

  void isTrue(bool v, [String m = '']) => ok(v, m.isEmpty ? '期望 true' : m);

  void isFalse(bool v, [String m = '']) => ok(!v, m.isEmpty ? '期望 false' : m);

  void notNull(Object? v, [String m = '']) =>
      ok(v != null, m.isEmpty ? '期望非 null' : m);

  void isNull(Object? v, [String m = '']) =>
      ok(v == null, m.isEmpty ? '期望 null' : m);

  /// 断言 f 抛出任意异常。
  void throwsOn(void Function() f, [String m = '']) {
    var thrown = false;
    try {
      f();
    } catch (_) {
      thrown = true;
    }
    if (!thrown) {
      throw StateError('${m.isEmpty ? '' : '[$m] '}期望抛出异常，但正常返回');
    }
  }

  /// 断言 f 抛出 ValidationError（硬约束校验失败必须用它）。
  void throwsValidation(void Function() f, [String m = '']) {
    Object? caught;
    try {
      f();
    } catch (e) {
      caught = e;
    }
    if (caught == null) {
      throw StateError('${m.isEmpty ? '' : '[$m] '}期望 ValidationError，但正常返回');
    }
    if (caught is! ValidationError) {
      throw StateError('${m.isEmpty ? '' : '[$m] '}'
          '期望 ValidationError，实际 ${caught.runtimeType}: $caught');
    }
  }

  /// 深度 JSON 相等。
  void jsonEq(Object? a, Object? b, [String m = '']) {
    if (stableStringify(a) != stableStringify(b)) {
      throw StateError('${m.isEmpty ? '' : '[$m] '}'
          'JSON 不一致\n  A=${jsonEncode(a)}\n  B=${jsonEncode(b)}');
    }
  }

  void contains(String haystack, String needle, [String m = '']) => ok(
      haystack.contains(needle),
      m.isEmpty ? '字符串未包含 "$needle"' : m);

  String get summary =>
      'TOTAL pass=$pass fail=${failures.length} ${allPassed ? 'ALL_GREEN' : 'HAS_FAILURE'}';

  /// 打印统计；有失败则非零退出。
  void report() {
    stdout.writeln('\n$summary');
    if (!allPassed) {
      for (final f in failures) {
        stdout.writeln('  - $f');
      }
      exit(1);
    }
  }
}
