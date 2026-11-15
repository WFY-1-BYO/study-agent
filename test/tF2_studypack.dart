/// F2 · .studypack 全量导入导出测试（PRD §4 F2 逐条验收）。
/// 单独运行：dart test/tF2_studypack.dart
import 'dart:convert';

import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/studypack.dart';
import '../lib/knowledge_base.dart';

DataPackage _fullPack() => DataPackage(
      entities: {
        'preferences.json': [
          {'defaultLeadMinutes': 2, 'presets': [2, 5]}
        ],
        'exam_profile.json': [ExamProfile.shenzhen().toJson()],
        'school_calendar.json': [
          SchoolCalendar(id: 'SC-1', importedFrom: 'screenshot', entries: [
            CalendarEntry(
                id: 'C-1', date: '2026-11-20', startMin: 480, endMin: 720,
                kind: 'activity', title: '校运会', deviceBanned: false)
          ]).toJson()
        ],
        'slot_pool.json': [
          Slot(id: 'S-1', date: '2026-11-14', startMin: 1040, endMin: 1100,
              source: 'template', confirmed: true).toJson(),
          SlotTemplate.defaults().first.toJson(),
        ],
        'tasks.json': [
          Task(id: 'T-1', type: 'habit', name: '打开不背单词背单词',
              timeHm: '07:30', reminderMode: 'vibration', leadMinutes: 2,
              action: 'com.bbdc.word').toJson()
        ],
        'plans.json': [
          Plan(id: 'P-1', goal: '精进基本不等式', quantTarget: 0.75,
              deadlineDays: 15, startMode: 'immediate', slotIds: ['S-1'],
              createdDate: '2026-11-14').toJson()
        ],
        'sessions.json': [
          Session(id: 'SE-1', planId: 'P-1', slotId: 'S-1',
              capacityMinutes: 60, stage: 'quiz', quizScore: 0.62).toJson()
        ],
        'weak_points.json': [
          WeakPoint(
              id: 'W-1', anchorId: 'RJ-A-BX1-CH2-2.2-EQ::SE-1::W-1',
              knowledgeNodeId: 'RJ-A-BX1-CH2-2.2-EQ',
              axisKnowledge: 'condition', axisGaokao: 'deRoutine',
              axisFeynman: 'fakeUnderstanding', severity: 4,
              evidence: ['第 3 题', '复述原句：凑积为定值就行'],
              reminderLine: '一正二定三相等，先问等号取不取得到').toJson()
        ],
        'review.json': [
          ReviewPlan(id: 'R-1', planId: 'P-1', sourceSessionId: 'SE-1').toJson()
        ],
        'ai_notes.json': [
          NoteDocument(id: 'N-1', owner: 'ai', channel: 'D',
              contentType: 'structuredText', anchorId: 'a::b::c',
              blocks: ['核心：一正·二定·三相等'], aiGenerated: true).toJson()
        ],
        'my_notes.json': [
          NoteDocument(id: 'N-2', owner: 'mine', channel: 'C',
              contentType: 'pdf', anchorId: 'a::b::c',
              blocks: ['手写批注归档']).toJson()
        ],
        'anchor_links.json': [
          AnchorLink(anchorId: 'a::b::c', aiNoteIds: ['N-1'],
              myNoteIds: ['N-2']).toJson()
        ],
        'resources.json': [
          Resource(id: 'Q-1', source: '2026 新高考 I 卷真题',
              textbookTag: '人教A版·必修一·2.2', difficulty: 'medium',
              isGaokao: true).toJson()
        ],
        'knowledge_base.json': [
          KnowledgeBase(
            notebooks: [
              Notebook(id: 'NB-1', title: '数学', subject: '数学',
                  coverColor: '#6366F1', type: 'notes',
                  createdDate: '2026-11-14'),
            ],
            entries: [
              KbEntry(id: 'KB-1', notebookId: 'NB-1',
                  question: '已知函数 f(x)=√(x²−2x+2)，求最小值',
                  knowledgePoint: '基本不等式', difficulty: 'medium',
                  source: 'my', createdDate: '2026-11-14'),
            ],
          ).toJson()
        ],
      },
    );

void runF2(Harness h) {
  h.group('F2 验收① 导出→导入 全实体逐字段一致', () {
    h.test('13 类实体全部无损', () {
      final original = _fullPack();
      final files = StudyPack.exportPack(original, device: 'vivo S7');
      final restored = StudyPack.importPack(files);
      h.jsonEq(restored.entities, original.entities);
      h.eq(restored.entities.length, 14);
    });
    h.test('固定格式：13 个实体文件 + manifest 全部存在', () {
      final files = StudyPack.exportPack(_fullPack());
      for (final name in DataPackage.entityFiles) {
        h.isTrue(files.containsKey(name), '缺少 $name');
      }
      h.isTrue(files.containsKey('manifest.json'));
      h.eq(files.length, 15);
    });
    h.test('manifest 自描述字段齐全且不加密', () {
      final files = StudyPack.exportPack(_fullPack(), device: 'Lenovo Y900');
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      h.eq(m['schemaVersion'], StudyPack.schemaVersion);
      h.eq(m['format'], 'studypack-open-v1');
      h.eq(m['encrypted'], false);
      h.eq(m['device'], 'Lenovo Y900');
      h.eq((m['entityFiles'] as List).length, 14);
      h.eq(m['fileCount'], 15);
      h.notNull(m['checksum']);
      h.notNull(m['exportedAt']);
    });
  });

  h.group('F2 验收② 篡改 / 缺文件 / 版本', () {
    h.test('篡改任一实体文件后校验失败', () {
      final files = StudyPack.exportPack(_fullPack());
      files['tasks.json'] = '[]';
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('篡改 assets 同样导致校验失败', () {
      final files = StudyPack.exportPack(_fullPack(),
          assets: {'assets/ink/n1.svg': '<svg>笔迹</svg>'});
      files['assets/ink/n1.svg'] = '<svg>被改</svg>';
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('篡改 manifest 里的 checksum 被拒', () {
      final files = StudyPack.exportPack(_fullPack());
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      m['checksum'] = 'deadbeef';
      files['manifest.json'] = jsonEncode(m);
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('缺少 manifest.json 被拒绝', () {
      final files = StudyPack.exportPack(_fullPack());
      files.remove('manifest.json');
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('缺少必填 manifest 字段被拒绝', () {
      final files = StudyPack.exportPack(_fullPack());
      files['manifest.json'] = jsonEncode({'schemaVersion': 1});
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('未来 schemaVersion 被拒绝', () {
      final files = StudyPack.exportPack(_fullPack());
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      m['schemaVersion'] = 99;
      files['manifest.json'] = jsonEncode(m);
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('旧 schemaVersion 可导入并标记迁移', () {
      final files = StudyPack.exportPack(_fullPack());
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      m['schemaVersion'] = 0;
      files['manifest.json'] = jsonEncode(m);
      final p = StudyPack.importPack(files);
      h.isTrue(StudyPack.isMigrated(p));
      h.jsonEq(p.entities, _fullPack().entities);
    });
    h.test('未知 format 被拒绝', () {
      final files = StudyPack.exportPack(_fullPack());
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      m['format'] = 'other-format';
      files['manifest.json'] = jsonEncode(m);
      h.throwsValidation(() => StudyPack.importPack(files));
    });
  });

  h.group('F2 验收③④⑤ 凭证 / 版权 / 空包', () {
    h.test('含 api_key 字段的输入被拒绝进包', () {
      final p = _fullPack();
      p.entities['tasks.json']!.add({'api_key': 'sk-abcdef'});
      h.throwsValidation(() => StudyPack.exportPack(p));
    });
    h.test('含 sk- 明文的值被拒绝进包', () {
      final p = _fullPack();
      p.entities['ai_notes.json']!.add({'note': 'sk-1234567890'});
      h.throwsValidation(() => StudyPack.exportPack(p));
    });
    h.test('含第三方二进制内容被拒绝进包', () {
      final p = _fullPack();
      p.entities['resources.json']!.add({
        'id': 'Q-2', 'source': 'bilibili BVxxx',
        'videoBinary': 'AAAA...', 'textbookTag': '', 'difficulty': 'basic'
      });
      h.throwsValidation(() => StudyPack.exportPack(p));
    });
    h.test('导入时若包内被注入凭证，同样拒绝', () {
      final files = StudyPack.exportPack(_fullPack());
      files['tasks.json'] = jsonEncode([
        {'id': 'x', 'apiKey': 'sk-injected'}
      ]);
      // 重算 checksum 模拟「格式合法但内容违规」
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      m['checksum'] = StudyPack.computeChecksum(files);
      files['manifest.json'] = jsonEncode(m);
      h.throwsValidation(() => StudyPack.importPack(files));
    });
    h.test('合法导出包全文不含凭证片段', () {
      final files = StudyPack.exportPack(_fullPack());
      final all = files.values.join('\n');
      h.isFalse(all.contains('sk-'), '不应出现 sk- 明文');
      h.isFalse(all.toLowerCase().contains('api_key'));
      h.isFalse(all.toLowerCase().contains('password'));
    });
    h.test('空包可用', () {
      final files = StudyPack.exportPack(DataPackage());
      final p = StudyPack.importPack(files);
      h.eq(p.entities.length, 14);
      for (final list in p.entities.values) {
        h.eq(list.length, 0);
      }
    });
    h.test('单实体包可用，其余补空数组', () {
      final files = StudyPack.exportPack(DataPackage(entities: {
        'tasks.json': [
          Task(id: 'T-1', type: 'once', name: '交作业', timeHm: '21:00',
              reminderMode: 'none').toJson()
        ]
      }));
      final p = StudyPack.importPack(files);
      h.eq(p.entities['tasks.json']!.length, 1);
      h.eq(p.entities['plans.json']!.length, 0);
    });
  });

  h.group('F2 验收⑥⑩⑪⑫ 跨设备 / assets / 稳定 / 幂等', () {
    h.test('跨设备导入结果一致（不对设备做假设）', () {
      final a = StudyPack.importPack(
          StudyPack.exportPack(_fullPack(), device: 'vivo S7'));
      final b = StudyPack.importPack(
          StudyPack.exportPack(_fullPack(), device: 'Lenovo Y900'));
      h.jsonEq(a.entities, b.entities);
    });
    h.test('assets 随包带走且内容一致', () {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0"/></svg>';
      final files = StudyPack.exportPack(_fullPack(),
          assets: {'assets/ink/n1.svg': svg});
      h.eq(files['assets/ink/n1.svg'], svg);
      final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      h.contains((m['assetFiles'] as List).join('|'), 'assets/ink/n1.svg');
      h.eq(m['fileCount'], 16);
      h.isTrue(StudyPack.importPack(files).entities.length == 14);
    });
    h.test('checksum 稳定：同样内容两次导出相同', () {
      final a = StudyPack.exportPack(_fullPack(), exportedAt: 'T1');
      final b = StudyPack.exportPack(_fullPack(), exportedAt: 'T2');
      h.eq(StudyPack.computeChecksum(a), StudyPack.computeChecksum(b));
      h.eq(
          (jsonDecode(a['manifest.json']!) as Map)['checksum'],
          (jsonDecode(b['manifest.json']!) as Map)['checksum']);
    });
    h.test('幂等：导入→再导出→再导入，实体一致', () {
      final files1 = StudyPack.exportPack(_fullPack());
      final p1 = StudyPack.importPack(files1);
      final files2 = StudyPack.exportPack(p1);
      final p2 = StudyPack.importPack(files2);
      h.jsonEq(p2.entities, p1.entities);
    });
  });
}

void main() {
  final h = Harness();
  runF2(h);
  h.report();
}
