/// F8 · 学习执行引擎（会话状态机）测试（PRD §4 F8 逐条验收）。
/// 单独运行：dart test/tF8_session.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/session.dart';

Plan _plan({double passLine = 0.75, double quantTarget = 0.75}) => Plan(
      id: 'P-1', goal: '精进基本不等式', quantTarget: quantTarget,
      passLine: passLine, deadlineDays: 15, startMode: 'immediate',
      createdDate: '2026-11-14',
    );

Session _session({
  int capacity = 60,
  bool pretestSkipped = true,
  bool noteVisible = true,
}) =>
    Session(
      id: 'SE-1', planId: 'P-1', slotId: 'T3-2026-11-14',
      capacityMinutes: capacity, pretestSkipped: pretestSkipped,
      noteVisible: noteVisible,
    );

WeakPoint _wp(String id) => WeakPoint(
      id: id, anchorId: 'RJ-A-BX1-CH2-2.2-EQ::SE-1::$id',
      knowledgeNodeId: 'RJ-A-BX1-CH2-2.2-EQ',
      axisKnowledge: 'condition', axisGaokao: 'deRoutine',
      axisFeynman: 'fakeUnderstanding', severity: 4,
      evidence: ['第 3 题', '复述原句：凑积为定值就行'],
      reminderLine: '一正二定三相等，先问等号取不取得到',
    );

NoteDocument _aiNote() => NoteDocument(
      id: 'N-AI', owner: 'ai', channel: 'D',
      contentType: 'structuredText', anchorId: 'a::b::c',
      blocks: ['核心：一正·二定·三相等'], aiGenerated: true,
    );

ReviewPlan _review({String planId = 'P-1'}) => ReviewPlan(
      id: 'R-1', planId: planId, sourceSessionId: 'SE-1',
      scheduledSlotIds: ['T4-2026-11-15'],
    );

void runF8(Harness h) {
  h.group('F8 验收① 全路径可达（含跳过摸底、关闭笔记）', () {
    h.test('达标主路径：资源→学习→测验→总结→AI笔记→复习计划→done', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(resources: ['视频：2.2 基本不等式', '题目：5 道']);
      h.eq(e.stage, 'study', '默认跳过摸底');
      e.addNoteBlock('一正二定三相等');
      e.finishStudy();
      h.eq(e.stage, 'quiz');
      e.submitQuizScore(0.8);
      h.eq(e.stage, 'summary');
      e.addRestatement('我认为 a+b≥2√ab，凑积为定值就行');
      e.aiCorrect('漏了前提，补一句：一正·二定·三相等');
      e.confirmUnderstanding();
      h.eq(e.stage, 'aiNote');
      e.generateAiNote(_aiNote());
      h.eq(e.stage, 'reviewPlan');
      e.generateReviewPlan(_review());
      h.eq(e.stage, 'done');
      h.isTrue(e.isDone);
      h.eq(e.quizAttempts, 1);
    });
    h.test('轨迹完整记录所有关键节点', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start();
      e.finishStudy();
      e.submitQuizScore(0.8);
      e.addRestatement('我的理解');
      e.aiCorrect('纠正');
      e.confirmUnderstanding();
      e.generateAiNote(_aiNote());
      e.generateReviewPlan(_review());
      final t = e.trace.join('|');
      for (final k in ['资源就绪', '视频', '达标', '我复述', 'AI 纠正',
          '理解确认', 'AI 笔记', '复习计划']) {
        h.contains(t, k, '轨迹缺少 $k');
      }
    });
    h.test('关闭内置笔记区不影响学习流程', () {
      final e = SessionEngine(
          plan: _plan(), initial: _session(noteVisible: false));
      h.isFalse(e.noteVisible);
      e.start();
      e.finishStudy();
      e.submitQuizScore(0.8);
      h.eq(e.stage, 'summary');
    });
  });

  h.group('F8 验收② 达标与未达标分支互斥', () {
    h.test('≥通过线 → summary；<通过线 → attribution', () {
      final a = SessionEngine(plan: _plan(), initial: _session());
      a.start(); a.finishStudy(); a.submitQuizScore(0.75);
      h.eq(a.stage, 'summary');
      final b = SessionEngine(plan: _plan(), initial: _session());
      b.start(); b.finishStudy(); b.submitQuizScore(0.62);
      h.eq(b.stage, 'attribution');
    });
    h.test('非法成绩 / 错误阶段被拒绝', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      h.throwsValidation(() => e.finishStudy(), 'resources 阶段不能结束学习');
      e.start(); e.finishStudy();
      h.throwsValidation(() => e.submitQuizScore(1.5));
      h.throwsValidation(() => e.submitQuizScore(-0.1));
    });
  });

  h.group('F8 验收③ 未达标回路：归因 → 费曼 → 再测，循环至通过', () {
    h.test('一次归因回路后回到 quiz，再测达标', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy();
      e.submitQuizScore(0.62); // attribution
      e.attribute(_wp('W-1')); // remediation
      e.addRestatement('我复述我的理解');
      e.aiCorrect('AI 纠正：先问等号取不取得到');
      e.confirmUnderstanding(); // → quiz 再测
      h.eq(e.stage, 'quiz');
      h.contains(e.trace.join('|'), '再测一遍');
      e.submitQuizScore(0.8);
      h.eq(e.stage, 'summary');
      h.eq(e.quizAttempts, 2);
      h.eq(e.weakPoints.length, 1);
    });
    h.test('连续两次未达标可循环，直至通过', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy();
      for (var i = 1; i <= 2; i++) {
        e.submitQuizScore(0.5 + i * 0.05);
        e.attribute(_wp('W-$i'));
        e.addRestatement('第 $i 轮复述');
        e.aiCorrect('第 $i 轮纠正');
        e.confirmUnderstanding();
      }
      h.eq(e.stage, 'quiz');
      h.eq(e.quizAttempts, 2, '两轮归因回路 = 两次测验');
      h.eq(e.weakPoints.length, 2);
      e.submitQuizScore(0.8);
      h.eq(e.quizAttempts, 3, '第三次再测');
      h.eq(e.stage, 'summary');
    });
    h.test('未归因不得直接复述 / 再测', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.4);
      h.throwsValidation(() => e.addRestatement('想跳过归因'));
      h.throwsValidation(() => e.confirmUnderstanding());
    });
  });

  h.group('F8 验收④ 复习计划确实纳入规划', () {
    h.test('生成的复习计划挂到当前 Plan', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.8);
      e.addRestatement('r'); e.aiCorrect('c'); e.confirmUnderstanding();
      e.generateAiNote(_aiNote());
      e.generateReviewPlan(_review());
      h.notNull(e.reviewPlan);
      h.eq(e.reviewPlan!.planId, 'P-1');
      h.eq(e.reviewPlan!.mode, 'fixed2');
    });
    h.test('挂错规划 / 非固定模式被拒绝', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.8);
      e.addRestatement('r'); e.aiCorrect('c'); e.confirmUnderstanding();
      e.generateAiNote(_aiNote());
      h.throwsValidation(() => e.generateReviewPlan(_review(planId: 'P-999')));
      h.eq(e.stage, 'reviewPlan', '失败不改变阶段');
    });
  });

  h.group('F8 验收⑤ 复习闭环固定模式 2，不可配 / 不可跳过', () {
    h.test('固定五步顺序正确', () {
      final e = SessionEngine(plan: _plan(), initial: _session(capacity: 20));
      final steps = e.reviewSteps();
      h.eq(steps.length, 5);
      h.eq(steps[0], '复述上次理解');
      h.eq(steps[1], 'AI 纠正');
      h.eq(steps[3], '几道简单练手题');
      h.eq(steps[4], '今日新内容');
    });
    h.test('skipReview / configureReview 明确报错', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      h.throwsValidation(() => e.skipReview());
      h.throwsValidation(() => e.configureReview('free'));
    });
    h.test('复习默认最小态：只显示 AI 笔记 + 速查卡', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      final v = e.reviewVisibleNotes();
      h.eq(v.length, 2);
      h.contains(v.join('|'), 'aiNote');
      h.contains(v.join('|'), 'examReminderCard');
      h.isFalse(v.contains('myNotes'));
      h.isTrue(e.reviewVisibleNotes(expandMyNotes: true).contains('myNotes'));
    });
  });

  h.group('F8 验收⑥ 必须确认理解才生成 AI 笔记', () {
    h.test('未经历复述-纠正不得确认理解', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.8);
      h.throwsValidation(() => e.confirmUnderstanding());
      e.addRestatement('只复述');
      h.throwsValidation(() => e.confirmUnderstanding(), '缺 AI 纠正');
    });
    h.test('非 aiNote 阶段 / 非 AI 笔记被拒绝', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      h.throwsValidation(() => e.generateAiNote(_aiNote()));
      e.start(); e.finishStudy(); e.submitQuizScore(0.8);
      e.addRestatement('r'); e.aiCorrect('c'); e.confirmUnderstanding();
      h.throwsValidation(() => e.generateAiNote(NoteDocument(
          id: 'N', owner: 'mine', channel: 'D',
          contentType: 'structuredText', anchorId: 'a')));
      h.eq(e.stage, 'aiNote');
    });
  });

  h.group('F8 验收⑦ 会话按容量匹配环节', () {
    h.test('20min 碎片只能跑复习闭环，不能开新内容', () {
      final e = SessionEngine(plan: _plan(), initial: _session(capacity: 20));
      h.isFalse(e.canStartNewContent);
      h.throwsValidation(() => e.start());
      e.startReviewOnly();
      h.eq(e.stage, 'review');
      h.contains(e.trace.join('|'), '复述上次理解');
    });
    h.test('60min 整块可跑完整新内容流程', () {
      final e = SessionEngine(plan: _plan(), initial: _session(capacity: 60));
      h.isTrue(e.canStartNewContent);
      e.start();
      h.eq(e.stage, 'study');
    });
    h.test('30min 碎片同样降级为复习', () {
      final e = SessionEngine(plan: _plan(), initial: _session(capacity: 30));
      h.isFalse(e.canStartNewContent);
    });
  });

  h.group('F8 验收⑧ 双层 75%：状态机只认会话通过线', () {
    h.test('passLine=0.6 时 0.62 达标，但规划目标线仍是 0.75', () {
      final p = _plan(passLine: 0.6, quantTarget: 0.75);
      final e = SessionEngine(plan: p, initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.62);
      h.eq(e.stage, 'summary', '会话达通过线');
      h.eq(e.plan.quantTarget, 0.75, '规划目标线不因此改变');
      h.eq(e.plan.passLine, 0.6);
    });
  });

  h.group('F8 验收⑨⑩⑪ 摸底 / 笔记显隐 / AI 降级', () {
    h.test('摸底测验存在但可跳过，也可完成', () {
      final a = SessionEngine(
          plan: _plan(), initial: _session(pretestSkipped: false));
      a.start();
      h.eq(a.stage, 'pretest');
      a.skipPretest();
      h.eq(a.stage, 'study');
      h.isTrue(a.pretestSkipped);
      final b = SessionEngine(
          plan: _plan(), initial: _session(pretestSkipped: false));
      b.start();
      b.completePretest();
      h.eq(b.stage, 'study');
      h.isFalse(b.pretestSkipped);
    });
    h.test('隐藏笔记区不删除已记内容', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start();
      e.addNoteBlock('边看边记：弦图引入');
      e.toggleNote(false);
      h.isFalse(e.noteVisible);
      h.eq(e.noteBlocks.length, 1, '显隐只影响渲染');
      e.addNoteBlock('隐藏状态下仍可写入');
      h.eq(e.noteBlocks.length, 2);
    });
    h.test('AI 未就绪标待处理，但不阻塞学习与测验', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(aiReady: false);
      h.isTrue(e.aiPending);
      h.contains(e.trace.join('|'), '待处理');
      e.finishStudy();
      e.submitQuizScore(0.8);
      h.eq(e.stage, 'summary', '无 AI 也能走非 AI 环节');
    });
  });

  h.group('F8 序列化', () {
    h.test('toJson 含完整状态，currentSession 可落入 sessions.json', () {
      final e = SessionEngine(plan: _plan(), initial: _session());
      e.start(); e.finishStudy(); e.submitQuizScore(0.62);
      e.attribute(_wp('W-1'));
      final j = e.toJson();
      h.eq(j['stage'], 'remediation');
      h.eq((j['quizScores'] as List).length, 1);
      h.eq((j['weakPoints'] as List).length, 1);
      final s = e.currentSession();
      h.eq(s.stage, 'remediation');
      h.eq(s.quizScore, 0.62);
      h.eq(s.attributionIds.length, 1);
      h.eq(s.planId, 'P-1');
    });
  });
}

void main() {
  final h = Harness();
  runF8(h);
  h.report();
}
