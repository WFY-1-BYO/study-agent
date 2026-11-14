/// F6 · SlotPool 时段池（四来源 + 绿色判定 + 容量匹配 + 重排）。
///
/// 「绿色空闲时段」不是一条规则，而是多来源、会变、需按天确认的池子：
/// 课程表手动标绿 / 校源日程 / 常驻作息模板 / 临时自定义。
/// 绿色 = 空闲 ∧ 设备可用 ∧ 能用手机 ∧ 时长够；
/// 课间与教学区域禁用自动过滤；按时段容量匹配学习环节（碎片→复习，整块→新内容）。
library study_agent.slotpool;

import 'core.dart';
import 'models.dart';

class SlotPool implements Entity {
  static const int minUsableMinutes = 10; // 课间短间隙过滤
  static const int newContentThreshold = 45; // ≥45min 才排新内容

  static const Map<String, int> sourcePriority = {
    'custom': 4,
    'schoolCalendar': 3,
    'courseTable': 2,
    'template': 1,
  };

  final String date;
  final List<Slot> slots;
  final List<SlotTemplate> templates;
  final SchoolCalendar? calendar;
  final Map<String, List<String>> assignments;

  SlotPool._({
    required this.date,
    required this.slots,
    required this.templates,
    this.calendar,
    Map<String, List<String>>? assignments,
  }) : assignments = assignments ?? <String, List<String>>{};

  /// 按天构建时段池（四来源合并、去重、过滤）。
  factory SlotPool.forDay(
    String date, {
    List<SlotTemplate>? templates,
    SchoolCalendar? calendar,
    List<Slot>? custom,
    List<Slot>? courseTable,
    bool confirmTemplates = false,
  }) {
    final tpls = templates ?? SlotTemplate.defaults();
    final pool = <Slot>[];

    void add(Slot s) {
      if (s.capacityMinutes < minUsableMinutes) return; // 课间过滤
      final i = pool.indexWhere((x) =>
          x.date == s.date &&
          x.startMin == s.startMin &&
          x.endMin == s.endMin);
      if (i < 0) {
        pool.add(s);
        return;
      }
      if ((sourcePriority[s.source] ?? 0) >
          (sourcePriority[pool[i].source] ?? 0)) {
        pool[i] = s;
      }
    }

    // 来源①：课程表手动标绿
    for (final s in courseTable ?? <Slot>[]) {
      if (s.date == date) add(s);
    }
    // 来源③：常驻作息模板（按天确认）
    for (final t in tpls) {
      if (!t.enabled) continue;
      add(Slot(
        id: '${t.id}-$date',
        date: date,
        startMin: t.startMin,
        endMin: t.endMin,
        source: 'template',
        confirmed: confirmTemplates,
      ));
    }
    // 来源②：校源日程 —— 活动自动供给空闲时段；课程/考试登记为禁用窗口
    final banned = <CalendarEntry>[];
    if (calendar != null) {
      for (final e in calendar.entries.where((x) => x.date == date)) {
        if (e.kind == 'activity' && !e.deviceBanned) {
          add(Slot(
            id: 'SC-${e.id}',
            date: date,
            startMin: e.startMin,
            endMin: e.endMin,
            source: 'schoolCalendar',
            confirmed: true,
          ));
        } else if (e.deviceBanned) {
          banned.add(e);
        }
      }
    }
    // 来源④：临时自定义（优先级最高）
    for (final s in custom ?? <Slot>[]) {
      if (s.date == date) add(s);
    }

    // 教学区域禁用：与课程/考试重叠的时段自动失去「设备可用」
    for (var i = 0; i < pool.length; i++) {
      for (final b in banned) {
        if (intervalsOverlap(
            pool[i].startMin, pool[i].endMin, b.startMin, b.endMin)) {
          pool[i] = Slot.fromJson(
              <String, dynamic>{...pool[i].toJson(), 'deviceAvailable': false});
          break;
        }
      }
    }
    pool.sort((a, b) => a.startMin.compareTo(b.startMin));
    return SlotPool._(
        date: date, slots: pool, templates: tpls, calendar: calendar);
  }

  /// 绿色时段（可学习）。
  List<Slot> available({int minRequired = 20}) {
    final list = slots.where((s) => s.isAvailable(minRequired)).toList();
    list.sort((a, b) => a.startMin.compareTo(b.startMin));
    return list;
  }

  /// 池子总容量（含未确认时段，用于排期测算）。
  int totalCapacity() =>
      slots.fold<int>(0, (s, x) => s + x.capacityMinutes);

  /// 常驻模板容量（默认 140 分钟/天）。
  int templateCapacity() => templates
      .where((t) => t.enabled)
      .fold<int>(0, (s, t) => s + t.capacityMinutes);

  /// 按时段容量匹配学习环节。
  String stageFor(Slot s) {
    if (!s.isAvailable(1)) return 'unusable';
    if (s.capacityMinutes >= newContentThreshold) return 'newContent';
    if (s.capacityMinutes >= 20) return 'review';
    return 'unusable';
  }

  /// 为一次会话挑时段：优先整块，其次拆分跨时段续接。
  List<Slot> planSession(int requiredMinutes) {
    if (requiredMinutes <= 0) {
      throw ValidationError('会话所需时长必须为正');
    }
    final pool = available(minRequired: 1);
    for (final s in pool) {
      if (s.capacityMinutes >= requiredMinutes) return [s];
    }
    final chosen = <Slot>[];
    var sum = 0;
    for (final s in pool) {
      chosen.add(s);
      sum += s.capacityMinutes;
      if (sum >= requiredMinutes) return chosen;
    }
    throw ValidationError(
        '时段容量不足：需要 $requiredMinutes 分钟，可用 $sum 分钟');
  }

  /// 重叠时段检测（返回冲突对）。
  List<List<Slot>> findOverlaps() {
    final out = <List<Slot>>[];
    for (var i = 0; i < slots.length; i++) {
      for (var j = i + 1; j < slots.length; j++) {
        if (slots[i].date == slots[j].date &&
            intervalsOverlap(slots[i].startMin, slots[i].endMin,
                slots[j].startMin, slots[j].endMin)) {
          out.add([slots[i], slots[j]]);
        }
      }
    }
    return out;
  }

  /// 登记排期（会话 → 时段 ID 列表）。
  void assign(String sessionId, List<Slot> chosen) {
    assignments[sessionId] = chosen.map((s) => s.id).toList();
  }

  /// 取消某时段：移除并清理所有引用，避免孤儿排期。
  void cancel(String slotId) {
    slots.removeWhere((s) => s.id == slotId);
    for (final ids in assignments.values) {
      ids.removeWhere((id) => id == slotId);
    }
  }

  /// 因时段消失而失去全部排期的会话（需重排）。
  List<String> orphanSessions() => assignments.entries
      .where((e) => e.value.isEmpty)
      .map((e) => e.key)
      .toList();

  /// 自动重排孤儿会话；容量不足的仍保留孤儿状态交由上层处理。
  /// 返回成功重排的会话 ID 列表。
  List<String> rescheduleOrphans(Map<String, int> requiredMinutesBySession) {
    final done = <String>[];
    for (final id in orphanSessions()) {
      final need = requiredMinutesBySession[id] ?? 20;
      try {
        assign(id, planSession(need));
        done.add(id);
      } on ValidationError {
        // 可用容量不足，保留孤儿状态
      }
    }
    return done;
  }

  @override
  Map<String, dynamic> toJson() => {
        'date': date,
        'slots': slots.map((s) => s.toJson()).toList(),
        'templates': templates.map((t) => t.toJson()).toList(),
        'calendar': calendar?.toJson(),
        'assignments': assignments,
      };

  static SlotPool fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    final slots = (m['slots'] as List).map((e) => Slot.fromJson(e)).toList();
    final tpls = (m['templates'] as List)
        .map((e) => SlotTemplate.fromJson(e))
        .toList();
    final asg = <String, List<String>>{};
    for (final e in (m['assignments'] as Map).entries) {
      asg[e.key as String] =
          (e.value as List).map((x) => x.toString()).toList();
    }
    return SlotPool._(
      date: m['date'] as String,
      slots: slots,
      templates: tpls,
      calendar: m['calendar'] == null
          ? null
          : SchoolCalendar.fromJson(m['calendar']),
      assignments: asg,
    );
  }
}
