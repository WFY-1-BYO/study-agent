/// F7 · 规划创建（闭环②起点）。
///
/// 目标 + 量化指标(75%) + 时间界限(15天) + startMode(立即/将来) + 绿色时段引用。
/// 关键：**75% 是双层** —— 会话通过线 passLine 与规划目标线 quantTarget 是独立字段，
/// 判定逻辑绝不能混用（PRD §2.4 最易写错的一条）。
library study_agent.plans;

import 'core.dart';
import 'models.dart';
import 'preferences.dart';
import 'slotpool.dart';

class PlanEngine implements Entity {
  final SlotPool pool;
  final PreferencesLayer prefs;
  final List<Plan> plans;
  final List<Session> sessions;
  int _seq = 0;

  PlanEngine({
    required this.pool,
    PreferencesLayer? prefs,
    List<Plan>? plans,
    List<Session>? sessions,
  })  : prefs = prefs ?? PreferencesLayer(),
        plans = plans ?? <Plan>[],
        sessions = sessions ?? <Session>[];

  /// 校验时段引用：必须指向池中现存、且被判定为绿色的 Slot。
  List<Slot> _resolveSlots(List<String> ids) {
    if (ids.isEmpty) throw ValidationError('规划必须挑选至少一个绿色空闲时段');
    final out = <Slot>[];
    for (final id in ids) {
      final found = pool.slots.where((s) => s.id == id).toList();
      if (found.isEmpty) {
        throw ValidationError('时段 $id 不存在于 SlotPool（slots 必须引用，不能复制）');
      }
      final s = found.first;
      if (!s.isAvailable(1)) {
        throw ValidationError('时段 $id 不是绿色可学习时段（未确认 / 设备禁用 / 不能用手机）');
      }
      out.add(s);
    }
    return out;
  }

  /// 创建规划；立即开始会同时生成首个 Session，将来开始不生成。
  Plan createPlan({
    required String id,
    required String goal,
    double quantTarget = 0.75,
    int deadlineDays = 15,
    required String startMode,
    required List<String> slotIds,
    double passLine = 0.75,
    required String createdDate,
  }) {
    if (goal.trim().isEmpty) throw ValidationError('规划目标必填且须可量化');
    if (quantTarget <= 0 || quantTarget > 1) {
      throw ValidationError('规划目标线必须在 (0,1]');
    }
    if (passLine <= 0 || passLine > 1) {
      throw ValidationError('会话通过线必须在 (0,1]');
    }
    if (deadlineDays <= 0) throw ValidationError('时间界限必须为正天数');
    DateTime.parse(createdDate); // 非法日期抛 FormatException，交由上层
    ensureEnum(startMode, E.startModes, 'Plan.startMode');

    final slots = _resolveSlots(slotIds);
    final plan = Plan(
      id: id,
      goal: goal,
      quantTarget: quantTarget,
      deadlineDays: deadlineDays,
      startMode: startMode,
      slotIds: slotIds,
      passLine: passLine,
      createdDate: createdDate,
    );
    plans.add(plan);

    if (startMode == 'immediate') {
      final first = slots.first;
      _seq++;
      final sid = makeId('SE', _seq);
      sessions.add(Session(
        id: sid,
        planId: plan.id,
        slotId: first.id,
        capacityMinutes: first.capacityMinutes,
        stage: 'resources',
        pretestSkipped: prefs.pretestSkippedFor(sid),
        noteVisible: prefs.noteVisibleFor(sid),
        sessionIntent: prefs.intentFor(sid),
        sourceMode: 'adaptive',
      ));
    }
    return plan;
  }

  /// 会话通过线（单次测验 ≥ passLine 才进总结）。
  bool sessionPassed(double quizScore, Plan plan) => quizScore >= plan.passLine;

  /// 规划目标线（到期整体解决率 ≥ quantTarget 才算达成）。
  bool planAchieved(double overallSolveRate, Plan plan) =>
      overallSolveRate >= plan.quantTarget;

  DateTime deadlineOf(Plan plan) => DateTime.parse(plan.createdDate)
      .add(Duration(days: plan.deadlineDays));

  int daysRemaining(Plan plan, String todayIso) =>
      deadlineOf(plan).difference(DateTime.parse(todayIso)).inDays;

  bool isExpired(Plan plan, String todayIso) =>
      !DateTime.parse(todayIso).isBefore(deadlineOf(plan));

  /// 到期收口：未到期保持 active；到期按**规划目标线**判定。
  String evaluateAtDeadline(
      Plan plan, double overallSolveRate, String todayIso) {
    if (!isExpired(plan, todayIso)) return 'active';
    return planAchieved(overallSolveRate, plan) ? 'achieved' : 'expired';
  }

  Plan withStatus(Plan plan, String status) =>
      Plan.fromJson(<String, dynamic>{...plan.toJson(), 'status': status});

  @override
  Map<String, dynamic> toJson() => {
        'plans': plans.map((p) => p.toJson()).toList(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'seq': _seq,
      };

  static PlanEngine fromJson(Object? json, {required SlotPool pool}) {
    final m = Map<String, dynamic>.from(json as Map);
    final e = PlanEngine(
      pool: pool,
      plans: (m['plans'] as List).map((x) => Plan.fromJson(x)).toList(),
      sessions: (m['sessions'] as List).map((x) => Session.fromJson(x)).toList(),
    );
    e._seq = m['seq'] as int;
    return e;
  }
}
