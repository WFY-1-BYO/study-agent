/// F1 · 领域模型与学情基线 ExamProfile。
///
/// 全部实体可 JSON 往返；任何非法枚举 / 缺字段都必须抛 ValidationError，
/// 不允许静默降级（PRD §4 F1 验收 ⑤）。
/// 知识点树挂靠人教 A 版目录，是「资源标签→归因→笔记→复习」共用的坐标体系。
library study_agent.models;

import 'core.dart';

// ------------------------------------------------------------------ 枚举
String ensureEnum(String value, List<String> allowed, String where) {
  if (!allowed.contains(value)) {
    throw ValidationError(
        '$where 非法取值: "$value"（允许 ${allowed.join(' / ')}）');
  }
  return value;
}

class E {
  static const taskTypes = ['habit', 'once'];
  static const reminderModes = ['vibration', 'sound', 'none'];
  static const startModes = ['immediate', 'scheduled'];
  static const planStatuses = ['active', 'achieved', 'expired'];
  static const sessionIntents = ['follow', 'challenge', 'confidence'];
  static const sourceModes = ['adaptive', 'intentOverride'];
  static const sessionStages = [
    'resources', 'pretest', 'study', 'quiz', 'passed', 'summary',
    'aiNote', 'reviewPlan', 'attribution', 'remediation', 'review', 'done'
  ];
  static const reviewModes = ['fixed2'];
  static const slotSources = [
    'courseTable', 'schoolCalendar', 'template', 'custom'
  ];
  static const calendarKinds = ['course', 'exam', 'activity'];
  static const noteOwners = ['ai', 'mine'];
  static const noteChannels = ['A', 'C', 'D'];
  static const contentTypes = [
    'structuredText', 'svgInk', 'pdf', 'externalRef'
  ];
  static const difficulties = ['basic', 'medium', 'hard'];
  static const variantLevels = ['L1', 'L2', 'L3', 'L4'];
  static const axisKnowledge = ['concept', 'condition', 'type', 'calculation'];
  static const axisGaokao = [
    'contextModeling', 'deRoutine', 'openInquiry', 'infoExtraction'
  ];
  static const axisFeynman = ['cannotSay', 'sayWrong', 'fakeUnderstanding'];
}

// ------------------------------------------------------------------ JSON 助手
Map<String, dynamic> _map(Object? v, String w) {
  if (v is! Map) throw ValidationError('$w 应为对象');
  return Map<String, dynamic>.from(v);
}

String _str(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! String) throw ValidationError('$w.$k 应为字符串');
  return v;
}

String? _optStr(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v == null ? null : v as String;
}

int _int(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! int) throw ValidationError('$w.$k 应为整数');
  return v;
}

double _dbl(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! num) throw ValidationError('$w.$k 应为数值');
  return v.toDouble();
}

double? _optDbl(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v == null ? null : (v as num).toDouble();
}

bool _bool(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! bool) throw ValidationError('$w.$k 应为布尔');
  return v;
}

List<String> _strs(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! List) throw ValidationError('$w.$k 应为数组');
  return v.map((e) => e.toString()).toList();
}

List<int> _ints(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! List) throw ValidationError('$w.$k 应为数组');
  return v.map((e) => e as int).toList();
}

List<Map<String, dynamic>> _maps(
    Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! List) throw ValidationError('$w.$k 应为数组');
  return v.map((e) => _map(e, '$w.$k[]')).toList();
}

// ------------------------------------------------------------------ 基类
abstract class Entity {
  Map<String, dynamic> toJson();
}

// ------------------------------------------------------------------ 知识点树
class KnowledgeNode implements Entity {
  final String id;
  final String title;
  final List<KnowledgeNode> children;

  KnowledgeNode({required this.id, required this.title, List<KnowledgeNode>? children})
      : children = children ?? <KnowledgeNode>[];

  bool get isLeaf => children.isEmpty;

  /// 按 id 定位任意节点（含叶子）。找不到返回 null。
  KnowledgeNode? find(String nodeId) {
    if (id == nodeId) return this;
    for (final c in children) {
      final hit = c.find(nodeId);
      if (hit != null) return hit;
    }
    return null;
  }

  List<KnowledgeNode> get leaves {
    if (isLeaf) return [this];
    return children.expand((c) => c.leaves).toList();
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'children': children.map((c) => c.toJson()).toList(),
      };

  static KnowledgeNode fromJson(Object? json) {
    final m = _map(json, 'KnowledgeNode');
    return KnowledgeNode(
      id: _str(m, 'id', 'KnowledgeNode'),
      title: _str(m, 'title', 'KnowledgeNode'),
      children: _maps(m, 'children', 'KnowledgeNode')
          .map(KnowledgeNode.fromJson)
          .toList(),
    );
  }
}

// ------------------------------------------------------------------ 学情基线
class ExamProfile implements Entity {
  final String region;
  final String school;
  final String paper;
  final String examMode;
  final String textbook;
  final List<Map<String, dynamic>> questionTypes;
  final Map<String, double> difficultyRatio;
  final List<String> styleTags;
  final KnowledgeNode knowledgeTree;

  ExamProfile({
    required this.region,
    required this.school,
    required this.paper,
    required this.examMode,
    required this.textbook,
    required this.questionTypes,
    required this.difficultyRatio,
    required this.styleTags,
    required this.knowledgeTree,
  });

  /// 深圳中学 · 新高考 I 卷 · 人教 A 版 2019（PRD §2.3 问题 1 结论）。
  factory ExamProfile.shenzhen() => ExamProfile(
        region: '广东深圳',
        school: '深圳中学',
        paper: '新高考 I 卷（新课标 I 卷）',
        examMode: '3+1+2；数学不分文理；选考科目广东自主命题',
        textbook: '人教 A 版（2019 新版）',
        questionTypes: [
          {'name': '单选', 'count': 8, 'scoreTotal': 40},
          {'name': '多选', 'count': 4, 'scoreTotal': 20},
          {'name': '填空', 'count': 4, 'scoreTotal': 20},
          {'name': '解答', 'count': 6, 'scoreTotal': 70},
        ],
        difficultyRatio: {'basic': 0.5, 'medium': 0.3, 'hard': 0.2},
        styleTags: [
          '去套路化', '题型顺序重组', '情境化建模增多', '重思维轻计算',
          '开放探究 + 新定义压轴', '回归教材'
        ],
        knowledgeTree: KnowledgeNode(
          id: 'RJ-A-BX1',
          title: '人教A版·必修第一册',
          children: [
            KnowledgeNode(
              id: 'RJ-A-BX1-CH2',
              title: '第二章 一元二次函数、方程和不等式',
              children: [
                KnowledgeNode(
                  id: 'RJ-A-BX1-CH2-2.2',
                  title: '2.2 基本不等式',
                  children: [
                    KnowledgeNode(
                        id: 'RJ-A-BX1-CH2-2.2-EQ', title: '等号成立条件'),
                    KnowledgeNode(
                        id: 'RJ-A-BX1-CH2-2.2-COND',
                        title: '一正二定三相等'),
                    KnowledgeNode(
                        id: 'RJ-A-BX1-CH2-2.2-MAX', title: '最值应用'),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  int get totalScore => questionTypes.fold<int>(
      0, (s, q) => s + ((q['scoreTotal'] as num).toInt()));

  double get difficultySum => difficultyRatio.values
      .fold<double>(0.0, (s, v) => s + v);

  @override
  Map<String, dynamic> toJson() => {
        'region': region,
        'school': school,
        'paper': paper,
        'examMode': examMode,
        'textbook': textbook,
        'questionTypes': questionTypes,
        'difficultyRatio': difficultyRatio,
        'styleTags': styleTags,
        'knowledgeTree': knowledgeTree.toJson(),
      };

  static ExamProfile fromJson(Object? json) {
    final m = _map(json, 'ExamProfile');
    final ratio = <String, double>{};
    for (final e in _map(m['difficultyRatio'], 'ExamProfile.difficultyRatio').entries) {
      ratio[e.key] = (e.value as num).toDouble();
    }
    return ExamProfile(
      region: _str(m, 'region', 'ExamProfile'),
      school: _str(m, 'school', 'ExamProfile'),
      paper: _str(m, 'paper', 'ExamProfile'),
      examMode: _str(m, 'examMode', 'ExamProfile'),
      textbook: _str(m, 'textbook', 'ExamProfile'),
      questionTypes: _maps(m, 'questionTypes', 'ExamProfile'),
      difficultyRatio: ratio,
      styleTags: _strs(m, 'styleTags', 'ExamProfile'),
      knowledgeTree: KnowledgeNode.fromJson(m['knowledgeTree']),
    );
  }
}

// ------------------------------------------------------------------ 任务
class Task implements Entity {
  final String id;
  final String type;
  final String name;
  final String timeHm;
  final List<int> weekdays;
  final String reminderMode;
  final int leadMinutes;
  final String? action;
  final bool enabled;

  Task({
    required this.id,
    required this.type,
    required this.name,
    required this.timeHm,
    List<int>? weekdays,
    required this.reminderMode,
    this.leadMinutes = 2,
    this.action,
    this.enabled = true,
  })  : weekdays = weekdays ?? <int>[1, 2, 3, 4, 5, 6, 7] {
    ensureEnum(type, E.taskTypes, 'Task.type');
    ensureEnum(reminderMode, E.reminderModes, 'Task.reminderMode');
    parseHm(timeHm);
    if (leadMinutes < 0) throw ValidationError('Task.leadMinutes 不能为负');
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'type': type, 'name': name, 'timeHm': timeHm,
        'weekdays': weekdays, 'reminderMode': reminderMode,
        'leadMinutes': leadMinutes, 'action': action, 'enabled': enabled,
      };

  static Task fromJson(Object? json) {
    final m = _map(json, 'Task');
    return Task(
      id: _str(m, 'id', 'Task'),
      type: _str(m, 'type', 'Task'),
      name: _str(m, 'name', 'Task'),
      timeHm: _str(m, 'timeHm', 'Task'),
      weekdays: _ints(m, 'weekdays', 'Task'),
      reminderMode: _str(m, 'reminderMode', 'Task'),
      leadMinutes: _int(m, 'leadMinutes', 'Task'),
      action: _optStr(m, 'action'),
      enabled: _bool(m, 'enabled', 'Task'),
    );
  }
}

// ------------------------------------------------------------------ 规划
class Plan implements Entity {
  final String id;
  final String goal;
  final double quantTarget;
  final int deadlineDays;
  final String startMode;
  final List<String> slotIds;
  final double passLine;
  final String status;
  final String createdDate;

  Plan({
    required this.id,
    required this.goal,
    this.quantTarget = 0.75,
    this.deadlineDays = 15,
    required this.startMode,
    List<String>? slotIds,
    this.passLine = 0.75,
    this.status = 'active',
    required this.createdDate,
  })  : slotIds = slotIds ?? <String>[] {
    ensureEnum(startMode, E.startModes, 'Plan.startMode');
    ensureEnum(status, E.planStatuses, 'Plan.status');
    if (quantTarget <= 0 || quantTarget > 1) {
      throw ValidationError('Plan.quantTarget 必须在 (0,1]');
    }
    if (passLine <= 0 || passLine > 1) {
      throw ValidationError('Plan.passLine 必须在 (0,1]');
    }
    if (deadlineDays <= 0) throw ValidationError('Plan.deadlineDays 必须为正');
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'goal': goal, 'quantTarget': quantTarget,
        'deadlineDays': deadlineDays, 'startMode': startMode,
        'slotIds': slotIds, 'passLine': passLine, 'status': status,
        'createdDate': createdDate,
      };

  static Plan fromJson(Object? json) {
    final m = _map(json, 'Plan');
    return Plan(
      id: _str(m, 'id', 'Plan'),
      goal: _str(m, 'goal', 'Plan'),
      quantTarget: _dbl(m, 'quantTarget', 'Plan'),
      deadlineDays: _int(m, 'deadlineDays', 'Plan'),
      startMode: _str(m, 'startMode', 'Plan'),
      slotIds: _strs(m, 'slotIds', 'Plan'),
      passLine: _dbl(m, 'passLine', 'Plan'),
      status: _str(m, 'status', 'Plan'),
      createdDate: _str(m, 'createdDate', 'Plan'),
    );
  }
}

// ------------------------------------------------------------------ 会话
class Session implements Entity {
  final String id;
  final String planId;
  final String slotId;
  final int capacityMinutes;
  final String stage;
  final bool pretestSkipped;
  final bool noteVisible;
  final double? quizScore;
  final String sessionIntent;
  final String sourceMode;
  final List<String> attributionIds;

  Session({
    required this.id,
    required this.planId,
    required this.slotId,
    required this.capacityMinutes,
    this.stage = 'resources',
    this.pretestSkipped = true,
    this.noteVisible = true,
    this.quizScore,
    this.sessionIntent = 'follow',
    this.sourceMode = 'adaptive',
    List<String>? attributionIds,
  })  : attributionIds = attributionIds ?? <String>[] {
    ensureEnum(stage, E.sessionStages, 'Session.stage');
    ensureEnum(sessionIntent, E.sessionIntents, 'Session.sessionIntent');
    ensureEnum(sourceMode, E.sourceModes, 'Session.sourceMode');
    if (capacityMinutes <= 0) {
      throw ValidationError('Session.capacityMinutes 必须为正');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'planId': planId, 'slotId': slotId,
        'capacityMinutes': capacityMinutes, 'stage': stage,
        'pretestSkipped': pretestSkipped, 'noteVisible': noteVisible,
        'quizScore': quizScore, 'sessionIntent': sessionIntent,
        'sourceMode': sourceMode, 'attributionIds': attributionIds,
      };

  static Session fromJson(Object? json) {
    final m = _map(json, 'Session');
    return Session(
      id: _str(m, 'id', 'Session'),
      planId: _str(m, 'planId', 'Session'),
      slotId: _str(m, 'slotId', 'Session'),
      capacityMinutes: _int(m, 'capacityMinutes', 'Session'),
      stage: _str(m, 'stage', 'Session'),
      pretestSkipped: _bool(m, 'pretestSkipped', 'Session'),
      noteVisible: _bool(m, 'noteVisible', 'Session'),
      quizScore: _optDbl(m, 'quizScore'),
      sessionIntent: _str(m, 'sessionIntent', 'Session'),
      sourceMode: _str(m, 'sourceMode', 'Session'),
      attributionIds: _strs(m, 'attributionIds', 'Session'),
    );
  }
}

// ------------------------------------------------------------------ 复习计划（固定模式 2）
class ReviewPlan implements Entity {
  static const fixedSteps = [
    '复述上次理解', 'AI 纠正', '反复确认', '几道简单练手题', '今日新内容'
  ];

  final String id;
  final String planId;
  final String mode;
  final List<String> steps;
  final String sourceSessionId;
  final List<String> scheduledSlotIds;

  ReviewPlan({
    required this.id,
    required this.planId,
    this.mode = 'fixed2',
    List<String>? steps,
    required this.sourceSessionId,
    List<String>? scheduledSlotIds,
  })  : steps = steps ?? List<String>.from(fixedSteps),
        scheduledSlotIds = scheduledSlotIds ?? <String>[] {
    ensureEnum(mode, E.reviewModes, 'ReviewPlan.mode');
    // 固定模式 2：不仅数量，内容也必须逐字一致，防止反序列化时偷换流程。
    if (this.steps.join('|') != fixedSteps.join('|')) {
      throw ValidationError('复习闭环固定模式 2，步骤不可配置 / 增删 / 改序');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'planId': planId, 'mode': mode, 'steps': steps,
        'sourceSessionId': sourceSessionId,
        'scheduledSlotIds': scheduledSlotIds,
      };

  static ReviewPlan fromJson(Object? json) {
    final m = _map(json, 'ReviewPlan');
    return ReviewPlan(
      id: _str(m, 'id', 'ReviewPlan'),
      planId: _str(m, 'planId', 'ReviewPlan'),
      mode: _str(m, 'mode', 'ReviewPlan'),
      steps: _strs(m, 'steps', 'ReviewPlan'),
      sourceSessionId: _str(m, 'sourceSessionId', 'ReviewPlan'),
      scheduledSlotIds: _strs(m, 'scheduledSlotIds', 'ReviewPlan'),
    );
  }
}

// ------------------------------------------------------------------ 时段
class Slot implements Entity {
  final String id;
  final String date;
  final int startMin;
  final int endMin;
  final String source;
  final bool deviceAvailable;
  final bool phoneAllowed;
  final bool confirmed;

  Slot({
    required this.id,
    required this.date,
    required this.startMin,
    required this.endMin,
    required this.source,
    this.deviceAvailable = true,
    this.phoneAllowed = true,
    this.confirmed = false,
  }) {
    ensureEnum(source, E.slotSources, 'Slot.source');
    if (endMin <= startMin) throw ValidationError('Slot 结束须晚于开始');
    if (startMin < 0 || endMin > 1440) {
      throw ValidationError('Slot 时间越界');
    }
  }

  int get capacityMinutes => endMin - startMin;

  /// 绿色判定：空闲 ∧ 设备可用 ∧ 能用手机 ∧ 时长够。
  bool isAvailable(int minRequired) =>
      deviceAvailable && phoneAllowed && confirmed && capacityMinutes >= minRequired;

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'startMin': startMin, 'endMin': endMin,
        'source': source, 'deviceAvailable': deviceAvailable,
        'phoneAllowed': phoneAllowed, 'confirmed': confirmed,
      };

  static Slot fromJson(Object? json) {
    final m = _map(json, 'Slot');
    return Slot(
      id: _str(m, 'id', 'Slot'),
      date: _str(m, 'date', 'Slot'),
      startMin: _int(m, 'startMin', 'Slot'),
      endMin: _int(m, 'endMin', 'Slot'),
      source: _str(m, 'source', 'Slot'),
      deviceAvailable: _bool(m, 'deviceAvailable', 'Slot'),
      phoneAllowed: _bool(m, 'phoneAllowed', 'Slot'),
      confirmed: _bool(m, 'confirmed', 'Slot'),
    );
  }
}

class SlotTemplate implements Entity {
  final String id;
  final String label;
  final int startMin;
  final int endMin;
  final bool enabled;

  SlotTemplate({
    required this.id,
    required this.label,
    required this.startMin,
    required this.endMin,
    this.enabled = true,
  }) {
    if (endMin <= startMin) throw ValidationError('SlotTemplate 结束须晚于开始');
  }

  int get capacityMinutes => endMin - startMin;

  /// 用户给的 4 个常驻时段：07:00–07:30 / 13:00–13:30 / 17:20–18:20 / 21:30–21:50。
  static List<SlotTemplate> defaults() => [
        SlotTemplate(id: 'T1', label: '早起床', startMin: 420, endMin: 450),
        SlotTemplate(id: 'T2', label: '午间', startMin: 780, endMin: 810),
        SlotTemplate(id: 'T3', label: '放学后整块', startMin: 1040, endMin: 1100),
        SlotTemplate(id: 'T4', label: '晚间', startMin: 1290, endMin: 1310),
      ];

  static int get defaultTotalMinutes =>
      defaults().fold<int>(0, (s, t) => s + t.capacityMinutes);

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'label': label, 'startMin': startMin,
        'endMin': endMin, 'enabled': enabled,
      };

  static SlotTemplate fromJson(Object? json) {
    final m = _map(json, 'SlotTemplate');
    return SlotTemplate(
      id: _str(m, 'id', 'SlotTemplate'),
      label: _str(m, 'label', 'SlotTemplate'),
      startMin: _int(m, 'startMin', 'SlotTemplate'),
      endMin: _int(m, 'endMin', 'SlotTemplate'),
      enabled: _bool(m, 'enabled', 'SlotTemplate'),
    );
  }
}

// ------------------------------------------------------------------ 校源日程
class CalendarEntry implements Entity {
  final String id;
  final String date;
  final int startMin;
  final int endMin;
  final String kind;
  final String title;
  final bool deviceBanned;

  CalendarEntry({
    required this.id,
    required this.date,
    required this.startMin,
    required this.endMin,
    required this.kind,
    required this.title,
    this.deviceBanned = true,
  }) {
    ensureEnum(kind, E.calendarKinds, 'CalendarEntry.kind');
    if (endMin <= startMin) throw ValidationError('CalendarEntry 结束须晚于开始');
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'startMin': startMin, 'endMin': endMin,
        'kind': kind, 'title': title, 'deviceBanned': deviceBanned,
      };

  static CalendarEntry fromJson(Object? json) {
    final m = _map(json, 'CalendarEntry');
    return CalendarEntry(
      id: _str(m, 'id', 'CalendarEntry'),
      date: _str(m, 'date', 'CalendarEntry'),
      startMin: _int(m, 'startMin', 'CalendarEntry'),
      endMin: _int(m, 'endMin', 'CalendarEntry'),
      kind: _str(m, 'kind', 'CalendarEntry'),
      title: _str(m, 'title', 'CalendarEntry'),
      deviceBanned: _bool(m, 'deviceBanned', 'CalendarEntry'),
    );
  }
}

class SchoolCalendar implements Entity {
  final String id;
  final String importedFrom;
  final List<CalendarEntry> entries;

  SchoolCalendar({
    required this.id,
    required this.importedFrom,
    List<CalendarEntry>? entries,
  }) : entries = entries ?? <CalendarEntry>[];

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'importedFrom': importedFrom,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  static SchoolCalendar fromJson(Object? json) {
    final m = _map(json, 'SchoolCalendar');
    return SchoolCalendar(
      id: _str(m, 'id', 'SchoolCalendar'),
      importedFrom: _str(m, 'importedFrom', 'SchoolCalendar'),
      entries: _maps(m, 'entries', 'SchoolCalendar')
          .map(CalendarEntry.fromJson)
          .toList(),
    );
  }
}

// ------------------------------------------------------------------ 薄弱点 / 速查卡
class WeakPoint implements Entity {
  final String id;
  final String anchorId;
  final String knowledgeNodeId;
  final String axisKnowledge;
  final String axisGaokao;
  final String axisFeynman;
  final int severity;
  final List<String> evidence;
  final String reminderLine;

  WeakPoint({
    required this.id,
    required this.anchorId,
    required this.knowledgeNodeId,
    required this.axisKnowledge,
    required this.axisGaokao,
    required this.axisFeynman,
    required this.severity,
    List<String>? evidence,
    required this.reminderLine,
  }) : evidence = evidence ?? <String>[] {
    ensureEnum(axisKnowledge, E.axisKnowledge, 'WeakPoint.axisKnowledge');
    ensureEnum(axisGaokao, E.axisGaokao, 'WeakPoint.axisGaokao');
    ensureEnum(axisFeynman, E.axisFeynman, 'WeakPoint.axisFeynman');
    if (this.evidence.isEmpty) {
      throw ValidationError('WeakPoint 必须有证据（题号 / 复述原句）');
    }
    if (severity < 1 || severity > 5) {
      throw ValidationError('WeakPoint.severity 必须在 1..5');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'anchorId': anchorId,
        'knowledgeNodeId': knowledgeNodeId,
        'axisKnowledge': axisKnowledge, 'axisGaokao': axisGaokao,
        'axisFeynman': axisFeynman, 'severity': severity,
        'evidence': evidence, 'reminderLine': reminderLine,
      };

  static WeakPoint fromJson(Object? json) {
    final m = _map(json, 'WeakPoint');
    return WeakPoint(
      id: _str(m, 'id', 'WeakPoint'),
      anchorId: _str(m, 'anchorId', 'WeakPoint'),
      knowledgeNodeId: _str(m, 'knowledgeNodeId', 'WeakPoint'),
      axisKnowledge: _str(m, 'axisKnowledge', 'WeakPoint'),
      axisGaokao: _str(m, 'axisGaokao', 'WeakPoint'),
      axisFeynman: _str(m, 'axisFeynman', 'WeakPoint'),
      severity: _int(m, 'severity', 'WeakPoint'),
      evidence: _strs(m, 'evidence', 'WeakPoint'),
      reminderLine: _str(m, 'reminderLine', 'WeakPoint'),
    );
  }
}

/// 屏幕态与打印态**同源**：文本一字不差，打印态另有非颜色标记 badges。
class ExamReminderCard implements Entity {
  final String id;
  final String weakPointId;
  final String content;
  final List<String> badges;

  ExamReminderCard({
    required this.id,
    required this.weakPointId,
    required this.content,
    List<String>? badges,
  }) : badges = badges ?? <String>[];

  String get screenText => content;
  String get printText => content;

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'weakPointId': weakPointId,
        'content': content, 'badges': badges,
        'screenText': screenText, 'printText': printText,
      };

  static ExamReminderCard fromJson(Object? json) {
    final m = _map(json, 'ExamReminderCard');
    return ExamReminderCard(
      id: _str(m, 'id', 'ExamReminderCard'),
      weakPointId: _str(m, 'weakPointId', 'ExamReminderCard'),
      content: _str(m, 'content', 'ExamReminderCard'),
      badges: _strs(m, 'badges', 'ExamReminderCard'),
    );
  }
}

// ------------------------------------------------------------------ 笔记
class NoteDocument implements Entity {
  final String id;
  final String owner;
  final String channel;
  final String contentType;
  final String anchorId;
  final List<String> blocks;
  final bool aiGenerated;

  NoteDocument({
    required this.id,
    required this.owner,
    required this.channel,
    required this.contentType,
    required this.anchorId,
    List<String>? blocks,
    this.aiGenerated = false,
  })  : blocks = blocks ?? <String>[] {
    ensureEnum(owner, E.noteOwners, 'NoteDocument.owner');
    ensureEnum(channel, E.noteChannels, 'NoteDocument.channel');
    ensureEnum(contentType, E.contentTypes, 'NoteDocument.contentType');
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'owner': owner, 'channel': channel,
        'contentType': contentType, 'anchorId': anchorId,
        'blocks': blocks, 'aiGenerated': aiGenerated,
      };

  static NoteDocument fromJson(Object? json) {
    final m = _map(json, 'NoteDocument');
    return NoteDocument(
      id: _str(m, 'id', 'NoteDocument'),
      owner: _str(m, 'owner', 'NoteDocument'),
      channel: _str(m, 'channel', 'NoteDocument'),
      contentType: _str(m, 'contentType', 'NoteDocument'),
      anchorId: _str(m, 'anchorId', 'NoteDocument'),
      blocks: _strs(m, 'blocks', 'NoteDocument'),
      aiGenerated: _bool(m, 'aiGenerated', 'NoteDocument'),
    );
  }
}

class AnchorLink implements Entity {
  final String anchorId;
  final List<String> aiNoteIds;
  final List<String> myNoteIds;

  AnchorLink({
    required this.anchorId,
    List<String>? aiNoteIds,
    List<String>? myNoteIds,
  })  : aiNoteIds = aiNoteIds ?? <String>[],
        myNoteIds = myNoteIds ?? <String>[];

  @override
  Map<String, dynamic> toJson() => {
        'anchorId': anchorId,
        'aiNoteIds': aiNoteIds,
        'myNoteIds': myNoteIds,
      };

  static AnchorLink fromJson(Object? json) {
    final m = _map(json, 'AnchorLink');
    return AnchorLink(
      anchorId: _str(m, 'anchorId', 'AnchorLink'),
      aiNoteIds: _strs(m, 'aiNoteIds', 'AnchorLink'),
      myNoteIds: _strs(m, 'myNoteIds', 'AnchorLink'),
    );
  }
}

// ------------------------------------------------------------------ 资源
class Resource implements Entity {
  final String id;
  final String source;
  final String textbookTag;
  final String examTag;
  final String yearRegion;
  final String questionType;
  final int score;
  final String difficulty;
  final String? parentId;
  final String variantLevel;
  final bool isGaokao;

  Resource({
    required this.id,
    required this.source,
    required this.textbookTag,
    this.examTag = '',
    this.yearRegion = '',
    this.questionType = '',
    this.score = 0,
    required this.difficulty,
    this.parentId,
    this.variantLevel = 'L1',
    this.isGaokao = false,
  }) {
    ensureEnum(difficulty, E.difficulties, 'Resource.difficulty');
    ensureEnum(variantLevel, E.variantLevels, 'Resource.variantLevel');
    if (source.trim().isEmpty) {
      throw ValidationError('Resource.source 必填（禁止无来源题）');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'source': source, 'textbookTag': textbookTag,
        'examTag': examTag, 'yearRegion': yearRegion,
        'questionType': questionType, 'score': score,
        'difficulty': difficulty, 'parentId': parentId,
        'variantLevel': variantLevel, 'isGaokao': isGaokao,
      };

  static Resource fromJson(Object? json) {
    final m = _map(json, 'Resource');
    return Resource(
      id: _str(m, 'id', 'Resource'),
      source: _str(m, 'source', 'Resource'),
      textbookTag: _str(m, 'textbookTag', 'Resource'),
      examTag: _str(m, 'examTag', 'Resource'),
      yearRegion: _str(m, 'yearRegion', 'Resource'),
      questionType: _str(m, 'questionType', 'Resource'),
      score: _int(m, 'score', 'Resource'),
      difficulty: _str(m, 'difficulty', 'Resource'),
      parentId: _optStr(m, 'parentId'),
      variantLevel: _str(m, 'variantLevel', 'Resource'),
      isGaokao: _bool(m, 'isGaokao', 'Resource'),
    );
  }
}

// ------------------------------------------------------------------ 数据包
class DataPackage implements Entity {
  /// .studypack 的 13 类实体文件名（另加 manifest.json 共 14 个文件，PRD §6.1）。
  static const entityFiles = [
    'preferences.json', 'exam_profile.json', 'school_calendar.json',
    'slot_pool.json', 'tasks.json', 'plans.json', 'sessions.json',
    'weak_points.json', 'review.json', 'ai_notes.json', 'my_notes.json',
    'anchor_links.json', 'resources.json',
  ];

  final Map<String, dynamic> manifest;
  final Map<String, List<Map<String, dynamic>>> entities;

  DataPackage({Map<String, dynamic>? manifest, Map<String, List<Map<String, dynamic>>>? entities})
      : manifest = manifest ?? <String, dynamic>{},
        entities = entities ?? <String, List<Map<String, dynamic>>>{};

  @override
  Map<String, dynamic> toJson() => {
        'manifest': manifest,
        'entities': entities,
      };

  static DataPackage fromJson(Object? json) {
    final m = _map(json, 'DataPackage');
    final src = _map(m['entities'], 'DataPackage.entities');
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in src.entries) {
      out[e.key] = _maps({'v': e.value}, 'v', 'DataPackage.entities');
    }
    return DataPackage(
      manifest: _map(m['manifest'], 'DataPackage.manifest'),
      entities: out,
    );
  }
}
