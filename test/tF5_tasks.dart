/// F5 · 任务与提醒测试（PRD §4 F5 逐条验收）。
/// 单独运行：dart test/tF5_tasks.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/preferences.dart';
import '../lib/tasks.dart';

Task _habit({
  String id = 'T-1',
  String timeHm = '07:30',
  List<int>? weekdays,
  String reminderMode = 'vibration',
  int leadMinutes = 2,
  String? action,
  bool enabled = true,
}) =>
    Task(
      id: id, type: 'habit', name: '打开不背单词背单词', timeHm: timeHm,
      weekdays: weekdays, reminderMode: reminderMode,
      leadMinutes: leadMinutes, action: action, enabled: enabled,
    );

// 2026-11-14 是周六（weekday=6），11-16 是周一（1）。
final saturday = DateTime(2026, 11, 14, 7, 0);

void runF5(Harness h) {
  h.group('F5 验收① 习惯任务按周期生成下一次', () {
    h.test('当天时间未到 → 返回今天', () {
      final e = TaskEngine(tasks: [_habit(timeHm: '07:30')]);
      final n = e.nextOccurrence(e.tasks.first, saturday);
      h.eq(n.year, 2026);
      h.eq(n.month, 11);
      h.eq(n.day, 14);
      h.eq(n.hour, 7);
      h.eq(n.minute, 30);
    });
    h.test('当天时间已过 → 跳到下一个匹配工作日', () {
      final t = _habit(timeHm: '07:30', weekdays: [1, 2, 3, 4, 5]);
      final e = TaskEngine(tasks: [t]);
      final n = e.nextOccurrence(t, DateTime(2026, 11, 16, 8, 0)); // 周一 08:00 已过
      h.eq(n.weekday, DateTime.tuesday, '应跳到周二');
      h.eq(n.hour, 7);
    });
    h.test('周末无课时 → 顺延到周一', () {
      final t = _habit(timeHm: '07:30', weekdays: [1, 2, 3, 4, 5]);
      final e = TaskEngine(tasks: [t]);
      final n = e.nextOccurrence(t, saturday); // 周六
      h.eq(n.weekday, DateTime.monday);
      h.eq(n.day, 16);
    });
    h.test('一次性任务当天已过不产生下次，且不让倒计时崩溃', () {
      final once = Task(
          id: 'T-9', type: 'once', name: '交作业', timeHm: '06:00',
          reminderMode: 'none');
      final e = TaskEngine(tasks: [once]);
      h.throwsValidation(() => e.nextOccurrence(once, saturday));
      h.eq(e.minutesUntilNext(saturday), -1);
      h.isNull(e.nextTask(saturday));
    });
    h.test('禁用任务被排除', () {
      final e = TaskEngine(tasks: [_habit(enabled: false)]);
      h.eq(e.minutesUntilNext(saturday), -1);
    });
  });

  h.group('F5 验收② 倒计时边界（同刻 / 跨日 / 跨零）', () {
    h.test('同刻 = 0 分钟', () {
      final e = TaskEngine(tasks: [_habit(timeHm: '07:00')]);
      h.eq(e.minutesUntilNext(saturday), 0);
    });
    h.test('当天晚些时候 = 30 分钟', () {
      final e = TaskEngine(tasks: [_habit(timeHm: '07:30')]);
      h.eq(e.minutesUntilNext(saturday), 30);
    });
    h.test('跨日 = 1440 分钟', () {
      final e = TaskEngine(tasks: [_habit(timeHm: '07:00', weekdays: [7])]);
      // 周六 07:00 → 周日 07:00
      h.eq(e.minutesUntilNext(saturday), 1440);
    });
    h.test('跨零：23:59 到次日 00:01 = 2 分钟', () {
      final e = TaskEngine(tasks: [_habit(timeHm: '00:01', weekdays: [7])]);
      final now = DateTime(2026, 11, 14, 23, 59); // 周六深夜
      h.eq(e.minutesUntilNext(now), 2);
    });
    h.test('多个任务取最近一个', () {
      final e = TaskEngine(tasks: [
        _habit(id: 'A', timeHm: '07:30'),
        _habit(id: 'B', timeHm: '08:00'),
        _habit(id: 'C', timeHm: '21:30'),
      ]);
      h.eq(e.minutesUntilNext(saturday), 30);
      h.eq(e.nextTask(saturday)!.id, 'A', 'Widget 最小态显示最近任务');
    });
    h.test('无任务返回 -1', () {
      h.eq(TaskEngine().minutesUntilNext(saturday), -1);
      h.isNull(TaskEngine().nextTask(saturday));
    });
  });

  h.group('F5 验收③ 提醒时刻 = 任务时刻 − 提前量', () {
    h.test('默认提前 2 分钟', () {
      final t = _habit(timeHm: '07:30', leadMinutes: 2);
      final e = TaskEngine(tasks: [t]);
      final occ = e.nextOccurrence(t, saturday);
      final at = e.reminderAt(t, occ);
      h.eq(at.hour, 7);
      h.eq(at.minute, 28);
    });
    h.test('提前量自动跨日（00:01 的任务提前 5 分钟）', () {
      final t = _habit(timeHm: '00:01', leadMinutes: 5);
      final e = TaskEngine(tasks: [t]);
      final occ = DateTime(2026, 11, 15, 0, 1);
      final at = e.reminderAt(t, occ);
      h.eq(at.day, 14);
      h.eq(at.hour, 23);
      h.eq(at.minute, 56);
    });
    h.test('建规划时 L0 覆盖提前量为 5 / 自定义 15', () {
      final prefs = PreferencesLayer();
      prefs.setOverride('S-1', SessionOverrides(leadMinutes: 5));
      prefs.setOverride('S-2', SessionOverrides(leadMinutes: 15));
      final t = _habit(timeHm: '07:30', leadMinutes: 2);
      final e = TaskEngine(tasks: [t], prefs: prefs);
      final occ = e.nextOccurrence(t, saturday);
      h.eq(e.reminderAt(t, occ).minute, 28, '无覆盖用任务自身值');
      h.eq(e.reminderAt(t, occ, sessionId: 'S-1').minute, 25);
      h.eq(e.reminderAt(t, occ, sessionId: 'S-2').minute, 15);
    });
    h.test('全局默认 5 分钟写入新建习惯任务', () {
      final prefs = PreferencesLayer();
      prefs.global.defaultLeadMinutes = 5;
      final e = TaskEngine(prefs: prefs);
      final t = e.createHabitTask(id: 'T-2', name: '背单词', timeHm: '07:30');
      h.eq(t.leadMinutes, 5);
      h.eq(t.reminderMode, prefs.global.reminderMode);
      h.eq(t.type, 'habit');
    });
  });

  h.group('F5 验收④ 「无」与设备禁用时段不产生提醒', () {
    h.test('提醒方式 = 无 → 静默', () {
      final t = _habit(reminderMode: 'none');
      final e = TaskEngine(tasks: [t]);
      final occ = e.nextOccurrence(t, saturday);
      final d = e.reminderFor(t, occ);
      h.isTrue(d.silent);
      h.eq(d.mode, 'none');
      h.contains(d.reason, '无');
    });
    h.test('提醒时刻落在教学区域禁用窗口 → 静默', () {
      final t = _habit(timeHm: '07:30', leadMinutes: 2);
      final banned = DeviceWindow(
          date: '2026-11-14', startMin: 445, endMin: 450,
          label: '早读（教学区域禁用电子设备）'); // 07:25–07:30
      final e = TaskEngine(tasks: [t], bannedWindows: [banned]);
      final occ = e.nextOccurrence(t, saturday); // 07:30
      h.isTrue(e.isDeviceBanned(e.reminderAt(t, occ)));
      final d = e.reminderFor(t, occ);
      h.isTrue(d.silent);
      h.contains(d.reason, '禁用');
    });
    h.test('禁用窗口之外正常按设定提醒', () {
      final t = _habit(timeHm: '07:30', leadMinutes: 2,
          reminderMode: 'sound');
      final banned = DeviceWindow(
          date: '2026-11-14', startMin: 480, endMin: 525, label: '数学课');
      final e = TaskEngine(tasks: [t], bannedWindows: [banned]);
      final d = e.reminderFor(t, e.nextOccurrence(t, saturday));
      h.isTrue(d.active);
      h.eq(d.mode, 'sound');
      h.isFalse(d.silent);
    });
    h.test('校历条目可转成禁用窗口', () {
      final w = DeviceWindow.fromCalendarEntry(CalendarEntry(
          id: 'C-1', date: '2026-11-14', startMin: 480, endMin: 525,
          kind: 'course', title: '数学课'));
      h.eq(w.label, '数学课');
      h.eq(w.startMin, 480);
      h.isTrue(TaskEngine(bannedWindows: [w])
          .isDeviceBanned(DateTime(2026, 11, 14, 8, 10)));
      h.isFalse(TaskEngine(bannedWindows: [w])
          .isDeviceBanned(DateTime(2026, 11, 14, 7, 10)));
    });
  });

  h.group('F5 验收⑤ 一键跳转动作', () {
    h.test('合法跳转动作可返回并可序列化', () {
      final t = _habit(action: 'com.bbdc.word');
      final e = TaskEngine(tasks: [t]);
      h.eq(e.launchAction(t), 'com.bbdc.word');
      h.eq(t.toJson()['action'], 'com.bbdc.word');
    });
    h.test('无跳转动作返回 null', () {
      h.isNull(TaskEngine(tasks: [_habit()]).launchAction(_habit()));
    });
    h.test('动作里含凭证被拒绝', () {
      for (final bad in ['sk-abc', 'api_key=xx', 'token=xx', 'password=1']) {
        final t = _habit(action: bad);
        h.throwsValidation(() => TaskEngine(tasks: [t]).launchAction(t));
      }
    });
  });

  h.group('F5 验收⑥ 规划学习时段写回今日日程', () {
    h.test('任务 / 规划学习 / 复习同在一条时间线', () {
      final study = ScheduleItem(
          id: 'S-1', title: '基本不等式 · 60min 新内容', kind: 'study',
          startMin: 1040, endMin: 1100);
      final review = ScheduleItem(
          id: 'R-1', title: '复习闭环（碎片 20min）', kind: 'review',
          startMin: 1290, endMin: 1310);
      final e = TaskEngine(
        tasks: [
          _habit(id: 'T-1', timeHm: '07:30'),
          _habit(id: 'T-2', timeHm: '21:30'),
        ],
        studyBlocks: [study],
      );
      final list = e.todaySchedule(saturday, extraBlocks: [review]);
      h.eq(list.length, 4);
      h.eq(list.first.id, 'T-1', '按时间排序');
      h.eq(list.last.startMin, 1290);
      h.contains(list.map((x) => x.kind).join('|'), 'study');
      h.contains(list.map((x) => x.kind).join('|'), 'review');
      h.contains(list.map((x) => x.title).join('|'), '基本不等式');
    });
    h.test('非当天任务不出现在今日日程', () {
      final e = TaskEngine(
          tasks: [_habit(timeHm: '07:30', weekdays: [1, 2, 3, 4, 5])]);
      h.eq(e.todaySchedule(saturday).length, 0, '周六无工作日任务');
    });
    h.test('ScheduleItem 往返无损', () {
      final s = ScheduleItem(
          id: 'S-1', title: '会话', kind: 'study',
          startMin: 1040, endMin: 1100);
      h.jsonEq(ScheduleItem.fromJson(s.toJson()).toJson(), s.toJson());
    });
  });
}

void main() {
  final h = Harness();
  runF5(h);
  h.report();
}
