/// F9 · 三维错因归因 WeakPoint 与考前速查卡。
///
/// ① 知识结构 + ② 高考能力 + ③ 费曼暴露 三维打轴，**排除 ④ AI 自由归因**
/// （禁止「基础不牢」这类无证据结论）。
/// 产出精确到知识点树**叶子节点**、带证据、带一行考前提醒的条目；
/// 薄弱程度量化（频次 / 跨时段重复 / 假懂加权），驱动复习权重与练手难度。
/// 速查卡屏幕态 / 打印态同源，打印态黑白可读（描边 + 图标 + 文字冗余编码）。
library study_agent.weakpoint;

import 'core.dart';
import 'models.dart';

class AttributionInput {
  final String knowledgeNodeId;
  final String axisKnowledge;
  final String axisGaokao;
  final String axisFeynman;
  final List<String> evidence;
  final String reminderLine;
  final int occurrences;
  final int distinctSessions;
  final String sessionId;

  /// 只允许 null。非 null 即代表「AI 自由归因」，明确拒绝。
  final String? freeformReason;

  AttributionInput({
    required this.knowledgeNodeId,
    required this.axisKnowledge,
    required this.axisGaokao,
    required this.axisFeynman,
    required this.evidence,
    required this.reminderLine,
    this.occurrences = 1,
    this.distinctSessions = 1,
    required this.sessionId,
    this.freeformReason,
  }) {
    if (axisKnowledge.isEmpty || axisGaokao.isEmpty || axisFeynman.isEmpty) {
      throw ValidationError('三维标签不可缺轴（知识结构 / 高考能力 / 费曼暴露）');
    }
    ensureEnum(axisKnowledge, E.axisKnowledge, 'AttributionInput.axisKnowledge');
    ensureEnum(axisGaokao, E.axisGaokao, 'AttributionInput.axisGaokao');
    ensureEnum(axisFeynman, E.axisFeynman, 'AttributionInput.axisFeynman');
    if (evidence.isEmpty) {
      throw ValidationError('归因必须带证据（题号 / 复述原句）');
    }
    if (occurrences < 1 || distinctSessions < 1) {
      throw ValidationError('错误频次与跨时段数必须为正');
    }
    if (reminderLine.trim().isEmpty) {
      throw ValidationError('必须给出一行考前提醒');
    }
    if (freeformReason != null && freeformReason!.trim().isNotEmpty) {
      throw ValidationError('禁止黑箱自由归因（④ 已被排除），请用三维标签 + 证据');
    }
  }
}

class WeakPointEngine implements Entity {
  final ExamProfile profile;
  final List<WeakPoint> items;
  int _seq = 0;

  WeakPointEngine({ExamProfile? profile, List<WeakPoint>? items})
      : profile = profile ?? ExamProfile.shenzhen(),
        items = items ?? <WeakPoint>[];

  /// 薄弱程度量化：频次(1..3) + 跨时段重复(+1) + 假懂(+1)，clamp 1..5。
  int computeSeverity({
    required int occurrences,
    required int distinctSessions,
    required bool fakeUnderstanding,
  }) {
    var s = occurrences.clamp(1, 3);
    if (distinctSessions >= 2) s++;
    if (fakeUnderstanding) s++;
    return s.clamp(1, 5);
  }

  String levelOf(int severity) =>
      severity >= 4 ? '高' : (severity >= 3 ? '中' : '低');

  /// 归因：必须落在知识点树的叶子节点上。
  WeakPoint attribute(AttributionInput input) {
    final node = profile.knowledgeTree.find(input.knowledgeNodeId);
    if (node == null) {
      throw ValidationError('知识点节点 ${input.knowledgeNodeId} 不存在于 ExamProfile');
    }
    if (!node.isLeaf) {
      throw ValidationError(
          '归因必须精确到知识点叶子节点，${input.knowledgeNodeId} 不是叶子');
    }
    _seq++;
    final id = makeId('W', _seq);
    final wp = WeakPoint(
      id: id,
      anchorId: buildAnchorId(input.knowledgeNodeId, input.sessionId, id),
      knowledgeNodeId: input.knowledgeNodeId,
      axisKnowledge: input.axisKnowledge,
      axisGaokao: input.axisGaokao,
      axisFeynman: input.axisFeynman,
      severity: computeSeverity(
        occurrences: input.occurrences,
        distinctSessions: input.distinctSessions,
        fakeUnderstanding: input.axisFeynman == 'fakeUnderstanding',
      ),
      evidence: input.evidence,
      reminderLine: input.reminderLine,
    );
    items.add(wp);
    return wp;
  }

  /// 屏幕态与打印态同源：content 是唯一文本源。
  ExamReminderCard buildCard(WeakPoint wp) {
    final node = profile.knowledgeTree.find(wp.knowledgeNodeId);
    if (node == null) throw ValidationError('薄弱点关联的知识点节点不存在');
    return ExamReminderCard(
      id: 'RC-${wp.id}',
      weakPointId: wp.id,
      content: '${node.title}｜${wp.reminderLine}',
      badges: [
        '程度:${levelOf(wp.severity)}',
        '描边',
        '▲',
        '文字标签',
      ],
    );
  }

  /// 黑白打印渲染：在同源文本外附加**非颜色**标记，正文一字不差。
  String renderPrint(ExamReminderCard card) =>
      '【${card.badges.first}】${card.printText}  ▲';

  /// 复习权重随薄弱程度单调上升。
  int reviewWeight(WeakPoint wp) => wp.severity * 2;

  /// 练手题难度：越薄弱越先给基础巩固，达标后再上难度。
  String practiceDifficulty(WeakPoint wp) => wp.severity >= 4
      ? 'basic'
      : (wp.severity >= 3 ? 'medium' : 'hard');

  /// 考前速览：一行一条，按薄弱程度降序（信息克制）。
  List<String> examQuickLook() {
    final sorted = List<WeakPoint>.from(items)
      ..sort((a, b) => b.severity.compareTo(a.severity));
    return sorted.map((w) {
      final node = profile.knowledgeTree.find(w.knowledgeNodeId);
      return '${node?.title ?? w.knowledgeNodeId}｜${w.reminderLine}'
          '（${levelOf(w.severity)}）';
    }).toList();
  }

  @override
  Map<String, dynamic> toJson() => {
        'items': items.map((w) => w.toJson()).toList(),
        'seq': _seq,
      };

  static WeakPointEngine fromJson(Object? json, {ExamProfile? profile}) {
    final m = Map<String, dynamic>.from(json as Map);
    final e = WeakPointEngine(
      profile: profile,
      items: (m['items'] as List).map((x) => WeakPoint.fromJson(x)).toList(),
    );
    e._seq = m['seq'] as int;
    return e;
  }
}
