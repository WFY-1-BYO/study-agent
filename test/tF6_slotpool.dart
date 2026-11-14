/// F6 · SlotPool 时段池测试（PRD §4 F6 逐条验收）。
/// 单独运行：dart test/tF6_slotpool.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/slotpool.dart';

const day = '2026-11-14';

Slot _slot(String id, int start, int end,
        {String source = 'custom', bool confirmed = true}) =>
    Slot(
      id: id, date: day, startMin: start, endMin: end,
      source: source, deviceAvailable: true, phoneAllowed: true,
      confirmed: confirmed,
    );

void runF6(Harness h) {
  h.group('F6 验收① 四来源合并、去重、按天确认', () {
    h.test('默认 4 个模板时段全部入池', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      h.eq(p.slots.length, 4);
      h.eq(p.slots.map((s) => s.source).toSet().length, 1);
      h.eq(p.slots.first.source, 'template');
    });
    h.test('四来源合并（课程表 / 校历 / 模板 / 自定义）', () {
      final cal = SchoolCalendar(id: 'SC', importedFrom: 'screenshot', entries: [
        CalendarEntry(id: 'C1', date: day, startMin: 600, endMin: 660,
            kind: 'activity', title: '空档', deviceBanned: false),
      ]);
      final p = SlotPool.forDay(
        day,
        calendar: cal,
        courseTable: [_slot('CT1', 540, 570, source: 'courseTable')],
        custom: [_slot('CU1', 1200, 1230)],
        confirmTemplates: true,
      );
      final sources = p.slots.map((s) => s.source).toSet();
      h.eq(sources.length, 4);
      for (final s in ['courseTable', 'schoolCalendar', 'template', 'custom']) {
        h.isTrue(sources.contains(s), '缺少来源 $s');
      }
    });
    h.test('同一时段按来源优先级去重（custom > schoolCalendar > template）', () {
      final p = SlotPool.forDay(
        day,
        courseTable: [_slot('CT1', 1040, 1100, source: 'courseTable')],
        custom: [_slot('CU1', 1040, 1100)],
        confirmTemplates: true,
      );
      final same = p.slots.where((s) => s.startMin == 1040 && s.endMin == 1100).toList();
      h.eq(same.length, 1, '同一时段只保留一个');
      h.eq(same.first.source, 'custom');
    });
    h.test('未确认的模板不算绿色（按天确认）', () {
      final p = SlotPool.forDay(day, confirmTemplates: false);
      h.eq(p.slots.length, 4);
      h.eq(p.available().length, 0, '未确认时段不可学习');
      final q = SlotPool.forDay(day, confirmTemplates: true);
      h.eq(q.available().length, 4);
    });
    h.test('模板可开关，关闭的不入池', () {
      final tpls = SlotTemplate.defaults();
      final t4 = tpls[3];
      final withDisabled = [
        tpls[0], tpls[1], tpls[2],
        SlotTemplate(
          id: t4.id, label: t4.label, startMin: t4.startMin,
          endMin: t4.endMin, enabled: false, // 关掉晚间 20min
        ),
      ];
      final p = SlotPool.forDay(day, templates: withDisabled, confirmTemplates: true);
      h.eq(p.slots.length, 3);
      h.eq(p.templateCapacity(), 120);
    });
  });

  h.group('F6 验收② 课间与教学区域禁用自动过滤', () {
    h.test('教学区域上课时段与模板重叠 → 该时段失去设备可用', () {
      final cal = SchoolCalendar(id: 'SC', importedFrom: 'screenshot', entries: [
        CalendarEntry(id: 'C1', date: day, startMin: 420, endMin: 450,
            kind: 'course', title: '早读', deviceBanned: true),
      ]);
      final p = SlotPool.forDay(day, calendar: cal, confirmTemplates: true);
      final t1 = p.slots.firstWhere((s) => s.startMin == 420);
      h.isFalse(t1.deviceAvailable);
      h.isFalse(t1.isAvailable(20));
      h.eq(p.available().length, 3, '4 段里被过滤掉 1 段');
    });
    h.test('课间 <10 分钟的短间隙被过滤，不入池', () {
      final p = SlotPool.forDay(day,
          custom: [_slot('BREAK', 500, 505)], confirmTemplates: true);
      h.isFalse(p.slots.any((s) => s.id == 'BREAK'));
    });
    h.test('课间用不了手机 → phoneAllowed=false 的时段不绿色', () {
      final s = Slot.fromJson(<String, dynamic>{
        ..._slot('X', 600, 630).toJson(),
        'phoneAllowed': false,
      });
      final p = SlotPool.forDay(day, custom: [s], confirmTemplates: false);
      final one = p.slots.firstWhere((x) => x.id == 'X');
      h.isFalse(one.isAvailable(20));
      h.eq(p.stageFor(one), 'unusable');
    });
  });

  h.group('F6 验收③ 容量：默认 140 分钟/天', () {
    h.test('4 个常驻时段合计 140 分钟', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      h.eq(p.templateCapacity(), 140);
      h.eq(p.totalCapacity(), 140);
    });
    h.test('容量分布 30 / 30 / 60 / 20', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      h.eq(p.slots.map((s) => s.capacityMinutes).join(','), '30,30,60,20');
    });
  });

  h.group('F6 验收④ 按时段容量匹配学习环节', () {
    h.test('20 / 30min 碎片 → 复习闭环；60min 整块 → 新内容', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      h.eq(p.stageFor(p.slots[0]), 'review'); // 30
      h.eq(p.stageFor(p.slots[1]), 'review'); // 30
      h.eq(p.stageFor(p.slots[2]), 'newContent'); // 60
      h.eq(p.stageFor(p.slots[3]), 'review'); // 20
    });
    h.test('20min 时段只被分配复习，装不下 60min 新内容', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final short = p.slots[3];
      h.isFalse(short.isAvailable(60));
      h.isTrue(short.isAvailable(20));
      h.eq(p.stageFor(short), 'review');
    });
    h.test('planSession 优先整块：需要 60min 选中 17:20–18:20', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final chosen = p.planSession(60);
      h.eq(chosen.length, 1);
      h.eq(chosen.first.capacityMinutes, 60);
      h.eq(chosen.first.startMin, 1040);
    });
    h.test('容量不足时拆分、跨时段续接', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final chosen = p.planSession(90);
      h.isTrue(chosen.length >= 2, '单段装不下 90min，必须跨时段');
      h.isTrue(chosen.fold<int>(0, (s, x) => s + x.capacityMinutes) >= 90);
    });
    h.test('完全无可用时段时明确报错', () {
      final p = SlotPool.forDay(day, confirmTemplates: false);
      h.throwsValidation(() => p.planSession(60));
    });
  });

  h.group('F6 验收⑤ 取消时段后排期重排、无孤儿', () {
    h.test('取消时段后引用被清理并报告孤儿会话', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final block = p.slots[2];
      p.assign('S-1', [block]);
      h.eq(p.assignments['S-1']!.length, 1);
      p.cancel(block.id);
      h.eq(p.slots.length, 3);
      h.eq(p.assignments['S-1']!.length, 0);
      h.contains(p.orphanSessions().join('|'), 'S-1');
    });
    h.test('自动重排孤儿会话到剩余时段', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final block = p.slots[2];
      p.assign('S-1', [block]);
      p.cancel(block.id);
      final done = p.rescheduleOrphans({'S-1': 20});
      h.contains(done.join('|'), 'S-1');
      h.eq(p.orphanSessions().length, 0, '重排后不应留孤儿');
      h.isTrue(p.assignments['S-1']!.isNotEmpty);
    });
    h.test('剩余容量不足时保留孤儿状态，不静默丢弃', () {
      final p = SlotPool.forDay(day, confirmTemplates: true);
      final block = p.slots[2];
      p.assign('S-1', [block]);
      for (final s in List<Slot>.from(p.slots)) {
        if (s.id != block.id) p.cancel(s.id);
      }
      p.cancel(block.id);
      final done = p.rescheduleOrphans({'S-1': 60});
      h.eq(done.length, 0);
      h.contains(p.orphanSessions().join('|'), 'S-1');
    });
  });

  h.group('F6 验收⑥ 重叠时段检测', () {
    h.test('无重叠时返回空', () {
      h.eq(SlotPool.forDay(day, confirmTemplates: true).findOverlaps().length, 0);
    });
    h.test('重叠时段被检出', () {
      final p = SlotPool.forDay(
        day,
        custom: [_slot('A', 900, 960), _slot('B', 930, 990)],
        confirmTemplates: false,
      );
      final overlaps = p.findOverlaps();
      h.isTrue(overlaps.isNotEmpty);
      h.contains(overlaps.first.map((s) => s.id).join('|'), 'A');
    });
    h.test('首尾相接不算重叠', () {
      final p = SlotPool.forDay(
        day,
        custom: [_slot('A', 900, 960), _slot('B', 960, 1020)],
        confirmTemplates: false,
      );
      h.eq(p.findOverlaps().length, 0);
    });
  });

  h.group('F6 验收⑦ 校历活动自动供给临时时段（校运会）', () {
    h.test('活动生成可学习时段且为整块', () {
      final cal = SchoolCalendar(id: 'SC', importedFrom: 'screenshot', entries: [
        CalendarEntry(id: 'SPORT', date: '2026-11-20', startMin: 480, endMin: 720,
            kind: 'activity', title: '校运会', deviceBanned: false),
      ]);
      final p = SlotPool.forDay('2026-11-20', calendar: cal);
      final extra = p.slots.where((s) => s.source == 'schoolCalendar').toList();
      h.eq(extra.length, 1);
      h.eq(extra.first.capacityMinutes, 240);
      h.isTrue(extra.first.confirmed, '校历活动即时生效');
      h.eq(p.stageFor(extra.first), 'newContent');
    });
    h.test('截图导入是一次性批量，非实时同步（不同日期互不影响）', () {
      final cal = SchoolCalendar(id: 'SC', importedFrom: 'screenshot', entries: [
        CalendarEntry(id: 'SPORT', date: '2026-11-20', startMin: 480, endMin: 720,
            kind: 'activity', title: '校运会', deviceBanned: false),
      ]);
      final p = SlotPool.forDay(day, calendar: cal, confirmTemplates: true);
      h.eq(p.slots.where((s) => s.source == 'schoolCalendar').length, 0);
      h.eq(p.slots.length, 4);
    });
  });

  h.group('F6 序列化往返', () {
    h.test('SlotPool JSON 往返无损（含排期与校历）', () {
      final cal = SchoolCalendar(id: 'SC', importedFrom: 'screenshot', entries: [
        CalendarEntry(id: 'C1', date: day, startMin: 420, endMin: 450,
            kind: 'course', title: '早读', deviceBanned: true),
      ]);
      final p = SlotPool.forDay(day, calendar: cal, confirmTemplates: true);
      p.assign('S-1', [p.slots[2]]);
      h.jsonEq(SlotPool.fromJson(p.toJson()).toJson(), p.toJson());
    });
  });
}

void main() {
  final h = Harness();
  runF6(h);
  h.report();
}
