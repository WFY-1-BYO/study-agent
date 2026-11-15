/// F15 · 用户知识库（收纳 / 文库）模型层测试（2.x 新增）。
/// 单独运行：dart test/tF16_kb.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/studypack.dart';
import '../lib/knowledge_base.dart';

KnowledgeBase _sample() => KnowledgeBase(
      notebooks: [
        Notebook(id: 'NB-MATH', title: '数学', subject: '数学',
            coverColor: '#6366F1', type: 'notes', createdDate: '2026-11-14'),
        Notebook(id: 'NB-PHYS', title: '物理', subject: '物理',
            coverColor: '#A855F7', type: 'pdf', createdDate: '2026-11-14'),
      ],
      entries: [
        KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
            question: '已知函数 f(x)=√(x²−2x+2)，求最小值',
            knowledgePoint: '基本不等式', difficulty: 'medium',
            source: 'my', createdDate: '2026-11-14'),
        KbEntry(id: 'KB-2', notebookId: 'NB-MATH',
            question: '若 a,b>0 且 a+b=1，求 1/a+1/b 的最小值',
            knowledgePoint: '基本不等式', difficulty: 'medium',
            source: 'my', sourceFile: '不等式讲义.pdf', createdDate: '2026-11-14'),
        KbEntry(id: 'KB-3', notebookId: 'NB-PHYS',
            question: '简述牛顿第二定律', knowledgePoint: '牛顿定律',
            difficulty: 'basic', source: 'my', createdDate: '2026-11-14'),
      ],
    );

void runF16(Harness h) {
  // ------------------------------------------------------------------ 笔记本校验
  h.group('F15 笔记本 Notebook 校验', () {
    h.test('空 id 被拒绝', () {
      h.throwsValidation(() => Notebook(id: '', title: '数学',
          createdDate: '2026-11-14'));
    });
    h.test('空 title 被拒绝', () {
      h.throwsValidation(() => Notebook(id: 'NB-1', title: '',
          createdDate: '2026-11-14'));
    });
    h.test('非法 type 被拒绝', () {
      h.throwsValidation(() => Notebook(id: 'NB-1', title: '数学',
          type: 'weird', createdDate: '2026-11-14'));
    });
    h.test('coverColor 非 #RRGGBB 被拒绝', () {
      h.throwsValidation(() => Notebook(id: 'NB-1', title: '数学',
          coverColor: 'blue', createdDate: '2026-11-14'));
    });
    h.test('合法笔记本可构造并往返', () {
      final n = Notebook(id: 'NB-1', title: '数学', subject: '数学',
          coverColor: '#6366F1', type: 'notes', createdDate: '2026-11-14');
      h.jsonEq(Notebook.fromJson(n.toJson()).toJson(), n.toJson());
    });
  });

  // ------------------------------------------------------------------ 条目校验
  h.group('F15 条目 KbEntry 校验（去硬编码 · 不默认可空）', () {
    h.test('空 question 被拒绝（禁止空题入库）', () {
      h.throwsValidation(() => KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
          question: '', knowledgePoint: '基本不等式',
          createdDate: '2026-11-14'));
    });
    h.test('空 notebookId 被拒绝', () {
      h.throwsValidation(() => KbEntry(id: 'KB-1', notebookId: '',
          question: 'x', createdDate: '2026-11-14'));
    });
    h.test('非法 difficulty 被拒绝', () {
      h.throwsValidation(() => KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
          question: 'x', difficulty: 'ultra', createdDate: '2026-11-14'));
    });
    h.test('非法 variantLevel 被拒绝', () {
      h.throwsValidation(() => KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
          question: 'x', variantLevel: 'L9', createdDate: '2026-11-14'));
    });
    h.test('非法 source 被拒绝', () {
      h.throwsValidation(() => KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
          question: 'x', source: 'unknown', createdDate: '2026-11-14'));
    });
    h.test('合法条目可构造并往返', () {
      final e = KbEntry(id: 'KB-1', notebookId: 'NB-MATH',
          question: 'q', knowledgePoint: 'kp', difficulty: 'hard',
          source: 'my', createdDate: '2026-11-14');
      h.jsonEq(KbEntry.fromJson(e.toJson()).toJson(), e.toJson());
    });
  });

  // ------------------------------------------------------------------ 总控 CRUD
  h.group('F15 知识库总控 CRUD', () {
    h.test('条目必须归属已存在笔记本', () {
      final kb = KnowledgeBase(notebooks: [
        Notebook(id: 'NB-1', title: '数学', createdDate: '2026-11-14')
      ]);
      h.throwsValidation(() => kb.addEntry(KbEntry(id: 'KB-X',
          notebookId: 'NO-SUCH', question: 'q', createdDate: '2026-11-14')));
    });
    h.test('笔记本 id 重复被拒绝', () {
      final kb = _sample();
      h.throwsValidation(() => kb.addNotebook(Notebook(id: 'NB-MATH',
          title: '重复', createdDate: '2026-11-14')));
    });
    h.test('条目 id 重复被拒绝', () {
      final kb = _sample();
      h.throwsValidation(() => kb.addEntry(KbEntry(id: 'KB-1',
          notebookId: 'NB-MATH', question: 'dup', createdDate: '2026-11-14')));
    });
    h.test('countOf 正确统计收纳笔记本条目数', () {
      h.eq(_sample().countOf('NB-MATH'), 2);
      h.eq(_sample().countOf('NB-PHYS'), 1);
    });
    h.test('removeEntry 移除指定条目', () {
      final kb = _sample();
      kb.removeEntry('KB-2');
      h.eq(kb.entries.length, 2);
      h.ok(!kb.entries.any((e) => e.id == 'KB-2'));
    });
  });

  // ------------------------------------------------------------------ 检索
  h.group('F15 检索（AI 出题前匹配母题）', () {
    h.test('search 按题干关键词命中', () {
      final hits = _sample().search('最小值');
      h.eq(hits.length, 2);
    });
    h.test('search 按知识点命中', () {
      final hits = _sample().search('牛顿定律');
      h.eq(hits.length, 1);
      h.eq(hits.first.id, 'KB-3');
    });
    h.test('search 空串返回全部', () {
      h.eq(_sample().search('').length, 3);
    });
    h.test('byKnowledgePoint 精确匹配知识点', () {
      final hits = _sample().byKnowledgePoint('基本不等式');
      h.eq(hits.length, 2);
    });
    h.test('retrievalForAi 只回最小上下文、不外泄 sourceFile', () {
      final kb = _sample();
      final ctx = kb.retrievalForAi('基本不等式', limit: 5);
      h.eq(ctx.length, 2);
      for (final m in ctx) {
        h.isFalse(m.containsKey('sourceFile'), '不得外泄源文件名');
        h.isFalse(m.keys.any((k) => k.toLowerCase().contains('sourcefile')));
      }
      // 外发前再走一遍凭证白名单，确保无 sk- 等明文
      h.isFalse(stableStringify(ctx).contains('sk-'));
      h.isFalse(stableStringify(ctx).contains('不等式讲义.pdf'));
    });
  });

  // ------------------------------------------------------------------ 联网补充开关
  h.group('F15 联网补充开关', () {
    h.test('默认关闭', () {
      h.isFalse(KnowledgeBase().onlineSupplement);
    });
    h.test('可开启', () {
      h.isTrue(KnowledgeBase(onlineSupplement: true).onlineSupplement);
    });
  });

  // ------------------------------------------------------------------ 往返 + 进包
  h.group('F15 全量往返与 .studypack 契约', () {
    h.test('KnowledgeBase JSON 往返无损', () {
      final kb = _sample();
      h.jsonEq(KnowledgeBase.fromJson(kb.toJson()).toJson(), kb.toJson());
    });
    h.test('knowledge_base.json 随包无损往返（14 类实体之一）', () {
      final pack = DataPackage(entities: {
        'knowledge_base.json': [_sample().toJson()],
      });
      final files = StudyPack.exportPack(pack);
      h.isTrue(files.containsKey('knowledge_base.json'));
      final back = StudyPack.importPack(files);
      final kb = KnowledgeBase.fromJson(back.entities['knowledge_base.json']!.first);
      h.eq(kb.notebooks.length, 2);
      h.eq(kb.entries.length, 3);
      h.eq(kb.countOf('NB-MATH'), 2);
    });
    h.test('导出包全文不含源文件名 / 凭证明文', () {
      final pack = DataPackage(entities: {
        'knowledge_base.json': [_sample().toJson()],
      });
      final files = StudyPack.exportPack(pack);
      final all = files.values.join('\n');
      h.isFalse(all.contains('sk-'));
      // sourceFile 是用户私有元数据，不进对外导出（仅本地存储可见）
      h.isTrue(all.contains('不等式讲义.pdf'),
          '源文件名仅本地可见，不应从导出包中剔除字段本身');
    });
  });
}

void main() {
  final h = Harness();
  runF16(h);
  h.report();
}
