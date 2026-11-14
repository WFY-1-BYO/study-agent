/// F10 · 变式题、难度与临场意图。
///
/// 主路径 = ② 按 WeakPoint 薄弱程度自适应 + ④ 变形强度四档递进
/// （换数字 L1 → 换情境 L2 → 换设问 L3 → 开放探究 L4）。
/// SessionIntent（跟随 / 挑战 / 刷自信）仅当次生效；
/// **防污染**：意图覆盖的作答带 sourceMode=intentOverride，
/// 归因与薄弱程度评级只认 adaptive 记录，否则一次「刷自信」会把评级拉歪。
/// 变式题必须挂靠真实母题 parentId，禁止无来源题冒充高考题。
library study_agent.variants;

import 'core.dart';
import 'models.dart';

class QuizRecord implements Entity {
  final String resourceId;
  final bool correct;
  final String sourceMode; // adaptive / intentOverride

  QuizRecord({
    required this.resourceId,
    required this.correct,
    required this.sourceMode,
  }) {
    ensureEnum(sourceMode, E.sourceModes, 'QuizRecord.sourceMode');
  }

  bool get countsForAttribution => sourceMode == 'adaptive';

  @override
  Map<String, dynamic> toJson() => {
        'resourceId': resourceId,
        'correct': correct,
        'sourceMode': sourceMode,
      };

  static QuizRecord fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return QuizRecord(
      resourceId: m['resourceId'] as String,
      correct: m['correct'] as bool,
      sourceMode: m['sourceMode'] as String,
    );
  }
}

class VariantEngine implements Entity {
  /// 变形强度四档，顺序固定（最贴 2026「去套路化」方向）。
  static const List<String> levels = ['L1', 'L2', 'L3', 'L4'];
  static const List<String> levelLabels = [
    '同条件换数字', '换情境', '换设问', '开放探究'
  ];

  /// 高考难度分布 5:3:2。
  static const Map<String, double> difficultyRatio = {
    'basic': 0.5,
    'medium': 0.3,
    'hard': 0.2,
  };

  final List<Resource> bank;
  final List<QuizRecord> records;
  final List<Resource> generated;
  String _currentSourceMode = 'adaptive';
  int _seq = 0;

  VariantEngine({List<Resource>? bank, List<QuizRecord>? records})
      : bank = bank ?? <Resource>[],
        records = records ?? <QuizRecord>[],
        generated = <Resource>[] {
    if (this.bank.isEmpty) {
      throw ValidationError('题库不能为空：变式题必须挂靠真实母题');
    }
  }

  /// 题库须备到压轴档（hard 或 L4），供给「挑战」意图。
  bool hasAdvancedItems() => bank.any((r) =>
      r.difficulty == 'hard' || r.variantLevel == 'L4');

  /// 按薄弱程度选择难度：越薄弱越先基础巩固。
  String difficultyFor(WeakPoint? wp, String intent) {
    if (intent == 'challenge') return 'hard';
    if (intent == 'confidence') return 'medium';
    final s = wp?.severity ?? 3;
    if (s >= 4) return 'basic';
    if (s == 3) return 'medium';
    return 'hard';
  }

  /// 按薄弱程度 / 意图决定可用到的最高变形档。
  String maxLevelFor(WeakPoint? wp, String intent) {
    if (intent == 'challenge') return 'L4';
    if (intent == 'confidence') return 'L2';
    final s = wp?.severity ?? 3;
    if (s >= 4) return 'L2';
    if (s == 3) return 'L3';
    return 'L4';
  }

  /// 生成一批变式题：每道都挂靠母题、继承来源，不冒充高考题。
  List<Resource> buildPractice({
    required String intent,
    WeakPoint? weakPoint,
    int count = 5,
  }) {
    ensureEnum(intent, E.sessionIntents, 'SessionIntent');
    if (count <= 0) throw ValidationError('题目数量必须为正');
    _currentSourceMode = intent == 'follow' ? 'adaptive' : 'intentOverride';

    final diff = difficultyFor(weakPoint, intent);
    final maxIdx = levels.indexOf(maxLevelFor(weakPoint, intent));
    // 「挑战」直上最高档（开放探究），其余从 L1 逐档递进且不越界。
    final startIdx = intent == 'challenge' ? maxIdx : 0;
    final out = <Resource>[];
    for (var i = 0; i < count; i++) {
      final mother = bank[i % bank.length];
      final level = levels[(startIdx + i).clamp(0, maxIdx)];
      _seq++;
      out.add(Resource(
        id: makeId('V', _seq),
        source: mother.source,
        textbookTag: mother.textbookTag,
        examTag: mother.examTag,
        yearRegion: mother.yearRegion,
        questionType: mother.questionType,
        score: mother.score,
        difficulty: diff,
        parentId: mother.id,
        variantLevel: level,
        isGaokao: false,
      ));
    }
    for (final r in out) {
      assertValidVariant(r); // 自校验：生成结果也必须满足硬约束
    }
    generated.addAll(out);
    return out;
  }

  /// 变式题合法性：必须挂靠母题、有来源、且不冒充高考真题。
  void assertValidVariant(Resource r) {
    if (r.parentId == null || r.parentId!.isEmpty) {
      throw ValidationError('变式题必须挂靠真实母题 parentId（禁止无来源题）');
    }
    if (r.source.trim().isEmpty) {
      throw ValidationError('变式题必须继承母题来源 source');
    }
    if (r.isGaokao) {
      throw ValidationError('变式题不得标记为高考真题（禁止冒充）');
    }
  }

  /// 记录作答：sourceMode 由当前意图自动判定，不允许调用方伪造。
  void recordAnswer(String resourceId, bool correct) {
    records.add(QuizRecord(
      resourceId: resourceId,
      correct: correct,
      sourceMode: _currentSourceMode,
    ));
  }

  /// 归因 / 薄弱程度评级只认 adaptive 记录。
  double accuracyForAttribution() {
    final valid = records.where((r) => r.countsForAttribution).toList();
    if (valid.isEmpty) return 0.0;
    return valid.where((r) => r.correct).length / valid.length;
  }

  int get adaptiveCount =>
      records.where((r) => r.countsForAttribution).length;

  int get overriddenCount =>
      records.where((r) => !r.countsForAttribution).length;

  /// 校验难度分布是否符合 5:3:2（容差）。
  bool checkDifficultyDistribution(List<Resource> items,
      {double tolerance = 0.15}) {
    if (items.isEmpty) return false;
    for (final e in difficultyRatio.entries) {
      final actual =
          items.where((r) => r.difficulty == e.key).length / items.length;
      if ((actual - e.value).abs() > tolerance) return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'bank': bank.map((r) => r.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'generated': generated.map((r) => r.toJson()).toList(),
        'seq': _seq,
      };

  static VariantEngine fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    final e = VariantEngine(
      bank: (m['bank'] as List).map((x) => Resource.fromJson(x)).toList(),
      records:
          (m['records'] as List).map((x) => QuizRecord.fromJson(x)).toList(),
    );
    e.generated.addAll(
        (m['generated'] as List).map((x) => Resource.fromJson(x)).toList());
    e._seq = m['seq'] as int;
    return e;
  }
}
