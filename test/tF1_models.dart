/// F1 · 领域模型与学情基线测试（PRD §4 F1 逐条验收）。
/// 单独运行：dart test/tF1_models.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';

typedef FromJson<T> = T Function(Object? json);

void _roundTrip<T extends Entity>(
    Harness h, String label, T entity, FromJson<T> from) {
  h.test('$label · JSON 往返字段零丢失', () {
    h.jsonEq(from(entity.toJson()).toJson(), entity.toJson());
  });
}

void runF1(Harness h) {
  h.group('F1 验收① 全实体 JSON 往返', () {
    _roundTrip(h, 'KnowledgeNode',
        ExamProfile.shenzhen().knowledgeTree, KnowledgeNode.fromJson);
    _roundTrip(h, 'ExamProfile', ExamProfile.shenzhen(), ExamProfile.fromJson);
    _roundTrip(h, 'Task',
        Task(
          id: 'T-0001', type: 'habit', name: '打开不背单词背单词',
          timeHm: '07:30', weekdays: [1, 2, 3, 4, 5],
          reminderMode: 'vibration', leadMinutes: 2,
          action: 'com.bbdc.word', enabled: true,
        ),
        Task.fromJson);
    _roundTrip(h, 'Plan',
        Plan(
          id: 'P-0001', goal: '精进基本不等式，能解决 75% 相关题目',
          quantTarget: 0.75, deadlineDays: 15, startMode: 'immediate',
          slotIds: ['S-T3-1114'], passLine: 0.75,
          status: 'active', createdDate: '2026-11-14',
        ),
        Plan.fromJson);
    _roundTrip(h, 'Session',
        Session(
          id: 'S-0001', planId: 'P-0001', slotId: 'S-T3-1114',
          capacityMinutes: 60, stage: 'quiz', pretestSkipped: true,
          noteVisible: false, quizScore: 0.62,
          sessionIntent: 'follow', sourceMode: 'adaptive',
          attributionIds: ['W-0001'],
        ),
        Session.fromJson);
    _roundTrip(h, 'ReviewPlan',
        ReviewPlan(
          id: 'R-0001', planId: 'P-0001',
          sourceSessionId: 'S-0001', scheduledSlotIds: ['S-T4-1115'],
        ),
        ReviewPlan.fromJson);
    _roundTrip(h, 'Slot',
        Slot(
          id: 'S-T3-1114', date: '2026-11-14',
          startMin: 1040, endMin: 1100, source: 'template',
          deviceAvailable: true, phoneAllowed: true, confirmed: true,
        ),
        Slot.fromJson);
    _roundTrip(h, 'SlotTemplate',
        SlotTemplate(id: 'T3', label: '放学后整块', startMin: 1040, endMin: 1100),
        SlotTemplate.fromJson);
    _roundTrip(h, 'CalendarEntry',
        CalendarEntry(
          id: 'C-0001', date: '2026-11-14', startMin: 480, endMin: 525,
          kind: 'course', title: '数学课', deviceBanned: true,
        ),
        CalendarEntry.fromJson);
    _roundTrip(h, 'SchoolCalendar',
        SchoolCalendar(
          id: 'SC-0001', importedFrom: 'screenshot',
          entries: [
            CalendarEntry(
              id: 'C-0001', date: '2026-11-14', startMin: 480, endMin: 525,
              kind: 'course', title: '数学课',
            ),
            CalendarEntry(
              id: 'C-0002', date: '2026-11-20', startMin: 480, endMin: 720,
              kind: 'activity', title: '校运会', deviceBanned: false,
            ),
          ],
        ),
        SchoolCalendar.fromJson);
    _roundTrip(h, 'WeakPoint',
        WeakPoint(
          id: 'W-0001',
          anchorId: buildAnchorId('RJ-A-BX1-CH2-2.2-EQ', 'S-0001', 'W-0001'),
          knowledgeNodeId: 'RJ-A-BX1-CH2-2.2-EQ',
          axisKnowledge: 'condition', axisGaokao: 'deRoutine',
          axisFeynman: 'fakeUnderstanding', severity: 4,
          evidence: ['第 3 题', '第 7 题', '复述原句：凑积为定值就行'],
          reminderLine: '一正二定三相等，先问等号取不取得到',
        ),
        WeakPoint.fromJson);
    _roundTrip(h, 'ExamReminderCard',
        ExamReminderCard(
          id: 'RC-0001', weakPointId: 'W-0001',
          content: '2.2 基本不等式｜一正 → 二定 → 三相等；坑：先问等号取不取得到',
          badges: ['描边', '▲高', '文字标签'],
        ),
        ExamReminderCard.fromJson);
    _roundTrip(h, 'NoteDocument',
        NoteDocument(
          id: 'N-0001', owner: 'ai', channel: 'D',
          contentType: 'structuredText',
          anchorId: 'RJ-A-BX1-CH2-2.2-EQ::S-0001::W-0001',
          blocks: ['核心：一正·二定·三相等', '等号成立条件'],
          aiGenerated: true,
        ),
        NoteDocument.fromJson);
    _roundTrip(h, 'AnchorLink',
        AnchorLink(
          anchorId: 'RJ-A-BX1-CH2-2.2-EQ::S-0001::W-0001',
          aiNoteIds: ['N-0001'], myNoteIds: ['N-0002', 'N-0003'],
        ),
        AnchorLink.fromJson);
    _roundTrip(h, 'Resource',
        Resource(
          id: 'Q-0001', source: '2026 新高考 I 卷真题',
          textbookTag: '人教A版·必修一·2.2', examTag: '基本不等式',
          yearRegion: '2026·新课标I卷', questionType: '单选',
          score: 5, difficulty: 'medium', parentId: null,
          variantLevel: 'L1', isGaokao: true,
        ),
        Resource.fromJson);
    _roundTrip(h, 'DataPackage',
        DataPackage(
          manifest: {'schemaVersion': 1, 'device': 'vivo S7'},
          entities: {
            'tasks.json': [Task(id: 'T-1', type: 'once', name: 'x',
                timeHm: '09:00', reminderMode: 'none').toJson()],
            'weak_points.json': <Map<String, dynamic>>[],
          },
        ),
        DataPackage.fromJson);
  });

  h.group('F1 验收② 知识点树与坐标体系', () {
    final ep = ExamProfile.shenzhen();
    h.test('可定位到叶子节点「等号成立条件」', () {
      final n = ep.knowledgeTree.find('RJ-A-BX1-CH2-2.2-EQ');
      h.notNull(n);
      h.isTrue(n!.isLeaf);
      h.eq(n.title, '等号成立条件');
    });
    h.test('首个锚点是 2.2 基本不等式，且叶子齐全', () {
      h.notNull(ep.knowledgeTree.find('RJ-A-BX1-CH2-2.2'));
      h.eq(ep.knowledgeTree.leaves.length, 3);
      for (final leaf in ep.knowledgeTree.leaves) {
        h.contains(leaf.id, 'RJ-A-BX1-CH2-2.2');
      }
    });
    h.test('anchorId 由知识点叶子 + 会话 + 薄弱点组成', () {
      final leaf = ep.knowledgeTree.leaves.first;
      h.eq(buildAnchorId(leaf.id, 'S-0001', 'W-0001'),
          '${leaf.id}::S-0001::W-0001');
    });
    h.test('找不到节点返回 null 而不是抛错', () {
      h.isNull(ep.knowledgeTree.find('NO-SUCH-NODE'));
    });
  });

  h.group('F1 验收③ 题型分值与④ 难度分布', () {
    final ep = ExamProfile.shenzhen();
    h.test('题型分值合计 = 150', () => h.eq(ep.totalScore, 150));
    h.test('题型枚举 8/4/4/6', () {
      h.eq(ep.questionTypes.length, 4);
      h.eq(ep.questionTypes[0]['count'], 8);
      h.eq(ep.questionTypes[3]['count'], 6);
    });
    h.test('难度 5:3:2 归一化为 1.0', () {
      h.ok((ep.difficultySum - 1.0).abs() < 1e-9,
          '实际=${ep.difficultySum}');
      h.eq(ep.difficultyRatio['basic'], 0.5);
      h.eq(ep.difficultyRatio['medium'], 0.3);
      h.eq(ep.difficultyRatio['hard'], 0.2);
    });
    h.test('学情基线字段符合深中 / 新高考 I 卷 / 人教 A 版', () {
      h.contains(ep.school, '深圳中学');
      h.contains(ep.paper, '新高考 I 卷');
      h.contains(ep.textbook, '人教 A 版');
      h.contains(ep.examMode, '数学不分文理');
      h.contains(ep.styleTags.join('|'), '去套路化');
      h.contains(ep.styleTags.join('|'), '回归教材');
    });
  });

  h.group('F1 验收⑤ 未知枚举必须报错，不得静默降级', () {
    h.test('Task.type 非法', () => h.throwsValidation(() => Task(
        id: 'x', type: 'weird', name: 'n', timeHm: '07:00',
        reminderMode: 'none')));
    h.test('Task.reminderMode 非法', () => h.throwsValidation(() => Task(
        id: 'x', type: 'habit', name: 'n', timeHm: '07:00',
        reminderMode: 'flash')));
    h.test('Plan.startMode 非法', () => h.throwsValidation(() => Plan(
        id: 'x', goal: 'g', startMode: 'later', createdDate: '2026-11-14')));
    h.test('Session.stage 非法', () => h.throwsValidation(() => Session(
        id: 'x', planId: 'p', slotId: 's', capacityMinutes: 60,
        stage: 'unknown')));
    h.test('Slot.source 非法', () => h.throwsValidation(() => Slot(
        id: 'x', date: '2026-11-14', startMin: 60, endMin: 120,
        source: 'crawler')));
    h.test('NoteDocument.owner 非法', () => h.throwsValidation(() =>
        NoteDocument(id: 'x', owner: 'shared', channel: 'D',
            contentType: 'structuredText', anchorId: 'a')));
    h.test('Resource.difficulty 非法', () => h.throwsValidation(() => Resource(
        id: 'x', source: 's', textbookTag: 't', difficulty: 'impossible')));
    h.test('WeakPoint.axisFeynman 非法', () => h.throwsValidation(() =>
        WeakPoint(
          id: 'x', anchorId: 'a', knowledgeNodeId: 'k',
          axisKnowledge: 'concept', axisGaokao: 'deRoutine',
          axisFeynman: 'vague', severity: 2,
          evidence: ['第 1 题'], reminderLine: 'r')));
    h.test('反序列化里的非法枚举同样被拒', () {
      h.throwsValidation(() => Task.fromJson({
            'id': 'x', 'type': 'weird', 'name': 'n', 'timeHm': '07:00',
            'weekdays': [1], 'reminderMode': 'none',
            'leadMinutes': 2, 'action': null, 'enabled': true,
          }));
    });
  });

  h.group('F1 硬约束（模型层）', () {
    h.test('复习闭环固定模式 2，自定义步骤被拒绝', () {
      h.throwsValidation(() => ReviewPlan(
          id: 'r', planId: 'p', sourceSessionId: 's',
          steps: ['复述', '直接跳过']));
      h.eq(ReviewPlan.fixedSteps.length, 5);
      h.eq(ReviewPlan.fixedSteps.last, '今日新内容');
    });
    h.test('薄弱点无证据被拒绝（排除黑箱自由归因）', () {
      h.throwsValidation(() => WeakPoint(
          id: 'x', anchorId: 'a', knowledgeNodeId: 'k',
          axisKnowledge: 'concept', axisGaokao: 'deRoutine',
          axisFeynman: 'cannotSay', severity: 1,
          evidence: [], reminderLine: '基础不牢'));
    });
    h.test('资源无 source 被拒绝（禁止无来源题）', () {
      h.throwsValidation(() => Resource(
          id: 'x', source: '  ', textbookTag: 't', difficulty: 'basic'));
    });
    h.test('速查卡屏幕态与打印态文本一字不差', () {
      final c = ExamReminderCard(
          id: 'c', weakPointId: 'w', content: '一正二定三相等',
          badges: ['▲高', '描边']);
      h.eq(c.screenText, c.printText);
      h.notNull(c.badges.isEmpty ? null : c.badges,
          '打印态必须有非颜色标记');
      h.isFalse(c.badges.isEmpty);
    });
    h.test('4 个常驻时段合计 140 分钟', () {
      h.eq(SlotTemplate.defaults().length, 4);
      h.eq(SlotTemplate.defaultTotalMinutes, 140);
      h.eq(SlotTemplate.defaults()[2].capacityMinutes, 60);
      h.eq(SlotTemplate.defaults()[3].capacityMinutes, 20);
    });
    h.test('绿色判定 = 空闲 ∧ 设备可用 ∧ 能用手机 ∧ 时长够', () {
      final base = Slot(id: 's', date: '2026-11-14', startMin: 780,
          endMin: 810, source: 'template', confirmed: true);
      h.isTrue(base.isAvailable(20));
      h.isFalse(base.isAvailable(60), '30min 装不下 60min 环节');
      h.isFalse(Slot.fromJson({
        ...base.toJson(), 'deviceAvailable': false,
      }).isAvailable(20), '教学区域禁用');
      h.isFalse(Slot.fromJson({
        ...base.toJson(), 'phoneAllowed': false,
      }).isAvailable(20), '课间不能用手机');
      h.isFalse(Slot.fromJson({
        ...base.toJson(), 'confirmed': false,
      }).isAvailable(20), '当天未确认');
    });
    h.test('DataPackage 实体文件清单为 13 类 + manifest', () {
      h.eq(DataPackage.entityFiles.length, 13);
      h.contains(DataPackage.entityFiles.join('|'), 'exam_profile.json');
      h.contains(DataPackage.entityFiles.join('|'), 'anchor_links.json');
    });
  });
}

void main() {
  final h = Harness();
  runF1(h);
  h.report();
}
