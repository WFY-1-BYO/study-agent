/// F10 · 变式题 / 难度 / 临场意图测试（PRD §4 F10 逐条验收）。
/// 单独运行：dart test/tF10_variants.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/variants.dart';

List<Resource> _bank() => [
      Resource(id: 'M-1', source: '2026 新高考 I 卷真题',
          textbookTag: '人教A版·必修一·2.2', difficulty: 'basic',
          isGaokao: true),
      Resource(id: 'M-2', source: '2026 新高考 I 卷真题',
          textbookTag: '人教A版·必修一·2.2', difficulty: 'medium',
          isGaokao: true),
      Resource(id: 'M-3', source: '压轴·开放探究母题',
          textbookTag: '人教A版·必修一·2.2', difficulty: 'hard',
          variantLevel: 'L4'),
    ];

WeakPoint _wp(int severity) => WeakPoint(
      id: 'W-1', anchorId: 'a::b::c',
      knowledgeNodeId: 'RJ-A-BX1-CH2-2.2-EQ',
      axisKnowledge: 'condition', axisGaokao: 'deRoutine',
      axisFeynman: 'fakeUnderstanding', severity: severity,
      evidence: ['第 3 题'], reminderLine: '先问等号取不取得到',
    );

void runF10(Harness h) {
  h.group('F10 验收① 变形强度四档递进', () {
    h.test('四档枚举与顺序固定', () {
      h.eq(VariantEngine.levels.join('|'), 'L1|L2|L3|L4');
      h.eq(VariantEngine.levelLabels.length, 4);
      h.eq(VariantEngine.levelLabels.last, '开放探究');
      h.eq(VariantEngine.levelLabels.first, '同条件换数字');
    });
    h.test('生成的变式题按档位递进且不越界', () {
      final e = VariantEngine(bank: _bank());
      final list = e.buildPractice(intent: 'follow', weakPoint: _wp(2), count: 6);
      h.eq(list.length, 6);
      h.eq(list.map((r) => r.variantLevel).toSet().length, 4);
      h.isTrue(list.map((r) => r.variantLevel).contains('L4'));
      h.isFalse(list.map((r) => r.variantLevel).contains('L5'));
    });
    h.test('薄弱点高时只到 L2（先巩固），达标后可到 L4', () {
      final e = VariantEngine(bank: _bank());
      h.eq(e.maxLevelFor(_wp(5), 'follow'), 'L2');
      h.eq(e.maxLevelFor(_wp(3), 'follow'), 'L3');
      h.eq(e.maxLevelFor(_wp(1), 'follow'), 'L4');
    });
  });

  h.group('F10 验收② 按薄弱程度自适应难度', () {
    h.test('越薄弱越先基础巩固', () {
      final e = VariantEngine(bank: _bank());
      h.eq(e.difficultyFor(_wp(5), 'follow'), 'basic');
      h.eq(e.difficultyFor(_wp(4), 'follow'), 'basic');
      h.eq(e.difficultyFor(_wp(3), 'follow'), 'medium');
      h.eq(e.difficultyFor(_wp(1), 'follow'), 'hard');
    });
    h.test('生成的题目难度与自适应结果一致', () {
      final e = VariantEngine(bank: _bank());
      final list = e.buildPractice(intent: 'follow', weakPoint: _wp(5), count: 3);
      h.isTrue(list.every((r) => r.difficulty == 'basic'));
    });
  });

  h.group('F10 验收③ 临场意图与来源标记', () {
    h.test('三种意图取值合法，非法值被拒', () {
      final e = VariantEngine(bank: _bank());
      for (final v in ['follow', 'challenge', 'confidence']) {
        h.eq(e.buildPractice(intent: v, count: 1).length, 1);
      }
      h.throwsValidation(() => e.buildPractice(intent: 'yolo'));
    });
    h.test('跟随系统 → adaptive；挑战 / 刷自信 → intentOverride', () {
      final e = VariantEngine(bank: _bank());
      e.buildPractice(intent: 'follow', count: 1);
      e.recordAnswer('V-0001', true);
      h.eq(e.records.last.sourceMode, 'adaptive');
      e.buildPractice(intent: 'confidence', count: 1);
      e.recordAnswer('V-0002', true);
      h.eq(e.records.last.sourceMode, 'intentOverride');
      e.buildPractice(intent: 'challenge', count: 1);
      e.recordAnswer('V-0003', false);
      h.eq(e.records.last.sourceMode, 'intentOverride');
    });
    h.test('挑战直上 hard + L4；刷自信锁 medium / 不升档', () {
      final e = VariantEngine(bank: _bank());
      final hard = e.buildPractice(intent: 'challenge', weakPoint: _wp(5), count: 1);
      h.eq(hard.first.difficulty, 'hard');
      h.eq(hard.first.variantLevel, 'L4');
      final easy = e.buildPractice(intent: 'confidence', weakPoint: _wp(1), count: 2);
      h.isTrue(easy.every((r) => r.difficulty == 'medium'));
      h.isFalse(easy.map((r) => r.variantLevel).contains('L3'));
      h.isFalse(easy.map((r) => r.variantLevel).contains('L4'));
    });
  });

  h.group('F10 验收④ 防污染：意图覆盖不参与薄弱评级', () {
    h.test('一次「刷自信」全对不得拉高评级', () {
      final e = VariantEngine(bank: _bank());
      e.buildPractice(intent: 'follow', count: 2);
      e.recordAnswer('a', true);
      e.recordAnswer('b', false);
      h.eq(e.accuracyForAttribution(), 0.5);
      e.buildPractice(intent: 'confidence', count: 3);
      e.recordAnswer('c', true);
      e.recordAnswer('d', true);
      e.recordAnswer('e', true);
      h.eq(e.adaptiveCount, 2);
      h.eq(e.overriddenCount, 3);
      h.eq(e.accuracyForAttribution(), 0.5, '刷自信不得污染评级');
    });
    h.test('「挑战」做错也不拉低评级', () {
      final e = VariantEngine(bank: _bank());
      e.buildPractice(intent: 'follow', count: 2);
      e.recordAnswer('a', true);
      e.recordAnswer('b', true);
      h.eq(e.accuracyForAttribution(), 1.0);
      e.buildPractice(intent: 'challenge', count: 2);
      e.recordAnswer('c', false);
      e.recordAnswer('d', false);
      h.eq(e.accuracyForAttribution(), 1.0);
    });
    h.test('无 adaptive 记录时评级为 0，而非用覆盖记录顶替', () {
      final e = VariantEngine(bank: _bank());
      e.buildPractice(intent: 'confidence', count: 2);
      e.recordAnswer('a', true);
      e.recordAnswer('b', true);
      h.eq(e.accuracyForAttribution(), 0.0);
    });
    h.test('QuizRecord 自身标记 countsForAttribution', () {
      h.isTrue(QuizRecord(resourceId: 'a', correct: true,
          sourceMode: 'adaptive').countsForAttribution);
      h.isFalse(QuizRecord(resourceId: 'a', correct: true,
          sourceMode: 'intentOverride').countsForAttribution);
      h.throwsValidation(() => QuizRecord(
          resourceId: 'a', correct: true, sourceMode: 'weird'));
    });
  });

  h.group('F10 验收⑤⑧ 变式题必须挂靠母题、来源可追溯', () {
    h.test('生成的每道题都有 parentId 且继承母题来源', () {
      final e = VariantEngine(bank: _bank());
      final list = e.buildPractice(intent: 'follow', count: 4);
      for (final r in list) {
        h.notNull(r.parentId);
        h.isTrue(_bank().any((m) => m.id == r.parentId));
        h.isFalse(r.isGaokao, '变式题不冒充高考真题');
        e.assertValidVariant(r);
      }
    });
    h.test('无 parentId / 无来源 / 冒充高考题被拒绝', () {
      final e = VariantEngine(bank: _bank());
      h.throwsValidation(() => e.assertValidVariant(Resource(
          id: 'X', source: 's', textbookTag: 't', difficulty: 'basic')));
      h.throwsValidation(() => e.assertValidVariant(Resource(
          id: 'X', source: '  ', textbookTag: 't', difficulty: 'basic',
          parentId: 'M-1')));
      h.throwsValidation(() => e.assertValidVariant(Resource(
          id: 'X', source: 's', textbookTag: 't', difficulty: 'basic',
          parentId: 'M-1', isGaokao: true)));
    });
    h.test('空题库被拒绝（变式必须挂靠真实母题）', () {
      h.throwsValidation(() => VariantEngine(bank: []));
      h.throwsValidation(() => VariantEngine());
    });
  });

  h.group('F10 验收⑥⑦ 难度分布 5:3:2 与压轴档', () {
    h.test('5:3:2 分布通过校验', () {
      final e = VariantEngine(bank: _bank());
      final items = <Resource>[
        for (var i = 0; i < 5; i++)
          Resource(id: 'B$i', source: 's', textbookTag: 't', difficulty: 'basic'),
        for (var i = 0; i < 3; i++)
          Resource(id: 'M$i', source: 's', textbookTag: 't', difficulty: 'medium'),
        for (var i = 0; i < 2; i++)
          Resource(id: 'H$i', source: 's', textbookTag: 't', difficulty: 'hard'),
      ];
      h.isTrue(e.checkDifficultyDistribution(items));
    });
    h.test('偏态分布被拒绝', () {
      final e = VariantEngine(bank: _bank());
      final items = <Resource>[
        for (var i = 0; i < 9; i++)
          Resource(id: 'B$i', source: 's', textbookTag: 't', difficulty: 'basic'),
        Resource(id: 'M0', source: 's', textbookTag: 't', difficulty: 'medium'),
      ];
      h.isFalse(e.checkDifficultyDistribution(items));
      h.isFalse(e.checkDifficultyDistribution([]));
    });
    h.test('题库须备到压轴档，供给「挑战」', () {
      h.isTrue(VariantEngine(bank: _bank()).hasAdvancedItems());
      final weak = VariantEngine(bank: [
        Resource(id: 'M-1', source: 's', textbookTag: 't', difficulty: 'basic'),
      ]);
      h.isFalse(weak.hasAdvancedItems());
    });
  });

  h.group('F10 序列化往返', () {
    h.test('VariantEngine JSON 往返无损', () {
      final e = VariantEngine(bank: _bank());
      e.buildPractice(intent: 'follow', weakPoint: _wp(4), count: 3);
      e.recordAnswer('V-0001', true);
      h.jsonEq(VariantEngine.fromJson(e.toJson()).toJson(), e.toJson());
    });
    h.test('QuizRecord 单独往返', () {
      final r = QuizRecord(resourceId: 'V-1', correct: false,
          sourceMode: 'intentOverride');
      h.jsonEq(QuizRecord.fromJson(r.toJson()).toJson(), r.toJson());
    });
  });
}

void main() {
  final h = Harness();
  runF10(h);
  h.report();
}
