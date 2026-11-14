/// F5 · 任务与提醒（闭环①）。
///
/// 习惯性 / 一次性任务、周期调度、今日日程、倒计时、提醒方式与提前量、
/// 一键跳转外部 App、设备禁用时段自动静默。
/// 规划排定的学习时段写回同一张日程，同样受倒计时与提醒管辖。
library study_agent.tasks;

import 'core.dart';
import 'models.dart';
import 'preferences.dart';

class ScheduleItem implements Entity {
  final String id;
  final String title;
  final String kind; // task / study / review
  final int startMin;
  final int endMin;

  ScheduleItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.startMin,
    required this.endMin,
  }) {
    if (endMin <= startMin) throw ValidationError('日程项结束须晚于开始');
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'kind': kind,
        'startMin': startMin, 'endMin': endMin,
      };

  static ScheduleItem fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return ScheduleItem(
      id: m['id'] as String,
      title: m['title'] as String,
      kind: m['kind'] as String,
      startMin: m['startMin'] as int,
      endMin: m['endMin'] as int,
    );
  }
}

class ReminderDecision implements Entity {
  final bool active;
  final String mode; // vibration / sound / none
  final String reason;

  ReminderDecision(this.active, this.mode, this.reason);

  bool get silent => !active || mode == 'none';

  @override
  Map<String, dynamic> toJson() => {
        'active': active, 'mode': mode, 'reason': reason, 'silent': silent,
      };
}

/// 设备禁用窗口（教学区域 / 考场内）：不响不亮屏。
class DeviceWindow implements Entity {
  final String date;
  final int startMin;
  final int endMin;
  final String label;

  DeviceWindow({
    required this.date,
    required this.startMin,
    required this.endMin,
    required this.label,
  }) {
    if (endMin <= startMin) throw ValidationError('禁用窗口结束须晚于开始');
  }

  static DeviceWindow fromCalendarEntry(CalendarEntry e) => DeviceWindow(
        date: e.date,
        startMin: e.startMin,
        endMin: e.endMin,
        label: e.title,
      );

  @override
  Map<String, dynamic> toJson() => {
        'date': date, 'startMin': startMin,
        'endMin': endMin, 'label': label,
      };
}

class TaskEngine {
  final List<Task> tasks;
  final PreferencesLayer prefs;
  final List<DeviceWindow> bannedWindows;
  final List<ScheduleItem> studyBlocks;

  TaskEngine({
    List<Task>? tasks,
    PreferencesLayer? prefs,
    List<DeviceWindow>? bannedWindows,
    List<ScheduleItem>? studyBlocks,
  })  : tasks = tasks ?? <Task>[],
        prefs = prefs ?? PreferencesLayer(),
        bannedWindows = bannedWindows ?? <DeviceWindow>[],
        studyBlocks = studyBlocks ?? <ScheduleItem>[];

  /// 新建习惯任务时把 L0 全局默认写进任务（全局默认 5 / 预设 2·5 由此生效）。
  Task createHabitTask({
    required String id,
    required String name,
    required String timeHm,
    List<int>? weekdays,
    String? action,
  }) =>
      Task(
        id: id,
        type: 'habit',
        name: name,
        timeHm: timeHm,
        weekdays: weekdays,
        reminderMode: prefs.global.reminderMode,
        leadMinutes: prefs.global.defaultLeadMinutes,
        action: action,
      );

  /// 提前量：会话级 L0 覆盖优先，否则用任务自身值。
  int leadFor(Task t, {String? sessionId}) {
    final o = sessionId == null
        ? null
        : prefs.overrides[sessionId]?.leadMinutes;
    return o ?? t.leadMinutes;
  }

  /// 习惯任务的下一次执行时刻（含今天；最多向后找 14 天）。
  DateTime nextOccurrence(Task t, DateTime from) {
    if (!t.enabled) throw ValidationError('任务已禁用: ${t.id}');
    final tm = parseHm(t.timeHm);
    final days = t.type == 'once' ? 1 : 15;
    for (var d = 0; d < days; d++) {
      final day = DateTime(from.year, from.month, from.day + d);
      if (!t.weekdays.contains(day.weekday)) continue;
      final cand = DateTime(day.year, day.month, day.day, tm ~/ 60, tm % 60);
      if (!cand.isBefore(from)) return cand;
    }
    throw ValidationError('任务 ${t.id} 在 ${days - 1} 天内无下次执行');
  }

  /// 距下一个任务还有多久（分钟级，省电；无任务返回 -1）。
  int minutesUntilNext(DateTime now) {
    final enabled = tasks.where((t) => t.enabled).toList();
    if (enabled.isEmpty) return -1;
    var best = 1 << 30;
    for (final t in enabled) {
      try {
        final diff = nextOccurrence(t, now).difference(now).inMinutes;
        if (diff < best) best = diff;
      } on ValidationError {
        // 已过期的一次性任务不应让整个倒计时失效
        continue;
      }
    }
    return best == 1 << 30 ? -1 : best;
  }

  /// 最近一个任务（供桌面 Widget 最小态）。
  Task? nextTask(DateTime now) {
    final enabled = tasks.where((t) => t.enabled).toList();
    if (enabled.isEmpty) return null;
    Task? best;
    Duration? bestDiff;
    for (final t in enabled) {
      try {
        final d = nextOccurrence(t, now).difference(now);
        if (bestDiff == null || d < bestDiff) {
          bestDiff = d;
          best = t;
        }
      } on ValidationError {
        continue;
      }
    }
    return best;
  }

  /// 提醒时刻 = 任务时刻 − 提前量（自动跨日）。
  DateTime reminderAt(Task t, DateTime occurrence, {String? sessionId}) =>
      occurrence.subtract(Duration(minutes: leadFor(t, sessionId: sessionId)));

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool isDeviceBanned(DateTime at) {
    final key = _dateKey(at);
    final minute = at.hour * 60 + at.minute;
    for (final w in bannedWindows) {
      if (w.date == key && minute >= w.startMin && minute < w.endMin) {
        return true;
      }
    }
    return false;
  }

  /// 提醒决策：方式「无」或设备禁用时段一律静默（不响不亮屏）。
  ReminderDecision reminderFor(Task t, DateTime occurrence,
      {String? sessionId}) {
    final at = reminderAt(t, occurrence, sessionId: sessionId);
    if (t.reminderMode == 'none') {
      return ReminderDecision(false, 'none', '提醒方式 = 无');
    }
    if (isDeviceBanned(at)) {
      return ReminderDecision(false, 'none', '设备禁用时段自动静默');
    }
    return ReminderDecision(true, t.reminderMode, '按设定提前 ${leadFor(t, sessionId: sessionId)} 分钟提醒');
  }

  /// 一键跳转外部 App 的执行动作；含凭证特征一律拒绝。
  String? launchAction(Task t) {
    final a = t.action;
    if (a == null) return null;
    final lower = a.toLowerCase();
    if (lower.contains('sk-') || lower.contains('api_key') ||
        lower.contains('token') || lower.contains('password')) {
      throw ValidationError('跳转动作不得携带凭证');
    }
    return a;
  }

  /// 今日日程：任务 + 规划学习时段 + 复习时段，同一条线按时间排序。
  List<ScheduleItem> todaySchedule(DateTime day,
      {List<ScheduleItem>? extraBlocks}) {
    final items = <ScheduleItem>[];
    for (final t in tasks.where((x) => x.enabled)) {
      if (!t.weekdays.contains(day.weekday)) continue;
      final start = parseHm(t.timeHm);
      items.add(ScheduleItem(
        id: t.id,
        title: t.name,
        kind: 'task',
        startMin: start,
        endMin: start + 30 <= 1440 ? start + 30 : 1440,
      ));
    }
    for (final b in studyBlocks) {
      items.add(b);
    }
    if (extraBlocks != null) items.addAll(extraBlocks);
    items.sort((a, b) => a.startMin.compareTo(b.startMin));
    return items;
  }
}
