/// F11 · 笔记子系统（A/C/D 三通道 + 双向关联）。
///
/// 硬约束（PRD §4 F11，逐条对应验收）：
///  - AI 笔记与「我的笔记」两份**独立存储、不合订**；
///  - `anchorId = 知识点节点ID :: SessionID :: WeakPointID`（core.buildAnchorId）；
///  - `AnchorLink` 本地索引双向可查，纯本地 / 离线可用，查询本身零外发；
///  - A 通道原件永远是外部引用，只有 C 通道归档回来的那份可被 AI 处理；
///  - D 内置笔记区可显隐；显隐只影响渲染，绝不删除 A/C 归档；
///  - OCR/视觉识别结果只作可检索摘要，与原始笔迹分离，绝不覆盖原件；
///  - 默认不把笔记交给 AI；只有主动触发才外发，且最小必要 + 脱敏。
///
/// 零第三方依赖，兼容 Dart 2.17。
library study_agent.notes;

import 'dart:convert';

import 'core.dart';
import 'models.dart';
import 'preferences.dart';

/// OCR / 视觉识别摘要：**与原始笔迹分离存储**，绝不覆盖原件。
/// 识别错了可以直接丢弃重来，不污染用户数据。
class OcrSummary implements Entity {
  final String noteId;
  final String anchorId;
  final String text;
  final String source; // 恒 'ocr'
  final bool derived; // 恒 true：它是派生数据，不是原件

  OcrSummary({
    required this.noteId,
    required this.anchorId,
    required this.text,
    this.source = 'ocr',
    this.derived = true,
  }) {
    if (source != 'ocr') {
      throw ValidationError('OcrSummary.source 恒为 "ocr"，实际 "$source"');
    }
    if (!derived) throw ValidationError('OCR 摘要必须标记为派生数据 derived=true');
    if (text.trim().isEmpty) throw ValidationError('OCR 摘要文本不可为空');
  }

  @override
  Map<String, dynamic> toJson() => {
        'noteId': noteId,
        'anchorId': anchorId,
        'text': text,
        'source': source,
        'derived': derived,
      };

  static OcrSummary fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return OcrSummary(
      noteId: m['noteId'] as String,
      anchorId: m['anchorId'] as String,
      text: m['text'] as String,
      source: m['source'] as String,
      derived: m['derived'] as bool,
    );
  }
}

/// 一次「主动触发」的 AI 外发记录。
/// 默认零外发 = 这份列表为空；它是可审计的外发台账，不是网络调用本身。
class OutboundRecord implements Entity {
  final String anchorId;
  final String noteId;
  final String channel;
  final String purpose;
  final String excerpt; // 脱敏后的一小段
  final int charCount;
  final bool redacted;

  OutboundRecord({
    required this.anchorId,
    required this.noteId,
    required this.channel,
    required this.purpose,
    required this.excerpt,
    required this.charCount,
    this.redacted = true,
  }) {
    if (!redacted) throw ValidationError('外发片段必须经过脱敏');
    if (channel != 'C') {
      throw ValidationError('只有 C 通道归档可被外发，实际 $channel');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'anchorId': anchorId,
        'noteId': noteId,
        'channel': channel,
        'purpose': purpose,
        'excerpt': excerpt,
        'charCount': charCount,
        'redacted': redacted,
      };

  static OutboundRecord fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return OutboundRecord(
      anchorId: m['anchorId'] as String,
      noteId: m['noteId'] as String,
      channel: m['channel'] as String,
      purpose: m['purpose'] as String,
      excerpt: m['excerpt'] as String,
      charCount: m['charCount'] as int,
      redacted: m['redacted'] as bool,
    );
  }
}

/// 笔记子系统主入口。
class NotesSubsystem implements Entity {
  /// 外发白名单键（与 F4 `Preferences.dataOutboundWhitelist` 对齐）。
  static const String outboundKind = 'noteReading';

  /// 最小必要外发：单次最多送审的字符数上限。
  static const int defaultMaxChars = 500;

  final PreferencesLayer prefs;

  // 两份独立存储：key 均为 noteId，绝不合并。
  final Map<String, NoteDocument> _aiNotes = <String, NoteDocument>{};
  final Map<String, NoteDocument> _myNotes = <String, NoteDocument>{};

  // 纯本地锚点索引（O(1) 命中，离线可用）。
  final Map<String, AnchorLink> _links = <String, AnchorLink>{};

  // OCR 摘要与外发台账：与原件 / 主流程分离。
  final Map<String, OcrSummary> _ocr = <String, OcrSummary>{};
  final List<OutboundRecord> _outbound = <OutboundRecord>[];

  int _seq = 0;

  NotesSubsystem({PreferencesLayer? prefs})
      : prefs = prefs ?? PreferencesLayer();

  // ---------------------------------------------------------------- 查询
  List<NoteDocument> get aiNotes =>
      List<NoteDocument>.unmodifiable(_aiNotes.values);

  List<NoteDocument> get myNotes =>
      List<NoteDocument>.unmodifiable(_myNotes.values);

  List<AnchorLink> get links =>
      List<AnchorLink>.unmodifiable(_links.values);

  List<OutboundRecord> get outboundLog =>
      List<OutboundRecord>.unmodifiable(_outbound);

  /// 默认零外发：只要没主动触发，这里恒为 false。
  bool get hasOutbound => _outbound.isNotEmpty;

  /// A/C 归档数量（不受显隐影响，用于验证「隐藏不删归档」）。
  int get archiveCount => _aiNotes.values.where((n) => n.channel != 'D').length +
      _myNotes.values.where((n) => n.channel != 'D').length;

  // ---------------------------------------------------------------- 通道规则
  /// A 原件=外部引用、C 归档=PDF 引用、D 内置=结构化文本/墨迹。
  /// 任何违反都抛 ValidationError，不静默降级。
  void assertChannelRules(NoteDocument n) {
    switch (n.channel) {
      case 'A':
        if (n.contentType != 'externalRef') {
          throw ValidationError(
              'A 通道原件始终是外部引用，contentType 必须为 externalRef');
        }
        for (final b in n.blocks) {
          if (!b.startsWith('ref:')) {
            throw ValidationError(
                'A 通道只存外部引用（ref: 前缀），不得存笔迹正文: "$b"');
          }
        }
        break;
      case 'C':
        if (n.contentType != 'pdf') {
          throw ValidationError('C 通道归档 contentType 必须为 pdf');
        }
        for (final b in n.blocks) {
          if (!b.startsWith('archive:')) {
            throw ValidationError(
                'C 通道归档只存归档引用（archive: 前缀）: "$b"');
          }
        }
        break;
      case 'D':
        if (n.contentType != 'structuredText' && n.contentType != 'svgInk') {
          throw ValidationError(
              'D 通道内置笔记 contentType 必须为 structuredText / svgInk');
        }
        break;
    }
  }

  // ---------------------------------------------------------------- 写入
  /// 生成锚点坐标（三段缺一不可）。
  String anchorIdFor({
    required String knowledgeNodeId,
    required String sessionId,
    required String weakPointId,
  }) {
    if (knowledgeNodeId.trim().isEmpty ||
        sessionId.trim().isEmpty ||
        weakPointId.trim().isEmpty) {
      throw ValidationError('anchorId 三段（知识点 / 会话 / 薄弱点）均不可为空');
    }
    return buildAnchorId(knowledgeNodeId, sessionId, weakPointId);
  }

  /// 登记一份 AI 笔记（独立容器）。
  void addAiNote(NoteDocument n) {
    if (n.owner != 'ai') {
      throw ValidationError('addAiNote 只收 owner=ai，实际 "${n.owner}"');
    }
    if (!n.aiGenerated) {
      throw ValidationError('AI 笔记必须 aiGenerated=true');
    }
    if (n.channel == 'A') {
      throw ValidationError('AI 笔记不得走 A 通道（A 只放外部原件引用）');
    }
    assertChannelRules(n);
    _register(_aiNotes, n, isAi: true);
  }

  /// 登记一份「我的笔记」（独立容器）。
  void addMyNote(NoteDocument n) {
    if (n.owner != 'mine') {
      throw ValidationError('addMyNote 只收 owner=mine，实际 "${n.owner}"');
    }
    if (n.aiGenerated) {
      throw ValidationError('我的笔迹不得标记 aiGenerated=true');
    }
    assertChannelRules(n);
    _register(_myNotes, n, isAi: false);
  }

  void _register(
    Map<String, NoteDocument> store,
    NoteDocument n, {
    required bool isAi,
    bool registerArchive = true,
  }) {
    if (store.containsKey(n.id) ||
        _aiNotes.containsKey(n.id) ||
        _myNotes.containsKey(n.id)) {
      throw ValidationError('笔记 id 必须全局唯一，重复: ${n.id}');
    }
    if (n.anchorId.trim().isEmpty) {
      throw ValidationError('NoteDocument.anchorId 必填');
    }
    // 复制 blocks，切断外部可变引用，保证原件不被外部意外改写。
    store[n.id] = NoteDocument(
      id: n.id,
      owner: n.owner,
      channel: n.channel,
      contentType: n.contentType,
      anchorId: n.anchorId,
      blocks: List<String>.from(n.blocks),
      aiGenerated: n.aiGenerated,
    );
    final link = _links.putIfAbsent(
        n.anchorId, () => AnchorLink(anchorId: n.anchorId));
    final ids = isAi ? link.aiNoteIds : link.myNoteIds;
    if (!ids.contains(n.id)) ids.add(n.id);

    // A/C 归档接 F4：显隐只影响渲染，归档索引始终可用。
    if (registerArchive && n.channel != 'D') {
      prefs.registerArchived(n.anchorId, n.id);
    }
  }

  NoteDocument _find(String noteId) {
    final n = _aiNotes[noteId] ?? _myNotes[noteId];
    if (n == null) throw ValidationError('未找到笔记 $noteId');
    return n;
  }

  List<NoteDocument> _idsToNotes(
          List<String> ids, Map<String, NoteDocument> store) =>
      List<NoteDocument>.unmodifiable(
          ids.map((id) => store[id]).whereType<NoteDocument>().toList());

  // ---------------------------------------------------------------- 双向关联
  /// 正向：按锚点取 AI 笔记 / 我的笔记。
  List<NoteDocument> aiNotesAt(String anchorId) =>
      _idsToNotes(_links[anchorId]?.aiNoteIds ?? const <String>[], _aiNotes);

  List<NoteDocument> myNotesAt(String anchorId) =>
      _idsToNotes(_links[anchorId]?.myNoteIds ?? const <String>[], _myNotes);

  /// 反向：从一份 AI 笔记 id 找到同锚点下「我的笔迹」id。
  List<String> linkedMyNoteIds(String aiNoteId) {
    final n = _aiNotes[aiNoteId];
    if (n == null) throw ValidationError('未找到 AI 笔记 $aiNoteId');
    return List<String>.unmodifiable(
        _links[n.anchorId]?.myNoteIds ?? const <String>[]);
  }

  /// 反向：从一份「我的笔记」id 找到同锚点下的 AI 笔记 id。
  List<String> linkedAiNoteIds(String myNoteId) {
    final n = _myNotes[myNoteId];
    if (n == null) throw ValidationError('未找到我的笔记 $myNoteId');
    return List<String>.unmodifiable(
        _links[n.anchorId]?.aiNoteIds ?? const <String>[]);
  }

  /// 双向跳转：给任一笔记 id，返回另一侧关联的笔记实体。
  List<NoteDocument> linkedNotes(String noteId) {
    final n = _find(noteId);
    final l = _links[n.anchorId];
    return n.owner == 'ai'
        ? _idsToNotes(l?.myNoteIds ?? const <String>[], _myNotes)
        : _idsToNotes(l?.aiNoteIds ?? const <String>[], _aiNotes);
  }

  // ---------------------------------------------------------------- 显隐（接 F4）
  bool noteVisibleFor(String sessionId) => prefs.noteVisibleFor(sessionId);

  /// 关闭 / 开启内置笔记区（D 通道）。只改开关，不删任何数据。
  void setNoteAreaVisible(String sessionId, bool visible) =>
      prefs.setOverride(sessionId, SessionOverrides(noteVisible: visible));

  /// 渲染态：隐藏时 D 通道不渲染，A/C 归档引用仍可见。
  List<NoteDocument> renderedNotes(String sessionId, String anchorId) {
    final all = <NoteDocument>[
      ...aiNotesAt(anchorId),
      ...myNotesAt(anchorId),
    ];
    if (noteVisibleFor(sessionId)) {
      return List<NoteDocument>.unmodifiable(all);
    }
    return List<NoteDocument>.unmodifiable(
        all.where((n) => n.channel != 'D').toList());
  }

  /// 归档检索：**不受显隐影响**，隐藏内置笔记区后照样命中 A/C。
  List<NoteDocument> searchArchive(String anchorId) {
    final all = <NoteDocument>[
      ...aiNotesAt(anchorId),
      ...myNotesAt(anchorId),
    ];
    return List<NoteDocument>.unmodifiable(
        all.where((n) => n.channel != 'D').toList());
  }

  /// A 通道外部原件 → C 通道归档快照（Notein 导出 PDF 回来）。
  /// 原件保持外部引用不变；只有这份新建的 C 归档可被 AI 处理。
  NoteDocument archiveSnapshot(String externalNoteId, String archiveRef) {
    final src = _find(externalNoteId);
    if (src.channel != 'A') {
      throw ValidationError('只有 A 通道外部原件可归档为 C 通道快照');
    }
    if (archiveRef.trim().isEmpty) {
      throw ValidationError('归档引用不可为空');
    }
    final ref = archiveRef.startsWith('archive:')
        ? archiveRef
        : 'archive:$archiveRef';
    _seq++;
    final archived = NoteDocument(
      id: makeId('ARCH', _seq),
      owner: 'mine',
      channel: 'C',
      contentType: 'pdf',
      anchorId: src.anchorId,
      blocks: <String>[ref],
      aiGenerated: false,
    );
    addMyNote(archived);
    return archived;
  }

  // ---------------------------------------------------------------- OCR 摘要
  /// OCR 只作可检索摘要，独立存储；原件 blocks 一字不改。
  void addOcrSummary(String noteId, String text) {
    final n = _find(noteId);
    final before = List<String>.from(n.blocks);
    _ocr[noteId] = OcrSummary(
      noteId: noteId,
      anchorId: n.anchorId,
      text: text,
    );
    // 自校验：任何把摘要写回原件的行为都视为违规。
    if (!jsonEquals(n.blocks, before)) {
      throw ValidationError('OCR 摘要不得覆盖原始笔迹');
    }
  }

  OcrSummary? ocrSummaryFor(String noteId) => _ocr[noteId];

  /// 原件只读视图（用于证明摘要与原件分离）。
  List<String> originalBlocks(String noteId) =>
      List<String>.unmodifiable(_find(noteId).blocks);

  /// 识别错了直接丢弃摘要重来，不污染数据。
  void dropOcrSummary(String noteId) => _ocr.remove(noteId);

  /// 系统层面明确拒绝「用 OCR 结果覆盖原件」。
  Never overwriteOriginalWithOcr() => throw ValidationError(
      '禁止用 OCR / 视觉识别结果覆盖原始笔迹（只作可检索摘要）');

  // ---------------------------------------------------------------- AI 外发
  /// **唯一**产生外发的入口：必须主动触发 + 白名单授权 + C 通道归档。
  /// 只送该锚点下的一小段（单个 block，截断到 maxChars），并脱敏。
  OutboundRecord requestAiAssist({
    required String noteId,
    String purpose = 'explainInk',
    int maxChars = defaultMaxChars,
    int blockIndex = 0,
  }) {
    if (maxChars <= 0 || maxChars > defaultMaxChars) {
      throw ValidationError(
          '最小必要外发：单次片段上限 $defaultMaxChars 字符，非法 $maxChars');
    }
    final n = _find(noteId);
    if (!prefs.allowOutbound(outboundKind)) {
      throw ValidationError(
          '默认不把笔记交给 AI：外发白名单未开启 "$outboundKind"');
    }
    if (n.channel != 'C') {
      throw ValidationError(
          'A 通道原件始终是外部引用，只有 C 通道归档回来的那份可被处理（当前 ${n.channel}）');
    }
    if (n.blocks.isEmpty) {
      throw ValidationError('该 C 归档无可送审片段');
    }
    if (blockIndex < 0 || blockIndex >= n.blocks.length) {
      throw ValidationError('片段下标越界: $blockIndex');
    }
    final raw = n.blocks[blockIndex];
    final clipped = raw.length > maxChars ? raw.substring(0, maxChars) : raw;
    final excerpt = _redact(clipped);
    final rec = OutboundRecord(
      anchorId: n.anchorId,
      noteId: n.id,
      channel: 'C',
      purpose: purpose,
      excerpt: excerpt,
      charCount: excerpt.length,
      redacted: true,
    );
    _outbound.add(rec);
    return rec;
  }

  /// 脱敏：疑似密钥 / 手机号 / 邮箱 / 凭证赋值一律遮蔽。
  String _redact(String s) {
    var out = s;
    out = out.replaceAll(
        RegExp(r'sk-[A-Za-z0-9_-]{8,}'), '[REDACTED_KEY]');
    out = out.replaceAll(RegExp(r'1[3-9]\d{9}'), '[REDACTED_PHONE]');
    out = out.replaceAll(
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[REDACTED_EMAIL]');
    out = out.replaceAll(
        RegExp(r'(api[_-]?key|token)\s*[:=]\s*\S+', caseSensitive: false),
        '[REDACTED_CRED]');
    return out;
  }

  // ---------------------------------------------------------------- 数据带走
  /// 三份独立实体文件，直接并入 .studypack 的固定 13 类实体。
  Map<String, List<Map<String, dynamic>>> packageEntities() => {
        'ai_notes.json': _aiNotes.values.map((n) => n.toJson()).toList(),
        'my_notes.json': _myNotes.values.map((n) => n.toJson()).toList(),
        'anchor_links.json': _links.values.map((l) => l.toJson()).toList(),
      };

  /// OCR 摘要与外发台账作为 assets 带走（不占 13 类实体文件名）。
  /// 外发 excerpt 二次脱敏，保证凭证不进包。
  Map<String, String> packageAssets() {
    final ocr = _ocr.values.map((s) => s.toJson()).toList();
    final outbound = _outbound.map((r) {
      final j = r.toJson();
      j['excerpt'] = _redact(r.excerpt);
      return j;
    }).toList();
    return <String, String>{
      'notes/ocr_summaries.json': jsonEncode(ocr),
      'notes/outbound_log.json': jsonEncode(outbound),
    };
  }

  /// 从 .studypack 的三份实体文件恢复（链接索引以导出文件为准）。
  static NotesSubsystem fromPackageEntities(
    Map<String, List<Map<String, dynamic>>> entities, {
    PreferencesLayer? prefs,
  }) {
    final sub = NotesSubsystem(prefs: prefs);
    for (final e in entities['ai_notes.json'] ?? const <Map<String, dynamic>>[]) {
      sub._register(sub._aiNotes, NoteDocument.fromJson(e),
          isAi: true, registerArchive: false);
    }
    for (final e in entities['my_notes.json'] ?? const <Map<String, dynamic>>[]) {
      sub._register(sub._myNotes, NoteDocument.fromJson(e),
          isAi: false, registerArchive: false);
    }
    sub._links.clear();
    for (final e in entities['anchor_links.json'] ?? const <Map<String, dynamic>>[]) {
      final l = AnchorLink.fromJson(e);
      sub._links[l.anchorId] = l;
    }
    return sub;
  }

  // ---------------------------------------------------------------- 全量往返
  @override
  Map<String, dynamic> toJson() => {
        'aiNotes': _aiNotes.values.map((n) => n.toJson()).toList(),
        'myNotes': _myNotes.values.map((n) => n.toJson()).toList(),
        'links': _links.values.map((l) => l.toJson()).toList(),
        'ocr': _ocr.values.map((s) => s.toJson()).toList(),
        'outbound': _outbound.map((r) => r.toJson()).toList(),
        'seq': _seq,
        'prefs': prefs.toJson(),
      };

  static NotesSubsystem fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    final prefs = m['prefs'] == null
        ? PreferencesLayer()
        : PreferencesLayer.fromJson(m['prefs']);
    final sub = NotesSubsystem(prefs: prefs);
    for (final e in (m['aiNotes'] as List)) {
      sub._register(sub._aiNotes, NoteDocument.fromJson(e),
          isAi: true, registerArchive: false);
    }
    for (final e in (m['myNotes'] as List)) {
      sub._register(sub._myNotes, NoteDocument.fromJson(e),
          isAi: false, registerArchive: false);
    }
    sub._links.clear();
    for (final e in (m['links'] as List)) {
      final l = AnchorLink.fromJson(e);
      sub._links[l.anchorId] = l;
    }
    for (final e in (m['ocr'] as List)) {
      final s = OcrSummary.fromJson(e);
      sub._ocr[s.noteId] = s;
    }
    sub._outbound.addAll(
        (m['outbound'] as List).map((e) => OutboundRecord.fromJson(e)));
    sub._seq = m['seq'] as int;
    return sub;
  }
}
