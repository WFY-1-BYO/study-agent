/// F7 · 规划创建测试（PRD §4 F7 逐条验收）。
/// 单独运行：dart test/tF7_plans.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/plans.dart';
import '../lib/preferences.dart';
import '../lib/slotpool.dart';

SlotPool _pool() => SlotPool.forDay('2026-11-14', confirmTemplates: true);

PlanEngine _engine({PreferencesLayer? prefs}) =>
    PlanEngine(pool: _pool(), prefs: prefs);

void runF7(Harness h) {
  h.group('F7 验收① 必填校验', () {
    h.test('目标为空被拒绝', () {
      h.throwsValidation(() => _engine().createPlan(
          id: 'P-1', goal: '  ', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
    });
    h.test('量化指标越界被拒绝', () {
      for (final v in [0.0, -0.1, 1.5]) {
        h.throwsValidation(() => _engine().createPlan(
            id: 'P', goal: '精进', quantTarget: v, startMode: 'immediate',
            slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
      }
    });
    h.test('时间界限 / 通过线非正数被拒绝', () {
      h.throwsValidation(() => _engine().createPlan(
          id: 'P', goal: '精进', deadlineDays: 0, startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
      h.throwsValidation(() => _engine().createPlan(
          id: 'P', goal: '精进', passLine: 0, startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
    });
    h.test('不选时段被拒绝', () {
      h.throwsValidation(() => _engine().createPlan(
          id: 'P', goal: '精进', startMode: 'immediate',
          slotIds: [], createdDate: '2026-11-14'));
    });
    h.test('非法 startMode 被拒绝', () {
      h.throwsValidation(() => _engine().createPlan(
          id: 'P', goal: '精进', startMode: 'later',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
    });
  });

  h.group('F7 验收② startMode 两个选项都可创建', () {
    h.test('立即开始 / 将来开始均成功且字段正确', () {
      final e = _engine();
      final a = e.createPlan(
          id: 'P-1', goal: '精进基本不等式', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      final b = e.createPlan(
          id: 'P-2', goal: '精进数列', startMode: 'scheduled',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      h.eq(a.startMode, 'immediate');
      h.eq(b.startMode, 'scheduled');
      h.eq(e.plans.length, 2);
    });
  });

  h.group('F7 验收③ slots 是引用而非复制，且必须绿色', () {
    h.test('引用池中现存时段时成功', () {
      final e = _engine();
      final p = e.createPlan(
          id: 'P-1', goal: '精进', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      h.eq(p.slotIds.length, 1);
      h.eq(p.slotIds.first, 'T3-2026-11-14');
      h.isTrue(e.pool.slots.any((s) => s.id == p.slotIds.first));
    });
    h.test('引用不存在的时段被拒绝', () {
      h.throwsValidation(() => _engine().createPlan(
          id: 'P', goal: '精进', startMode: 'immediate',
          slotIds: ['NO-SUCH-SLOT'], createdDate: '2026-11-14'));
    });
    h.test('引用未确认 / 非绿色时段被拒绝', () {
      final unconfirmed = SlotPool.forDay('2026-11-14', confirmTemplates: false);
      final e = PlanEngine(pool: unconfirmed);
      h.throwsValidation(() => e.createPlan(
          id: 'P', goal: '精进', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14'));
    });
  });

  h.group('F7 验收④ 立即开始生成首个会话，将来开始不生成', () {
    h.test('立即开始 → 1 个会话，属性与时段对齐', () {
      final e = _engine();
      e.createPlan(
          id: 'P-1', goal: '精进基本不等式', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      h.eq(e.sessions.length, 1);
      final s = e.sessions.first;
      h.eq(s.planId, 'P-1');
      h.eq(s.slotId, 'T3-2026-11-14');
      h.eq(s.capacityMinutes, 60, '60min 整块时段');
      h.eq(s.stage, 'resources');
      h.eq(s.sourceMode, 'adaptive');
    });
    h.test('将来开始 → 不生成会话', () {
      final e = _engine();
      e.createPlan(
          id: 'P-1', goal: '精进', startMode: 'scheduled',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      h.eq(e.sessions.length, 0);
    });
    h.test('会话属性继承 L0（笔记显隐 / 摸底跳过 / 意图）', () {
      final prefs = PreferencesLayer();
      prefs.setOverride('SE-0001', SessionOverrides(
          noteVisible: false, pretestSkipped: true,
          sessionIntent: 'challenge'));
      final e = _engine(prefs: prefs);
      e.createPlan(
          id: 'P-1', goal: '精进', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      final s = e.sessions.first;
      h.isFalse(s.noteVisible);
      h.isTrue(s.pretestSkipped);
      h.eq(s.sessionIntent, 'challenge');
    });
  });

  h.group('F7 验收⑤ 到期按规划目标线收口', () {
    final e = _engine();
    final p = e.createPlan(
        id: 'P-1', goal: '精进基本不等式', quantTarget: 0.75,
        deadlineDays: 15, startMode: 'immediate',
        slotIds: ['T3-2026-11-14'], createdDate: '2026-11-01');

    h.test('15 天期限计算正确', () {
      h.eq(e.deadlineOf(p).month, 11);
      h.eq(e.deadlineOf(p).day, 16);
      h.eq(e.daysRemaining(p, '2026-11-14'), 2);
    });
    h.test('未到期保持 active', () {
      h.isFalse(e.isExpired(p, '2026-11-14'));
      h.eq(e.evaluateAtDeadline(p, 0.9, '2026-11-14'), 'active');
    });
    h.test('到期且整体解决率 ≥75% → achieved', () {
      h.isTrue(e.isExpired(p, '2026-11-16'));
      h.eq(e.evaluateAtDeadline(p, 0.8, '2026-11-16'), 'achieved');
      h.eq(e.evaluateAtDeadline(p, 0.75, '2026-11-16'), 'achieved');
    });
    h.test('到期但整体解决率不足 → expired', () {
      h.eq(e.evaluateAtDeadline(p, 0.62, '2026-11-16'), 'expired');
    });
    h.test('状态可写回规划', () {
      final closed = e.withStatus(p, 'achieved');
      h.eq(closed.status, 'achieved');
      h.eq(closed.quantTarget, p.quantTarget, '其余字段不变');
    });
  });

  h.group('F7 验收⑥ 75% 是双层、两个独立字段', () {
    h.test('passLine 与 quantTarget 可分别设置', () {
      final e = _engine();
      final p = e.createPlan(
          id: 'P-1', goal: '精进', quantTarget: 0.75, passLine: 0.6,
          startMode: 'immediate', slotIds: ['T3-2026-11-14'],
          createdDate: '2026-11-14');
      h.eq(p.quantTarget, 0.75);
      h.eq(p.passLine, 0.6);
    });
    h.test('会话 0.62 通过 ≠ 规划 0.62 达成', () {
      final e = _engine();
      final p = e.createPlan(
          id: 'P-1', goal: '精进', quantTarget: 0.75, passLine: 0.6,
          startMode: 'immediate', slotIds: ['T3-2026-11-14'],
          createdDate: '2026-11-14');
      h.isTrue(e.sessionPassed(0.62, p), '会话达到 0.6 通过线 → 进总结');
      h.isFalse(e.planAchieved(0.62, p), '但整体未达 0.75 目标线');
    });
    h.test('改动通过线不影响目标线判定', () {
      final e = _engine();
      final p = e.createPlan(
          id: 'P-1', goal: '精进', quantTarget: 0.75, passLine: 0.9,
          startMode: 'immediate', slotIds: ['T3-2026-11-14'],
          createdDate: '2026-11-14');
      h.isFalse(e.sessionPassed(0.8, p));
      h.isTrue(e.planAchieved(0.8, p));
    });
  });

  h.group('F7 序列化往返', () {
    h.test('PlanEngine JSON 往返无损', () {
      final e = _engine();
      e.createPlan(
          id: 'P-1', goal: '精进基本不等式', startMode: 'immediate',
          slotIds: ['T3-2026-11-14'], createdDate: '2026-11-14');
      e.createPlan(
          id: 'P-2', goal: '精进数列', startMode: 'scheduled',
          slotIds: ['T1-2026-11-14'], createdDate: '2026-11-14');
      h.jsonEq(PlanEngine.fromJson(e.toJson(), pool: e.pool).toJson(),
          e.toJson());
    });
  });
}

void main() {
  final h = Harness();
  runF7(h);
  h.report();
}
