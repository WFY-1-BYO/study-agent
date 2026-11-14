/// F9 · 三维归因与考前速查卡测试（PRD §4 F9 逐条验收）。
/// 单独运行：dart test/tF9_weakpoint.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/weakpoint.dart';

const leaf = 'RJ-A-BX1-CH2-2.2-EQ';
const branch = 'RJ-A-BX1-CH2-2.2';

AttributionInput _input({
  String node = leaf,
  String knowledge = 'condition',
  String gaokao = 'deRoutine',
  String feynman = 'fakeUnderstanding',
  List<String>? evidence,
  int occurrences = 1,
  int distinctSessions = 1,
  String? freeform,
}) =>
    AttributionInput(
      knowledgeNodeId: node,
      axisKnowledge: knowledge,
      axisGaokao: gaokao,
      axisFeynman: feynman,
      evidence: evidence ?? ['第 3 题', '复述原句：凑积为定值就行'],
      reminderLine: '一正二定三相等，先问等号取不取得到',
      occurrences: occurrences,
      distinctSessions: distinctSessions,
      sessionId: 'SE-1',
      freeformReason: freeform,
    );

void runF9(Harness h) {
  h.group('F9 验收① 三维打轴、不可缺轴、排除自由归因', () {
    h.test('同一条错因同时带三个轴', () {
      final e = WeakPointEngine();
      final w = e.attribute(_input());
      h.eq(w.axisKnowledge, 'condition');
      h.eq(w.axisGaokao, 'deRoutine');
      h.eq(w.axisFeynman, 'fakeUnderstanding');
    });
    h.test('缺任一轴被拒绝', () {
      h.throwsValidation(() => _input(knowledge: ''));
      h.throwsValidation(() => _input(gaokao: ''));
      h.throwsValidation(() => _input(feynman: ''));
    });
    h.test('非法轴取值被拒绝（复用考纲词典，不新造）', () {
      h.throwsValidation(() => _input(knowledge: 'vague'));
      h.throwsValidation(() => _input(gaokao: 'vague'));
      h.throwsValidation(() => _input(feynman: 'vague'));
    });
    h.test('④ 黑箱自由归因被明确拒绝', () {
      h.throwsValidation(() => _input(freeform: '基础不牢，需加强'));
      h.contains('基础不牢', '基础不牢');
    });
    h.test('三维枚举与模型层词典一致', () {
      h.eq(E.axisKnowledge.length, 4);
      h.eq(E.axisGaokao.length, 4);
      h.eq(E.axisFeynman.length, 3);
      h.isTrue(E.axisFeynman.contains('fakeUnderstanding'));
    });
  });

  h.group('F9 验收② 无证据 / 非叶子节点被拒绝', () {
    h.test('无证据条目被拒绝', () {
      h.throwsValidation(() => _input(evidence: []));
    });
    h.test('归因必须精确到知识点叶子节点', () {
      final e = WeakPointEngine();
      h.throwsValidation(() => e.attribute(_input(node: branch)));
      h.throwsValidation(() => e.attribute(_input(node: 'NO-SUCH')));
      h.notNull(e.attribute(_input()));
    });
    h.test('anchorId 由叶子节点 + 会话 + 薄弱点组成', () {
      final w = WeakPointEngine().attribute(_input());
      h.eq(w.anchorId, '$leaf::SE-1::${w.id}');
      h.contains(w.anchorId, leaf);
    });
  });

  h.group('F9 验收③④ 薄弱程度量化：假懂 / 跨时段加权', () {
    h.test('假懂使程度升高', () {
      final e = WeakPointEngine();
      final a = e.computeSeverity(
          occurrences: 2, distinctSessions: 1, fakeUnderstanding: false);
      final b = e.computeSeverity(
          occurrences: 2, distinctSessions: 1, fakeUnderstanding: true);
      h.isTrue(b > a, '假懂加权必须抬高程度');
      h.eq(b, a + 1);
    });
    h.test('跨时段重复使程度升高', () {
      final e = WeakPointEngine();
      final a = e.computeSeverity(
          occurrences: 2, distinctSessions: 1, fakeUnderstanding: false);
      final b = e.computeSeverity(
          occurrences: 2, distinctSessions: 2, fakeUnderstanding: false);
      h.isTrue(b > a);
      h.eq(b, a + 1);
    });
    h.test('错误频次升高使程度单调不减，且 clamp 在 1..5', () {
      final e = WeakPointEngine();
      var prev = 0;
      for (var n = 1; n <= 8; n++) {
        final s = e.computeSeverity(
            occurrences: n, distinctSessions: 3,
            fakeUnderstanding: true);
        h.isTrue(s >= prev, '程度不得随频次下降');
        h.isTrue(s >= 1 && s <= 5);
        prev = s;
      }
      h.eq(prev, 5);
    });
    h.test('真实样例：3 次错 + 1 次假懂 + 跨 2 时段 → 程度高', () {
      final e = WeakPointEngine();
      final w = e.attribute(_input(
          occurrences: 3, distinctSessions: 2));
      h.eq(w.severity, 5);
      h.eq(e.levelOf(w.severity), '高');
    });
  });

  h.group('F9 验收⑤⑥ 速查卡同源双渲染、黑白可读', () {
    final e = WeakPointEngine();
    final w = e.attribute(_input(occurrences: 3, distinctSessions: 2));
    final card = e.buildCard(w);

    h.test('屏幕态与打印态文本一字不差', () {
      h.eq(card.screenText, card.printText);
      h.eq(card.screenText, card.content);
      h.contains(card.content, '等号成立条件');
      h.contains(card.content, w.reminderLine);
    });
    h.test('打印态含非颜色标记（描边 / 图标 / 文字等级）', () {
      h.isTrue(card.badges.isNotEmpty);
      h.contains(card.badges.join('|'), '程度:');
      h.contains(card.badges.join('|'), '描边');
      h.contains(card.badges.join('|'), '▲');
      final printed = e.renderPrint(card);
      h.contains(printed, card.content, '打印态正文与屏幕态一致');
      h.contains(printed, '【');
      h.contains(printed, '▲');
      h.isFalse(printed.contains('#'), '打印态不依赖色值');
    });
    h.test('速查卡挂到薄弱点，且可 JSON 往返', () {
      h.eq(card.weakPointId, w.id);
      h.jsonEq(ExamReminderCard.fromJson(card.toJson()).toJson(),
          card.toJson());
    });
  });

  h.group('F9 验收⑦ 程度驱动复习权重与练手难度', () {
    h.test('复习权重随程度单调上升', () {
      final e = WeakPointEngine();
      var prev = -1;
      for (var s = 1; s <= 5; s++) {
        final w = WeakPoint(
            id: 'W-$s', anchorId: 'a', knowledgeNodeId: leaf,
            axisKnowledge: 'concept', axisGaokao: 'deRoutine',
            axisFeynman: 'cannotSay', severity: s,
            evidence: ['第 1 题'], reminderLine: 'r');
        final weight = e.reviewWeight(w);
        h.isTrue(weight > prev, '权重必须单调递增');
        prev = weight;
      }
    });
    h.test('越薄弱越先给基础巩固，达标后上难度', () {
      final e = WeakPointEngine();
      String diff(int s) => e.practiceDifficulty(WeakPoint(
          id: 'W', anchorId: 'a', knowledgeNodeId: leaf,
          axisKnowledge: 'concept', axisGaokao: 'deRoutine',
          axisFeynman: 'cannotSay', severity: s,
          evidence: ['第 1 题'], reminderLine: 'r'));
      h.eq(diff(5), 'basic');
      h.eq(diff(4), 'basic');
      h.eq(diff(3), 'medium');
      h.eq(diff(1), 'hard');
    });
  });

  h.group('F9 考前速览：一行一条、按程度排序', () {
    h.test('信息克制：每条一行，程度降序', () {
      final e = WeakPointEngine();
      final low = e.attribute(_input(occurrences: 1, distinctSessions: 1,
          feynman: 'cannotSay'));
      final high = e.attribute(_input(occurrences: 3, distinctSessions: 2));
      final lines = e.examQuickLook();
      h.eq(lines.length, 2);
      h.isFalse(lines.first.contains('\n'), '一条一行');
      h.contains(lines.first, '高');
      h.contains(lines.last, '低');
      h.eq(high.severity, 5);
      h.isTrue(low.severity < high.severity);
    });
    h.test('无薄弱点时返回空列表', () {
      h.eq(WeakPointEngine().examQuickLook().length, 0);
    });
  });

  h.group('F9 序列化往返', () {
    h.test('WeakPointEngine JSON 往返无损', () {
      final e = WeakPointEngine();
      e.attribute(_input());
      e.attribute(_input(node: 'RJ-A-BX1-CH2-2.2-COND', occurrences: 2));
      h.jsonEq(WeakPointEngine.fromJson(e.toJson()).toJson(), e.toJson());
    });
    h.test('归因结果可落入 weak_points.json', () {
      final w = WeakPointEngine().attribute(_input());
      final j = w.toJson();
      h.eq(j['knowledgeNodeId'], leaf);
      h.eq((j['evidence'] as List).length, 2);
      h.notNull(j['anchorId']);
    });
  });
}

void main() {
  final h = Harness();
  runF9(h);
  h.report();
}
