/// F0 · 测试基座与公共工具自检。
/// 单独运行：dart test/tF0_framework.dart
import 'framework.dart';
import '../lib/core.dart';

void runF0(Harness h) {
  h.group('F0 测试基座自检', () {
    h.test('eq 通过', () => h.eq(2 + 2, 4));
    h.test('ok / isTrue / isFalse', () {
      h.ok(true);
      h.isTrue(1 < 2);
      h.isFalse(1 > 2);
    });
    h.test('eq 失败确实被记录为 FAIL（用独立子 Harness 验证，不污染主统计）', () {
      final sub = Harness();
      sub.test('故意失败', () => sub.eq(1, 2));
      h.eq(sub.pass, 0);
      h.eq(sub.failures.length, 1);
      h.isFalse(sub.allPassed);
    });
    h.test('throwsOn 捕获异常', () => h.throwsOn(() => throw StateError('x')));
    h.test('throwsValidation 只认 ValidationError', () {
      h.throwsValidation(() => throw const ValidationError('bad'));
      final sub = Harness();
      sub.test('类型不符应 FAIL', () {
        sub.throwsValidation(() => throw StateError('wrong type'));
      });
      h.eq(sub.failures.length, 1, '类型不符必须判失败');
    });
    h.test('jsonEq 忽略 key 顺序但认值差异', () {
      h.jsonEq({'a': 1, 'b': 2}, {'b': 2, 'a': 1});
      final sub = Harness();
      sub.test('值不同应 FAIL', () => sub.jsonEq({'a': 1}, {'a': 2}));
      h.eq(sub.failures.length, 1);
    });
  });

  h.group('F0 公共工具 core.dart', () {
    h.test('parseHm / formatHm 往返', () {
      h.eq(parseHm('07:30'), 450);
      h.eq(parseHm('00:00'), 0);
      h.eq(parseHm('23:59'), 1439);
      h.eq(formatHm(450), '07:30');
      h.eq(formatHm(0), '00:00');
      h.eq(formatHm(1439), '23:59');
    });
    h.test('非法时间被拒绝', () {
      h.throwsValidation(() => parseHm('7:3'));
      h.throwsValidation(() => parseHm('24:00'));
      h.throwsValidation(() => parseHm('12:60'));
      h.throwsValidation(() => parseHm('abc'));
      h.throwsValidation(() => formatHm(1440));
    });
    h.test('区间重叠判定（半开区间）', () {
      h.isTrue(intervalsOverlap(60, 120, 100, 180));
      h.isFalse(intervalsOverlap(60, 120, 120, 180), '首尾相接不算重叠');
      h.isFalse(intervalsOverlap(60, 120, 0, 60));
      h.isTrue(intervalsOverlap(60, 180, 90, 120), '包含关系算重叠');
    });
    h.test('stableStringify 与 key 顺序无关', () {
      h.eq(stableStringify({'b': 2, 'a': 1}), stableStringify({'a': 1, 'b': 2}));
      h.eq(stableStringify({'a': [1, {'z': 3, 'y': 2}]}),
          stableStringify({'a': [1, {'y': 2, 'z': 3}]}));
    });
    h.test('checksum 稳定且对改动敏感', () {
      final a = checksumHex(stableStringify({'x': 1}));
      final b = checksumHex(stableStringify({'x': 1}));
      final c = checksumHex(stableStringify({'x': 2}));
      h.eq(a, b, '同样内容必须同 checksum');
      h.isFalse(a == c, '内容变化 checksum 必须变');
      h.eq(a.length, 8);
    });
    h.test('makeId / buildAnchorId', () {
      h.eq(makeId('S', 7), 'S-0007');
      h.eq(buildAnchorId('KP2.2', 'S07', 'W03'), 'KP2.2::S07::W03');
    });
    h.test('requireFields 缺字段报错', () {
      h.throwsValidation(
          () => requireFields({'a': 1}, ['a', 'b'], 'Plan'));
      requireFields({'a': 1, 'b': 2}, ['a', 'b'], 'Plan');
    });
  });
}

void main() {
  final h = Harness();
  runF0(h);
  h.report();
}
