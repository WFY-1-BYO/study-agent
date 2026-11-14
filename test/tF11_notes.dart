/// F11 · 笔记子系统测试（PRD §4 F11 六条验收逐条 + 硬约束）。
/// 单独运行：dart test/tF11_notes.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/notes.dart';
import '../lib/preferences.dart';
import '../lib/studypack.dart';

const kn = 'RJ-A-BX1-CH2-2.2-EQ';
const se = 'SE-0001';
const wp = 'WP-0001';

String _anchor() => buildAnchorId(kn, se, wp);

NoteDocument _ai({
  String id = 'AN-1',
  String channel = 'D',
  String ct = 'structuredText',
  String? anchorId,
  List<String>? blocks,
  bool aiGenerated = true,
}) =>
    NoteDocument(
      id: id,
      owner: 'ai',
      channel: channel,
      contentType: ct,
      anchorId: anchorId ?? _anchor(),
      blocks: blocks ?? <String>['AI 讲解：一正二定三相等，先问等号取不取得到'],
      aiGenerated: aiGenerated,
    );

NoteDocument _mine({
  String id = 'MD-1',
  String channel = 'D',
  String ct = 'svgInk',
  String? anchorId,
  List<String>? blocks,
  bool aiGenerated = false,
}) =>
    NoteDocument(
      id: id,
      owner: 'mine',
      channel: channel,
      contentType: ct,
      anchorId: anchorId ?? _anchor(),
      blocks: blocks ?? <String>['手写：一正二定三相等'],
      aiGenerated: aiGenerated,
    );

NoteDocument _aRef() => _mine(
      id: 'MA-1',
      channel: 'A',
      ct: 'externalRef',
      blocks: <String>['ref:notein://page/12'],
    );

NoteDocument _cPdf({String id = 'MC-1', List<String>? blocks}) => _mine(
      id: id,
      channel: 'C',
      ct: 'pdf',
      blocks: blocks ?? <String>['archive:notein-export-001.pdf'],
    );

NotesSubsystem _sub({PreferencesLayer? prefs}) =>
    NotesSubsystem(prefs: prefs);

/// 三通道齐全 + 一份 AI 笔记 + 一份 A→C 归档快照的标准夹具。
NotesSubsystem _full({PreferencesLayer? prefs}) {
  final s = _sub(prefs: prefs);
  s.addAiNote(_ai());
  s.addMyNote(_aRef());
  s.addMyNote(_cPdf());
  s.addMyNote(_mine(id: 'MD-1'));
  s.archiveSnapshot('MA-1', 'notein-export-001.pdf');
  return s;
}

void runF11(Harness h) {
  // ------------------------------------------------------------------ 验收①
  h.group('F11 验收① 两份笔记独立存、不合订', () {
    h.test('AI 笔记只进 aiNotes，我的笔记只进 myNotes', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      h.eq(s.aiNotes.length, 1);
      h.eq(s.myNotes.length, 1);
      h.eq(s.aiNotes.first.owner, 'ai');
      h.eq(s.myNotes.first.owner, 'mine');
    });

    h.test('addAiNote 收到 owner=mine 被拒绝', () {
      h.throwsValidation(() => _sub().addAiNote(
          NoteDocument(
              id: 'X',
              owner: 'mine',
              channel: 'D',
              contentType: 'structuredText',
              anchorId: _anchor(),
              blocks: <String>['x'],
              aiGenerated: true)));
    });

    h.test('addMyNote 收到 owner=ai 被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_ai()));
    });

    h.test('我的笔迹不得标记 aiGenerated=true', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(aiGenerated: true)));
    });

    h.test('AI 笔记必须 aiGenerated=true', () {
      h.throwsValidation(() => _sub().addAiNote(_ai(aiGenerated: false)));
    });

    h.test('AI 笔记不得走 A 通道（A 只放外部原件引用）', () {
      h.throwsValidation(() => _sub().addAiNote(_ai(
          channel: 'A',
          ct: 'externalRef',
          blocks: <String>['ref:notein://page/9'])));
    });

    h.test('.studypack 导出为三份独立文件，两份笔记不合订', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      final e = s.packageEntities();
      h.eq(e.keys.length, 3);
      h.eq(e['ai_notes.json']!.length, 1);
      h.eq(e['my_notes.json']!.length, 1);
      h.eq(e['ai_notes.json']![0]['owner'], 'ai');
      h.eq(e['my_notes.json']![0]['owner'], 'mine');
      h.isFalse(e['ai_notes.json']!.any((x) => x['id'] == 'MD-1'));
      h.isFalse(e['my_notes.json']!.any((x) => x['id'] == 'AN-1'));
      h.eq(e['anchor_links.json']!.length, 1);
    });

    h.test('笔记 id 在两份容器中必须全局唯一', () {
      h.throwsValidation(() {
        final s = _sub();
        s.addAiNote(_ai(id: 'SAME'));
        s.addMyNote(_mine(id: 'SAME'));
      });
    });

    h.test('同一容器重复 id 被拒绝', () {
      h.throwsValidation(() {
        final s = _sub();
        s.addMyNote(_mine(id: 'DUP'));
        s.addMyNote(_mine(id: 'DUP'));
      });
    });
  });

  // ------------------------------------------------------------------ 验收②
  h.group('F11 验收② anchorId 双向查询命中且纯本地', () {
    h.test('anchorIdFor 按「知识点::会话::薄弱点」三段生成', () {
      h.eq(_sub().anchorIdFor(
          knowledgeNodeId: kn, sessionId: se, weakPointId: wp),
          '$kn::$se::$wp');
    });

    h.test('anchorId 任一段为空被拒绝', () {
      final s = _sub();
      h.throwsValidation(() => s.anchorIdFor(
          knowledgeNodeId: '', sessionId: se, weakPointId: wp));
      h.throwsValidation(() => s.anchorIdFor(
          knowledgeNodeId: kn, sessionId: '', weakPointId: wp));
      h.throwsValidation(() => s.anchorIdFor(
          knowledgeNodeId: kn, sessionId: se, weakPointId: ''));
    });

    h.test('正向：同一锚点下 AI 笔记与我的笔记都命中', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      h.eq(s.aiNotesAt(_anchor()).length, 1);
      h.eq(s.myNotesAt(_anchor()).length, 1);
      h.eq(s.aiNotesAt(_anchor()).first.id, 'AN-1');
      h.eq(s.myNotesAt(_anchor()).first.id, 'MD-1');
    });

    h.test('反向：AI 笔记 → 我的笔迹 / 我的笔迹 → AI 笔记 都能命中', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      h.eq(s.linkedMyNoteIds('AN-1').join(','), 'MD-1');
      h.eq(s.linkedAiNoteIds('MD-1').join(','), 'AN-1');
      h.eq(s.linkedNotes('AN-1').first.id, 'MD-1');
      h.eq(s.linkedNotes('MD-1').first.id, 'AN-1');
    });

    h.test('跨锚点不串：另一个 anchorId 查不到', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      final other = buildAnchorId(kn, 'SE-9999', wp);
      h.eq(s.aiNotesAt(other).length, 0);
      h.eq(s.myNotesAt(other).length, 0);
      h.eq(s.links.length, 1);
    });

    h.test('查询本身零外发：双向检索后 outboundLog 仍为空', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      s.aiNotesAt(_anchor());
      s.myNotesAt(_anchor());
      s.linkedMyNoteIds('AN-1');
      s.linkedNotes('MD-1');
      h.isFalse(s.hasOutbound);
      h.eq(s.outboundLog.length, 0);
    });

    h.test('离线（白名单为空）时双向索引照样工作', () {
      final s = _sub(); // 默认白名单空 = 离线
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      h.isFalse(s.prefs.allowOutbound(NotesSubsystem.outboundKind));
      h.eq(s.linkedNotes('AN-1').length, 1);
    });

    h.test('AnchorLink 索引可经 .studypack 实体文件往返', () {
      final s = _sub();
      s.addAiNote(_ai());
      s.addMyNote(_mine());
      final back = NotesSubsystem.fromPackageEntities(
          s.packageEntities(), prefs: s.prefs);
      h.eq(back.links.length, 1);
      h.eq(back.links.first.anchorId, _anchor());
      h.eq(back.linkedMyNoteIds('AN-1').join(','), 'MD-1');
      h.eq(back.linkedAiNoteIds('MD-1').join(','), 'AN-1');
    });
  });

  // ------------------------------------------------------------------ 验收③
  h.group('F11 验收③ 关闭 D 通道不删除 A/C 归档', () {
    h.test('三通道规则：A=externalRef / C=pdf / D=structuredText|svgInk', () {
      final s = _full();
      h.eq(s.archiveCount, 3); // MA-1(A) + MC-1(C) + ARCH-0001(C)
      h.eq(s.myNotes.where((n) => n.channel == 'D').length, 1);
    });

    h.test('A 通道 contentType 非 externalRef 被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(
          id: 'BAD-A1', channel: 'A', ct: 'svgInk',
          blocks: <String>['ref:x'])));
    });

    h.test('A 通道出现笔迹正文（非 ref: 前缀）被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(
          id: 'BAD-A2', channel: 'A', ct: 'externalRef',
          blocks: <String>['一正二定三相等'])));
    });

    h.test('C 通道 contentType 非 pdf 被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(
          id: 'BAD-C1', channel: 'C', ct: 'structuredText',
          blocks: <String>['archive:x'])));
    });

    h.test('C 通道出现非归档引用（非 archive: 前缀）被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(
          id: 'BAD-C2', channel: 'C', ct: 'pdf',
          blocks: <String>['正文'])));
    });

    h.test('D 通道 contentType=pdf 被拒绝', () {
      h.throwsValidation(() => _sub().addMyNote(_mine(
          id: 'BAD-D1', channel: 'D', ct: 'pdf',
          blocks: <String>['正文'])));
    });

    h.test('archiveSnapshot：A → C，原件仍是外部引用', () {
      final s = _sub();
      s.addMyNote(_aRef());
      final arch = s.archiveSnapshot('MA-1', 'notein-export-001.pdf');
      h.eq(arch.channel, 'C');
      h.eq(arch.contentType, 'pdf');
      h.eq(arch.blocks.first, 'archive:notein-export-001.pdf');
      h.eq(arch.anchorId, _anchor());
      h.eq(s.myNotes.firstWhere((n) => n.id == 'MA-1').channel, 'A');
      h.eq(s.myNotes.firstWhere((n) => n.id == 'MA-1').contentType,
          'externalRef');
    });

    h.test('非 A 通道原件不允许归档为快照', () {
      h.throwsValidation(() {
        final s = _sub();
        s.addMyNote(_mine());
        s.archiveSnapshot('MD-1', 'x.pdf');
      });
    });

    h.test('隐藏内置笔记区后，两份笔记总数与归档数均不变', () {
      final s = _full();
      final total = s.aiNotes.length + s.myNotes.length;
      h.eq(total, 5); // 1 AI + 3 我的 + 1 归档快照
      s.setNoteAreaVisible(se, false);
      h.isFalse(s.noteVisibleFor(se));
      h.eq(s.aiNotes.length + s.myNotes.length, total);
      h.eq(s.archiveCount, 3);
    });

    h.test('隐藏后渲染态不含 D，但仍含 A/C 归档引用', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      final vis = s.renderedNotes(se, _anchor());
      h.isFalse(vis.any((n) => n.channel == 'D'));
      h.eq(vis.length, 3);
      h.isTrue(vis.any((n) => n.channel == 'A'));
      h.isTrue(vis.any((n) => n.channel == 'C'));
    });

    h.test('重新开启后 D 通道恢复渲染（数据从未被删）', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      s.setNoteAreaVisible(se, true);
      final vis = s.renderedNotes(se, _anchor());
      h.isTrue(vis.any((n) => n.channel == 'D'));
      h.eq(vis.length, 5);
    });
  });

  // ------------------------------------------------------------------ 验收④
  h.group('F11 验收④ OCR 摘要与原件分离', () {
    h.test('添加 OCR 摘要后，原始笔迹 blocks 逐字不变', () {
      final s = _sub();
      s.addMyNote(_mine());
      final before = List<String>.from(s.originalBlocks('MD-1'));
      s.addOcrSummary('MD-1', '识别结果：一正二定三相等');
      h.jsonEq(s.originalBlocks('MD-1'), before);
      h.eq(s.originalBlocks('MD-1').first, '手写：一正二定三相等');
    });

    h.test('摘要独立存、source=ocr、derived=true，且不等于原件', () {
      final s = _sub();
      s.addMyNote(_mine());
      s.addOcrSummary('MD-1', '识别结果：一正二定三相等');
      final sum = s.ocrSummaryFor('MD-1')!;
      h.eq(sum.source, 'ocr');
      h.isTrue(sum.derived);
      h.eq(sum.noteId, 'MD-1');
      h.eq(sum.anchorId, _anchor());
      h.isFalse(s.originalBlocks('MD-1').contains(sum.text));
    });

    h.test('识别错可丢弃摘要重来，原件仍不受影响', () {
      final s = _sub();
      s.addMyNote(_mine());
      final before = List<String>.from(s.originalBlocks('MD-1'));
      s.addOcrSummary('MD-1', '识别错了：一正二定四相等');
      s.dropOcrSummary('MD-1');
      h.isNull(s.ocrSummaryFor('MD-1'));
      h.jsonEq(s.originalBlocks('MD-1'), before);
      s.addOcrSummary('MD-1', '重新识别：一正二定三相等');
      h.eq(s.ocrSummaryFor('MD-1')!.text, '重新识别：一正二定三相等');
    });

    h.test('系统层面拒绝「用 OCR 覆盖原件」', () {
      h.throwsValidation(() => _sub().overwriteOriginalWithOcr());
    });

    h.test('空摘要被拒绝；给不存在的笔记写摘要被拒绝', () {
      final s = _sub();
      s.addMyNote(_mine());
      h.throwsValidation(() => s.addOcrSummary('MD-1', '   '));
      h.throwsValidation(() => s.addOcrSummary('NOT-EXIST', 'x'));
    });

    h.test('OCR 摘要伪造 source / derived 被拒绝', () {
      h.throwsValidation(() => OcrSummary(
          noteId: 'MD-1', anchorId: _anchor(), text: 'x', source: 'manual'));
      h.throwsValidation(() => OcrSummary(
          noteId: 'MD-1', anchorId: _anchor(), text: 'x', derived: false));
    });
  });

  // ------------------------------------------------------------------ 验收⑤
  h.group('F11 验收⑤ 隐藏笔记区后归档仍可检索（接 F4）', () {
    h.test('隐藏后 searchArchive 仍命中全部 A/C 归档', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      final arch = s.searchArchive(_anchor());
      h.eq(arch.length, 3);
      h.isFalse(arch.any((n) => n.channel == 'D'));
    });

    h.test('归档登记接 F4：prefs.findArchived 命中且不受显隐影响', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      final ids = s.prefs.findArchived(_anchor());
      h.eq(ids.length, 3);
      h.isTrue(ids.contains('MA-1'));
      h.isTrue(ids.contains('MC-1'));
      h.isTrue(ids.contains('ARCH-0001'));
      h.isFalse(ids.contains('MD-1')); // D 通道不进归档索引
    });

    h.test('隐藏后仍可导出全量归档（数据可带走）', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      final e = s.packageEntities();
      h.eq(e['my_notes.json']!.length, 4);
      h.eq(e['ai_notes.json']!.length, 1);
      h.eq(e['anchor_links.json']!.length, 1);
    });
  });

  // ------------------------------------------------------------------ 验收⑥
  h.group('F11 验收⑥ 主动触发才调用 AI，未触发零外发', () {
    h.test('仅本地操作（建笔记/显隐/OCR/双向查询）后零外发', () {
      final s = _full();
      s.setNoteAreaVisible(se, false);
      s.addOcrSummary('MD-1', '识别结果');
      s.linkedNotes('AN-1');
      s.searchArchive(_anchor());
      h.isFalse(s.hasOutbound);
      h.eq(s.outboundLog.length, 0);
    });

    h.test('默认不把笔记交给 AI：未开白名单时主动触发也被拒', () {
      final s = _sub();
      s.addMyNote(_cPdf());
      h.throwsValidation(() => s.requestAiAssist(noteId: 'MC-1'));
      h.isFalse(s.hasOutbound);
    });

    h.test('开启白名单 + 主动触发 C 归档 → 产生 1 条可审计外发', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_cPdf());
      final rec = s.requestAiAssist(noteId: 'MC-1');
      h.eq(s.outboundLog.length, 1);
      h.isTrue(s.hasOutbound);
      h.eq(rec.noteId, 'MC-1');
      h.eq(rec.anchorId, _anchor());
      h.eq(rec.channel, 'C');
      h.isTrue(rec.redacted);
    });

    h.test('A 通道外部原件不可外发（只有 C 归档可被处理）', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_aRef());
      h.throwsValidation(() => s.requestAiAssist(noteId: 'MA-1'));
    });

    h.test('D 通道内置笔迹不可外发', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_mine());
      h.throwsValidation(() => s.requestAiAssist(noteId: 'MD-1'));
    });

    h.test('最小必要：只送单个 block 且截断到 maxChars', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_cPdf(blocks: <String>[
        'archive:' + '甲' * 300,
        'archive:第二段绝不能被带出去',
      ]));
      final rec = s.requestAiAssist(noteId: 'MC-1', maxChars: 20);
      h.eq(rec.excerpt.length, 20);
      h.isFalse(rec.excerpt.contains('第二段'));
      h.eq(rec.charCount, 20);
    });

    h.test('越界的 maxChars / blockIndex 被拒绝', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_cPdf());
      h.throwsValidation(
          () => s.requestAiAssist(noteId: 'MC-1', maxChars: 0));
      h.throwsValidation(
          () => s.requestAiAssist(noteId: 'MC-1', maxChars: 999));
      h.throwsValidation(
          () => s.requestAiAssist(noteId: 'MC-1', blockIndex: 5));
    });

    h.test('脱敏：手机号 / 邮箱 / 疑似密钥 / 凭证赋值均被遮蔽', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _sub(prefs: p);
      s.addMyNote(_cPdf(blocks: <String>[
        'archive:联系 13812345678',
        'archive:邮箱 a.b+tag@sz.edu.cn',
        'archive:备用 sk-ABCDEFGH12345678',
        'archive:api_key=abcdef123456',
      ]));
      final r0 = s.requestAiAssist(noteId: 'MC-1', blockIndex: 0);
      final r1 = s.requestAiAssist(noteId: 'MC-1', blockIndex: 1);
      final r2 = s.requestAiAssist(noteId: 'MC-1', blockIndex: 2);
      final r3 = s.requestAiAssist(noteId: 'MC-1', blockIndex: 3);
      h.isFalse(r0.excerpt.contains('13812345678'));
      h.isTrue(r0.excerpt.contains('[REDACTED_PHONE]'));
      h.isFalse(r1.excerpt.contains('a.b+tag@sz.edu.cn'));
      h.isTrue(r1.excerpt.contains('[REDACTED_EMAIL]'));
      h.isFalse(r2.excerpt.contains('sk-ABCDEFGH12345678'));
      h.isFalse(r2.excerpt.contains('sk-'));
      h.isTrue(r2.excerpt.contains('[REDACTED_KEY]'));
      h.isFalse(r3.excerpt.contains('abcdef123456'));
      h.isTrue(r3.excerpt.contains('[REDACTED_CRED]'));
      h.eq(s.outboundLog.length, 4);
    });

    h.test('外发记录不可伪造 channel / redacted', () {
      h.throwsValidation(() => OutboundRecord(
          anchorId: _anchor(),
          noteId: 'MC-1',
          channel: 'A',
          purpose: 'x',
          excerpt: 'x',
          charCount: 1));
      h.throwsValidation(() => OutboundRecord(
          anchorId: _anchor(),
          noteId: 'MC-1',
          channel: 'C',
          purpose: 'x',
          excerpt: 'x',
          charCount: 1,
          redacted: false));
    });
  });

  // ------------------------------------------------------------------ 往返
  h.group('F11 全量往返与数据带走', () {
    h.test('toJson / fromJson 全量往返：笔记 / 索引 / OCR / 外发台账', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _full(prefs: p);
      s.setNoteAreaVisible(se, false);
      s.addOcrSummary('MD-1', '识别结果：一正二定三相等');
      s.requestAiAssist(noteId: 'ARCH-0001');

      final back = NotesSubsystem.fromJson(s.toJson());
      h.eq(back.aiNotes.length, s.aiNotes.length);
      h.eq(back.myNotes.length, s.myNotes.length);
      h.eq(back.links.length, s.links.length);
      h.eq(back.outboundLog.length, 1);
      h.eq(back.ocrSummaryFor('MD-1')!.text, '识别结果：一正二定三相等');
      h.isFalse(back.noteVisibleFor(se)); // 显隐开关也恢复
      h.eq(back.linkedMyNoteIds('AN-1').length, 4);
      h.eq(back.searchArchive(_anchor()).length, 3);
      h.jsonEq(back.toJson(), s.toJson());
    });

    h.test('packageAssets 带走 OCR 摘要与外发日志且不含凭证', () {
      final p = PreferencesLayer(
          global: Preferences(
              dataOutboundWhitelist: <String>[NotesSubsystem.outboundKind]));
      final s = _full(prefs: p);
      s.addOcrSummary('MD-1', '识别结果：一正二定三相等');
      s.requestAiAssist(noteId: 'ARCH-0001');
      final a = s.packageAssets();
      h.ok(a.containsKey('notes/ocr_summaries.json'));
      h.ok(a.containsKey('notes/outbound_log.json'));
      h.contains(a['notes/ocr_summaries.json']!, '识别结果');
      h.isFalse(a.values.any((v) => v.contains('sk-')));
    });

    h.test('.studypack 导出（实体 + assets）可被 F2 导入且不报错', () {
      final s = _full();
      s.addOcrSummary('MD-1', '识别结果');
      final files = StudyPack.exportPack(
        DataPackage(entities: s.packageEntities()),
        device: 'vivo S7',
        assets: s.packageAssets(),
      );
      final back = StudyPack.importPack(files);
      h.eq(back.entities['ai_notes.json']!.length, 1);
      h.eq(back.entities['my_notes.json']!.length, 4);
      h.eq(back.entities['anchor_links.json']!.length, 1);
      h.ok(files.containsKey('notes/ocr_summaries.json'));
      h.isFalse(files.values.any((v) => v.contains('sk-')));
    });
  });
}

void main() {
  final h = Harness();
  runF11(h);
  h.report();
}
