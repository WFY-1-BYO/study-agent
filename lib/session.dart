/// F8 · 学习执行引擎（会话状态机 · 闭环②核心）。
///
/// 资源就绪 →〔摸底测验：可选可跳过〕→ 视频学习+笔记 → 相关测验 → 判定
///   达标   → 总结(复述→AI纠正→反复→确认理解) → 生成 AI 笔记 → 生成复习计划纳入规划 → done
///   未达标 → AI 错因归因(WeakPoint) → 回到费曼复述-纠正 → 再测一遍（循环至通过线）
///
/// 硬约束：双层 75% 严格分离；复习闭环固定模式 2 不可配 / 不可跳过；
/// 笔记显隐只影响渲染不删数据；AI 未就绪标「待处理」但不阻塞非 AI 环节。
library study_agent.session;

import 'core.dart';
import 'models.dart';
import 'preferences.dart';

class SessionEngine implements Entity {
  static const int newContentThreshold = 45; // 与 SlotPool 一致

  final Plan plan;
  final Session initial;
  final PreferencesLayer prefs;

  String _stage = 'resources';
  final List<String> _trace = <String>[];
  final List<String> _resources = <String>[];
  final List<String> _restatements = <String>[];
  final List<String> _corrections = <String>[];
  final List<WeakPoint> _weakPoints = <WeakPoint>[];
  final List<String> _noteBlocks = <String>[];
  final List<double> _quizScores = <double>[];

  bool _pretestSkipped;
  bool _noteVisible;
  bool _understandingConfirmed = false;
  bool _aiPending = false;
  int _quizAttempts = 0;
  NoteDocument? _aiNote;
  ReviewPlan? _reviewPlan;

  SessionEngine({
    required this.plan,
    required this.initial,
    PreferencesLayer? prefs,
  })  : prefs = prefs ?? PreferencesLayer(),
        _pretestSkipped = initial.pretestSkipped,
        _noteVisible = initial.noteVisible;

  // ---------------------------------------------------------------- 查询
  String get stage => _stage;
  List<String> get trace => List<String>.unmodifiable(_trace);
  List<double> get quizScores => List<double>.unmodifiable(_quizScores);
  List<WeakPoint> get weakPoints => List<WeakPoint>.unmodifiable(_weakPoints);
  List<String> get noteBlocks => List<String>.unmodifiable(_noteBlocks);
  List<String> get resources => List<String>.unmodifiable(_resources);
  int get quizAttempts => _quizAttempts;
  bool get isDone => _stage == 'done';
  bool get aiPending => _aiPending;
  bool get pretestSkipped => _pretestSkipped;
  bool get noteVisible => _noteVisible;
  bool get understandingConfirmed => _understandingConfirmed;
  NoteDocument? get aiNote => _aiNote;
  ReviewPlan? get reviewPlan => _reviewPlan;

  /// 是否装得下新内容（按容量匹配环节，接 F6）。
  bool get canStartNewContent =>
      initial.capacityMinutes >= newContentThreshold;

  /// 恢复成可序列化的 Session（供 .studypack 的 sessions.json）。
  Session currentSession() => Session.fromJson(<String, dynamic>{
        ...initial.toJson(),
        'stage': _stage,
        'pretestSkipped': _pretestSkipped,
        'noteVisible': _noteVisible,
        'quizScore': _quizScores.isEmpty ? null : _quizScores.last,
        'attributionIds': _weakPoints.map((w) => w.id).toList(),
      });

  void _to(String next, String note) {
    _stage = next;
    _trace.add('$_stage: $note');
  }

  void _require(String expected, String action) {
    if (_stage != expected) {
      throw ValidationError('$action 只能在 $expected 阶段执行，当前 $_stage');
    }
  }

  // ---------------------------------------------------------------- 主流程
  /// AI 准备资源；aiReady=false 表示无 key / 无网，标「待处理」但不阻塞学习。
  void start({List<String> resources = const <String>[], bool aiReady = true}) {
    _require('resources', '开始会话');
    if (!canStartNewContent) {
      throw ValidationError(
          '碎片时段 ${initial.capacityMinutes}min 只跑复习闭环，请用 startReviewOnly()');
    }
    _resources.addAll(resources);
    _aiPending = !aiReady;
    _trace.add('resources: 资源就绪${_aiPending ? '（AI 待处理，不阻塞）' : ''}');
    _stage = _pretestSkipped ? 'study' : 'pretest';
    _trace.add('$_stage: ${_pretestSkipped ? '摸底测验已跳过' : '摸底测验（可选）'}');
  }

  void skipPretest() {
    if (_stage != 'pretest') {
      throw ValidationError('摸底测验只能在 pretest 阶段跳过，当前 $_stage');
    }
    _pretestSkipped = true;
    _to('study', '跳过摸底，直接视频学习');
  }

  void completePretest() {
    _require('pretest', '完成摸底测验');
    _to('study', '摸底完成，进入视频学习');
  }

  /// 笔记显隐只影响渲染，笔记数据始终保留。
  void toggleNote(bool visible) => _noteVisible = visible;

  void addNoteBlock(String text) {
    if (text.trim().isEmpty) throw ValidationError('笔记内容不可为空');
    _noteBlocks.add(text);
  }

  void finishStudy() {
    _require('study', '结束学习');
    _to('quiz', '视频 + 笔记完成，进入相关测验');
  }

  /// 提交测验成绩：按**会话通过线**（plan.passLine）判定，与规划目标线无关。
  void submitQuizScore(double score) {
    _require('quiz', '提交测验成绩');
    if (score < 0 || score > 1) {
      throw ValidationError('测验正确率必须在 [0,1]');
    }
    _quizAttempts++;
    _quizScores.add(score);
    if (score >= plan.passLine) {
      _trace.add('quiz: $score ≥ 通过线 ${plan.passLine} → 达标');
      _to('summary', '进入费曼式总结（我复述 → AI 纠正 → 反复）');
    } else {
      _trace.add('quiz: $score < 通过线 ${plan.passLine} → 未达标');
      _to('attribution', '进入 AI 错因归因（不重学、不直接换题）');
    }
  }

  /// 未达标分支：归因产出 WeakPoint 后回到费曼。
  void attribute(WeakPoint weakPoint) {
    _require('attribution', '错因归因');
    _weakPoints.add(weakPoint);
    _to('remediation', '归因完成 → 继续费曼复述-纠正');
  }

  void addRestatement(String text) {
    if (_stage != 'summary' && _stage != 'remediation') {
      throw ValidationError('复述只能在总结 / 归因回路阶段，当前 $_stage');
    }
    if (text.trim().isEmpty) throw ValidationError('复述内容不可为空');
    _restatements.add(text);
    _trace.add('$_stage: 我复述 → $text');
  }

  void aiCorrect(String correction) {
    if (_stage != 'summary' && _stage != 'remediation') {
      throw ValidationError('AI 纠正只能在总结 / 归因回路阶段，当前 $_stage');
    }
    if (correction.trim().isEmpty) throw ValidationError('纠正内容不可为空');
    _corrections.add(correction);
    _trace.add('$_stage: AI 纠正 → $correction');
  }

  /// 必须经历至少一轮「复述 + 纠正」才允许确认理解。
  void confirmUnderstanding() {
    if (_stage != 'summary' && _stage != 'remediation') {
      throw ValidationError('确认理解只能在总结 / 归因回路阶段，当前 $_stage');
    }
    if (_restatements.isEmpty || _corrections.isEmpty) {
      throw ValidationError('尚未经历「我复述 → AI 纠正」循环，不得确认理解');
    }
    _understandingConfirmed = true;
    _trace.add('$_stage: 理解确认');
    if (_stage == 'remediation') {
      _to('quiz', '归因回路收口 → 再测一遍');
    } else {
      _to('aiNote', '确认理解 → 生成个性化 AI 笔记');
    }
  }

  void generateAiNote(NoteDocument note) {
    _require('aiNote', '生成 AI 笔记');
    if (note.owner != 'ai' || !note.aiGenerated) {
      throw ValidationError('个性化 AI 笔记须 owner=ai 且 aiGenerated=true');
    }
    if (!_understandingConfirmed) {
      throw ValidationError('必须先确认理解才能生成 AI 笔记');
    }
    _aiNote = note;
    _to('reviewPlan', 'AI 笔记已生成 → 生成复习计划并纳入规划');
  }

  void generateReviewPlan(ReviewPlan review) {
    _require('reviewPlan', '生成复习计划');
    if (review.planId != plan.id) {
      throw ValidationError('复习计划必须纳入当前规划 ${plan.id}');
    }
    if (review.mode != 'fixed2') {
      throw ValidationError('复习计划必须是固定模式 2');
    }
    _reviewPlan = review;
    _to('done', '复习计划纳入规划，会话完成');
  }

  // ---------------------------------------------------------------- 复习闭环
  /// 固定模式 2，不可配、不可跳过。
  List<String> reviewSteps() => List<String>.from(ReviewPlan.fixedSteps);

  Never skipReview() =>
      throw ValidationError('复习闭环固定模式 2，不可跳过');

  Never configureReview(String mode) =>
      throw ValidationError('复习闭环固定模式 2，不可配置（尝试 $mode）');

  /// 碎片时段的复习态（下次学习前）。
  void startReviewOnly() {
    _require('resources', '开始复习');
    if (canStartNewContent) {
      // 整块时段也允许先复习，符合「下次学习前先复习上次内容」
    }
    _to('review', '复习闭环：${ReviewPlan.fixedSteps.join(' → ')}');
  }

  /// 复习默认只显示 AI 笔记 + 考前速查卡（信息克制），我的笔迹按需展开。
  List<String> reviewVisibleNotes({bool expandMyNotes = false}) =>
      expandMyNotes
          ? ['aiNote', 'examReminderCard', 'myNotes']
          : ['aiNote', 'examReminderCard'];

  @override
  Map<String, dynamic> toJson() => {
        'plan': plan.toJson(),
        'initial': initial.toJson(),
        'stage': _stage,
        'trace': _trace,
        'resources': _resources,
        'restatements': _restatements,
        'corrections': _corrections,
        'weakPoints': _weakPoints.map((w) => w.toJson()).toList(),
        'noteBlocks': _noteBlocks,
        'quizScores': _quizScores,
        'pretestSkipped': _pretestSkipped,
        'noteVisible': _noteVisible,
        'understandingConfirmed': _understandingConfirmed,
        'aiPending': _aiPending,
        'quizAttempts': _quizAttempts,
        'aiNote': _aiNote?.toJson(),
        'reviewPlan': _reviewPlan?.toJson(),
      };
}
