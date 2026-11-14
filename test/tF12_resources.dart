/// F12 · 资源适配器与高考对齐约束测试（PRD §4 F12 六条验收逐条 + 硬约束）。
/// 单独运行：dart test/tF12_resources.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/resources.dart';
import '../lib/studypack.dart';
import '../lib/variants.dart';

const leaf = 'RJ-A-BX1-CH2-2.2-EQ';
const branch = 'RJ-A-BX1-CH2-2.2';

ResourceAdapter _adapter() => ResourceAdapter();

Resource _ingest(
  ResourceAdapter a, {
  String id = 'R-1',
  String channel = 'local',
  String tier = SourceTier.own,
  String source = '我的资料·基本不等式讲义.pdf',
  String uri = 'file:///storage/notes/ineq.pdf',
  String examTag = leaf,
  String? textbookTag,
  String yearRegion = '',
  String questionType = '',
  int score = 0,
  String difficulty = 'medium',
  String variantLevel = 'L1',
  bool isGaokao = false,
  String? parentId,
  String title = '基本不等式讲义',
  String? bv,
  int? durationSeconds,
  String? provider,
}) =>
    a.ingest(
      id: id,
      channel: channel,
      tier: tier,
      source: source,
      uri: uri,
      examTag: examTag,
      textbookTag: textbookTag,
      yearRegion: yearRegion,
      questionType: questionType,
      score: score,
      difficulty: difficulty,
      variantLevel: variantLevel,
      isGaokao: isGaokao,
      parentId: parentId,
      title: title,
      bv: bv,
      durationSeconds: durationSeconds,
      provider: provider,
    );

Resource _bili(ResourceAdapter a, {String id = 'R-B'}) => _ingest(
      a,
      id: id,
      channel: 'ref',
      tier: SourceTier.bilibili,
      source: 'B站·基本不等式精讲',
      uri: 'https://www.bilibili.com/video/BV1xx411c7mD',
      bv: 'BV1xx411c7mD',
      durationSeconds: 720,
      title: '基本不等式精讲',
    );

void runF12(Harness h) {
  // ------------------------------------------------------------------ 验收①
  h.group('F12 验收① 缺 source 的资源被拒绝', () {
    h.test('ingest 空 source 被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(), source: ''));
    });

    h.test('ingest 纯空白 source 被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(), source: '   '));
    });

    h.test('模型层直接构造空 source 也被拒绝', () {
      h.throwsValidation(() => Resource(
          id: 'X',
          source: '',
          textbookTag: '人教 A 版（2019 新版）',
          examTag: leaf,
          difficulty: 'medium'));
    });

    h.test('合法 source 正常登记并保留', () {
      final r = _ingest(_adapter(), source: '2024 深圳中学月考试卷');
      h.eq(r.source, '2024 深圳中学月考试卷');
    });

    h.test('变式题继承母题 source，不会因继承而变空', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      final v = a.attachVariant(motherId: 'R-1');
      h.eq(v.source, '我的资料·基本不等式讲义.pdf');
      h.ok(v.source.trim().isNotEmpty);
    });
  });

  // ------------------------------------------------------------------ 验收②
  h.group('F12 验收② 无来源题不得标记为「高考题」', () {
    h.test('B站视频标 isGaokao=true 被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          channel: 'ref',
          tier: SourceTier.bilibili,
          bv: 'BV1',
          uri: 'https://www.bilibili.com/video/BV1',
          isGaokao: true,
          yearRegion: '2024·广东'));
    });

    h.test('AI 生成资源标 isGaokao=true 被拒绝（禁止冒充）', () {
      h.throwsValidation(() => _ingest(_adapter(),
          tier: SourceTier.aiGenerated,
          isGaokao: true,
          yearRegion: '2024·广东'));
    });

    h.test('高考真题缺年份地区被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/1',
          isGaokao: true));
    });

    h.test('带 parentId 的变式不得标为高考真题', () {
      h.throwsValidation(() => _ingest(_adapter(),
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/1',
          isGaokao: true,
          yearRegion: '2024·广东',
          parentId: 'R-1'));
    });

    h.test('合法真题：权威题库 + 年份地区 + 无 parentId', () {
      final r = _ingest(_adapter(),
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/2024gd',
          isGaokao: true,
          yearRegion: '2024·广东',
          questionType: '单选',
          score: 5);
      h.isTrue(r.isGaokao);
      h.eq(r.yearRegion, '2024·广东');
      h.isNull(r.parentId);
    });

    h.test('B站资源天然不是真题、不带题型分值', () {
      final r = _bili(_adapter());
      h.isFalse(r.isGaokao);
      h.eq(r.questionType, '');
      h.eq(r.score, 0);
    });
  });

  // ------------------------------------------------------------------ 验收③
  h.group('F12 验收③ 变式题必有 parentId', () {
    h.test('无 parentId 的变式被拒绝', () {
      h.throwsValidation(() => _adapter().assertValidVariant(Resource(
          id: 'V0',
          source: 'x',
          textbookTag: '人教 A 版（2019 新版）',
          examTag: leaf,
          difficulty: 'medium',
          variantLevel: 'L2')));
    });

    h.test('parentId 指向不存在母题被拒绝', () {
      h.throwsValidation(() => _adapter().assertValidVariant(Resource(
          id: 'V0',
          source: 'x',
          textbookTag: '人教 A 版（2019 新版）',
          examTag: leaf,
          difficulty: 'medium',
          parentId: 'NOT-EXIST',
          variantLevel: 'L2')));
    });

    h.test('变式题标 isGaokao=true 被拒绝', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      h.throwsValidation(() => a.assertValidVariant(Resource(
          id: 'V0',
          source: 'x',
          textbookTag: '人教 A 版（2019 新版）',
          examTag: leaf,
          difficulty: 'medium',
          parentId: 'R-1',
          variantLevel: 'L2',
          isGaokao: true)));
    });

    h.test('attachVariant 空 motherId 被拒绝', () {
      h.throwsValidation(() => _adapter().attachVariant(motherId: ''));
    });

    h.test('attachVariant 未登记母题被拒绝', () {
      h.throwsValidation(() => _adapter().attachVariant(motherId: 'NOPE'));
    });

    h.test('不得基于变式再变式（母题必须是原始题）', () {
      h.throwsValidation(() {
        final a = _adapter();
        _ingest(a, id: 'R-1');
        final v = a.attachVariant(motherId: 'R-1');
        a.attachVariant(motherId: v.id);
      });
    });

    h.test('attachVariant 合法：挂靠母题、继承来源、恒定非真题', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      final v = a.attachVariant(
          motherId: 'R-1', difficulty: 'hard', variantLevel: 'L4');
      h.eq(v.parentId, 'R-1');
      h.eq(v.source, '我的资料·基本不等式讲义.pdf');
      h.eq(v.examTag, leaf);
      h.eq(v.difficulty, 'hard');
      h.eq(v.variantLevel, 'L4');
      h.isFalse(v.isGaokao);
    });

    h.test('接入层混进非 L1 变形档被拒（变式统一走 attachVariant）', () {
      h.throwsValidation(() => _ingest(_adapter(), variantLevel: 'L2'));
    });

    h.test('接入层混进 parentId 被拒', () {
      h.throwsValidation(() => _ingest(_adapter(), parentId: 'R-1'));
    });
  });

  // ------------------------------------------------------------------ 验收④
  h.group('F12 验收④ B站资源不含视频二进制', () {
    h.test('B站只登记标题 / BV号 / 时长 / 跳转引用', () {
      final a = _adapter();
      _bili(a);
      final d = a.resolve('R-B');
      h.eq(d.channel, 'ref');
      h.eq(d.tier, SourceTier.bilibili);
      h.eq(d.bv, 'BV1xx411c7mD');
      h.eq(d.durationSeconds, 720);
      h.eq(d.title, '基本不等式精讲');
      h.contains(d.uri, 'bilibili.com');
      final keys = d.toJson().keys.toList();
      h.isFalse(keys.any((k) => k.toLowerCase().contains('binary')));
      h.isFalse(keys.any((k) => k.toLowerCase().contains('embedded')));
    });

    h.test('B站缺 BV 号被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          channel: 'ref',
          tier: SourceTier.bilibili,
          uri: 'https://www.bilibili.com/video/xxx'));
    });

    h.test('tier=bilibili 但通道非 ref 被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          channel: 'local',
          tier: SourceTier.bilibili,
          bv: 'BV1',
          uri: 'https://www.bilibili.com/video/BV1'));
    });

    h.test('ref 通道但 tier 非 bilibili 被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          channel: 'ref',
          tier: SourceTier.authoritative,
          uri: 'https://example.com'));
    });

    h.test('assertNoEmbeddedContent 拒绝各类二进制 / 版权正文字段', () {
      for (final k in ['binary', 'videoBinary', 'embeddedContent',
        'pdfBinary', 'videoData']) {
        h.throwsValidation(
            () => assertNoEmbeddedContent({k: 'AAAA'}), '字段 $k');
      }
    });

    h.test('assertNoEmbeddedContent 拒绝 data: / base64: 内嵌串', () {
      h.throwsValidation(() =>
          assertNoEmbeddedContent({'uri': 'data:video/mp4;base64,AAAA'}));
      h.throwsValidation(() =>
          assertNoEmbeddedContent({'uri': 'base64:AAAA'}));
    });

    h.test('ingest 的 uri 含 data: 内嵌视频被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          uri: 'data:video/mp4;base64,AAAAAAAA'));
    });

    h.test('接入描述序列化后不含任何二进制痕迹', () {
      final a = _adapter();
      _bili(a);
      final json = a.packageAssets()['resources/access.json']!;
      h.isFalse(json.contains('base64'));
      h.isFalse(json.contains('data:'));
      h.contains(json, 'BV1xx411c7mD');
      h.contains(json, '720');
    });
  });

  // ------------------------------------------------------------------ 验收⑤
  h.group('F12 验收⑤ 四通道接入不改变主流程', () {
    ResourceAdapter four() {
      final a = _adapter();
      _ingest(a,
          id: 'R-A',
          channel: 'A',
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/1');
      _ingest(a,
          id: 'R-C', channel: 'C', uri: 'archive:notein-001.pdf');
      _bili(a, id: 'R-ref');
      _ingest(a, id: 'R-local');
      return a;
    }

    h.test('A / C / ref / local 四通道全部登记成功，产出同一种 Resource', () {
      final a = four();
      h.eq(a.resources.length, 4);
      h.eq(a.resources.whereType<Resource>().length, 4);
      h.eq(a.packageEntities()['resources.json']!.length, 4);
    });

    h.test('每个通道都能 resolve 到对应 AccessDescriptor', () {
      final a = four();
      h.eq(a.resolve('R-A').channel, 'A');
      h.eq(a.resolve('R-C').channel, 'C');
      h.eq(a.resolve('R-ref').channel, 'ref');
      h.eq(a.resolve('R-local').channel, 'local');
    });

    h.test('四通道资源可直接喂给 F10 变式引擎（下游不分支）', () {
      final a = four();
      final ve = VariantEngine(bank: a.resources);
      final practice = ve.buildPractice(intent: 'follow', count: 5);
      h.eq(practice.length, 5);
      h.isTrue(practice.every((r) => r.parentId != null));
      h.isTrue(practice.every((r) => !r.isGaokao));
    });

    h.test('resolve 返回的是引用而非正文', () {
      final a = four();
      for (final r in a.resources) {
        final d = a.resolve(r.id);
        h.ok(d.uri.trim().isNotEmpty);
        h.isFalse(d.uri.startsWith('data:'));
        h.isFalse(d.uri.startsWith('base64:'));
      }
    });

    h.test('资料优先级：自己的资料 > 权威题库 > B站 > AI 生成', () {
      final a = _adapter();
      _bili(a, id: 'R-bili');
      _ingest(a,
          id: 'R-auth',
          channel: 'A',
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/1');
      _ingest(a, id: 'R-own');
      a.attachVariant(motherId: 'R-own', id: 'R-ai');
      h.eq(a.priorityOrdered().map((r) => r.id).join(','),
          'R-own,R-auth,R-bili,R-ai');
    });

    h.test('学科网内容不进包：只允许 https 外部引用', () {
      final a = _adapter();
      final r = _ingest(a,
          channel: 'A',
          tier: SourceTier.authoritative,
          uri: 'https://www.zxxk.com/q/2024',
          provider: '学科网');
      h.eq(a.resolve(r.id).provider, '学科网');
      h.contains(a.resolve(r.id).uri, 'https://');
    });

    h.test('学科网 uri 非 https（疑似内嵌正文）被拒绝', () {
      h.throwsValidation(() => _ingest(_adapter(),
          channel: 'A',
          tier: SourceTier.authoritative,
          uri: 'local:/zxxk/cached.pdf',
          provider: '学科网'));
    });

    h.test('AI 生成资源只能经 attachVariant，接入层直接登记被拒', () {
      h.throwsValidation(() => _ingest(_adapter(),
          tier: SourceTier.aiGenerated));
    });
  });

  // ------------------------------------------------------------------ 验收⑥
  h.group('F12 验收⑥ 考纲标签可映射到 ExamProfile 知识点树', () {
    h.test('叶子标签映射到具体知识点节点', () {
      final node = _adapter().assertExamTagMapped(leaf);
      h.eq(node.id, leaf);
      h.eq(node.title, '等号成立条件');
      h.isTrue(node.isLeaf);
    });

    h.test('分支标签也能映射到知识点树', () {
      final node = _adapter().assertExamTagMapped(branch);
      h.eq(node.id, branch);
      h.isFalse(node.isLeaf);
    });

    h.test('未登记的考纲标签被拒绝', () {
      h.throwsValidation(
          () => _adapter().assertExamTagMapped('RJ-A-BX1-CH99'));
      h.throwsValidation(() => _ingest(_adapter(), examTag: 'NOT-IN-TREE'));
    });

    h.test('空考纲标签被拒绝', () {
      h.throwsValidation(() => _adapter().assertExamTagMapped('   '));
    });

    h.test('教材版本不对齐人教 A 版被拒绝', () {
      h.throwsValidation(
          () => _ingest(_adapter(), textbookTag: '苏教版·必修一'));
    });

    h.test('题型不在新高考 I 卷题型表内被拒绝', () {
      h.throwsValidation(
          () => _ingest(_adapter(), questionType: '不定项证明题'));
    });

    h.test('合法题型「多选」通过', () {
      final r = _ingest(_adapter(), questionType: '多选', score: 5);
      h.eq(r.questionType, '多选');
    });

    h.test('resourcesForExamTag 按节点检索命中', () {
      final a = _adapter();
      _ingest(a, id: 'R-1', examTag: leaf);
      _ingest(a, id: 'R-2', examTag: branch);
      h.eq(a.resourcesForExamTag(leaf).length, 1);
      h.eq(a.resourcesForExamTag(branch).length, 1);
      h.throwsValidation(() => a.resourcesForExamTag('BAD'));
    });

    h.test('对齐基线：新高考 I 卷 / 150 分 / 难度 5:3:2', () {
      final p = _adapter().profile;
      h.eq(p.paper, '新高考 I 卷（新课标 I 卷）');
      h.eq(p.totalScore, 150);
      h.ok((p.difficultySum - 1.0).abs() < 1e-9);
      h.eq(p.difficultyRatio['basic'], 0.5);
      h.eq(p.difficultyRatio['medium'], 0.3);
      h.eq(p.difficultyRatio['hard'], 0.2);
      h.eq(E.difficulties.length, 3);
    });
  });

  // ------------------------------------------------------------------ 往返
  h.group('F12 全量往返与 .studypack 只带走引用与标签', () {
    h.test('toJson / fromJson 全量往返', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      _bili(a, id: 'R-B');
      a.attachVariant(motherId: 'R-1', id: 'R-V');
      final back = ResourceAdapter.fromJson(a.toJson());
      h.eq(back.resources.length, 3);
      h.eq(back.resolve('R-B').bv, 'BV1xx411c7mD');
      h.eq(back.resolve('R-V').tier, SourceTier.aiGenerated);
      h.eq(back.profile.totalScore, 150);
      h.jsonEq(back.toJson(), a.toJson());
    });

    h.test('packageEntities 只输出 resources.json；assets 只含引用与标签', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      _bili(a, id: 'R-B');
      final ents = a.packageEntities();
      h.eq(ents.keys.length, 1);
      h.eq(ents['resources.json']!.length, 2);
      final assets = a.packageAssets();
      h.eq(assets.keys.length, 1);
      h.contains(assets['resources/access.json']!, 'BV1xx411c7mD');
      h.isFalse(assets.values.any((v) => v.contains('base64')));
      h.isFalse(assets.values.any((v) => v.contains('data:')));
      h.isFalse(ents.values.any((list) =>
          list.any((m) => m.keys.any((k) => k.toLowerCase().contains('binary')))));
    });

    h.test('exportPack + importPack 不报错，包内不含二进制 / 凭证', () {
      final a = _adapter();
      _ingest(a, id: 'R-1');
      _bili(a, id: 'R-B');
      final files = StudyPack.exportPack(
        DataPackage(entities: a.packageEntities()),
        device: 'Lenovo Y900',
        assets: a.packageAssets(),
      );
      final back = StudyPack.importPack(files);
      h.eq(back.entities['resources.json']!.length, 2);
      h.isFalse(files.values.any((v) => v.contains('base64')));
      h.isFalse(files.values.any((v) => v.contains('sk-')));
    });

    h.test('系统层面明确拒绝「凭空造题」', () {
      h.throwsValidation(() => _adapter().generateFromScratch());
    });
  });
}

void main() {
  final h = Harness();
  runF12(h);
  h.report();
}
