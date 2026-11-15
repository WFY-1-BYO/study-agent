/// F15 · 用户知识库（收纳 / 文库）模型层（2.x 新增）。
///
/// 设计要点（承接「我的要求」与 2.x 蓝图）：
///  - 知识库是**本地结构化数据库**，每条目带 来源 / 知识点 / 难度 / 母题 / 变式档 字段，可检索；
///  - AI 出题时优先检索「我的」真实母题，再做变式，不凭空造题；
///  - 数据全本机，随 `.studypack` 整包带走；
///  - `onlineSupplement`（联网补充）仅作可选开关：默认只对你的自有资料做匹配，
///    开启后才允许对接你自行配置的在线权威源（如学科网），且只存引用不存正文。
///
/// 零第三方依赖，兼容 Dart 2.17。
library study_agent.knowledge_base;

import 'core.dart';
import 'models.dart';

class KB {
  static const notebookTypes = ['pdf', 'notes', 'folder'];
  static const difficulties = ['basic', 'medium', 'hard'];
  static const variantLevels = ['L1', 'L2', 'L3', 'L4'];
  static const sources = ['my', 'authoritative', 'online'];
}

// ------------------------------------------------------------------ 笔记本
class Notebook implements Entity {
  final String id;
  final String title;
  final String subject;
  final String coverColor;
  final String type;
  final bool favorited;
  final String createdDate;

  Notebook({
    required this.id,
    required this.title,
    this.subject = '',
    this.coverColor = '#6366F1',
    this.type = 'notes',
    this.favorited = false,
    required this.createdDate,
  }) {
    if (id.trim().isEmpty) throw ValidationError('Notebook.id 不可为空');
    if (title.trim().isEmpty) throw ValidationError('Notebook.title 不可为空');
    ensureEnum(type, KB.notebookTypes, 'Notebook.type');
    if (!coverColor.startsWith('#')) {
      throw ValidationError('Notebook.coverColor 必须为 #RRGGBB 十六进制');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'coverColor': coverColor,
        'type': type,
        'favorited': favorited,
        'createdDate': createdDate,
      };

  static Notebook fromJson(Object? json) {
    final m = _map(json, 'Notebook');
    return Notebook(
      id: _str(m, 'id', 'Notebook'),
      title: _str(m, 'title', 'Notebook'),
      subject: _optStr(m, 'subject') ?? '',
      coverColor: _optStr(m, 'coverColor') ?? '#6366F1',
      type: _str(m, 'type', 'Notebook'),
      favorited: _bool(m, 'favorited', 'Notebook'),
      createdDate: _str(m, 'createdDate', 'Notebook'),
    );
  }
}

// ------------------------------------------------------------------ 条目（题）
class KbEntry implements Entity {
  final String id;
  final String notebookId;
  final String question;
  final String knowledgePoint;
  final String difficulty;
  final String? motherId;
  final String variantLevel;
  final String source;
  final String sourceFile;
  final String answer;
  final List<String> tags;
  final String createdDate;

  KbEntry({
    required this.id,
    required this.notebookId,
    required this.question,
    this.knowledgePoint = '',
    this.difficulty = 'medium',
    this.motherId,
    this.variantLevel = 'L1',
    this.source = 'my',
    this.sourceFile = '',
    this.answer = '',
    List<String>? tags,
    required this.createdDate,
  })  : tags = tags ?? <String>[] {
    if (id.trim().isEmpty) throw ValidationError('KbEntry.id 不可为空');
    if (notebookId.trim().isEmpty) {
      throw ValidationError('KbEntry.notebookId 不可为空');
    }
    if (question.trim().isEmpty) {
      throw ValidationError('KbEntry.question 不可为空（禁止空题入库）');
    }
    ensureEnum(difficulty, KB.difficulties, 'KbEntry.difficulty');
    ensureEnum(variantLevel, KB.variantLevels, 'KbEntry.variantLevel');
    ensureEnum(source, KB.sources, 'KbEntry.source');
    if (source.trim().isEmpty) {
      throw ValidationError('KbEntry.source 必填（禁止无来源题）');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'notebookId': notebookId,
        'question': question,
        'knowledgePoint': knowledgePoint,
        'difficulty': difficulty,
        'motherId': motherId,
        'variantLevel': variantLevel,
        'source': source,
        'sourceFile': sourceFile,
        'answer': answer,
        'tags': tags,
        'createdDate': createdDate,
      };

  static KbEntry fromJson(Object? json) {
    final m = _map(json, 'KbEntry');
    return KbEntry(
      id: _str(m, 'id', 'KbEntry'),
      notebookId: _str(m, 'notebookId', 'KbEntry'),
      question: _str(m, 'question', 'KbEntry'),
      knowledgePoint: _optStr(m, 'knowledgePoint') ?? '',
      difficulty: _str(m, 'difficulty', 'KbEntry'),
      motherId: _optStr(m, 'motherId'),
      variantLevel: _optStr(m, 'variantLevel') ?? 'L1',
      source: _str(m, 'source', 'KbEntry'),
      sourceFile: _optStr(m, 'sourceFile') ?? '',
      answer: _optStr(m, 'answer') ?? '',
      tags: _strs(m, 'tags', 'KbEntry'),
      createdDate: _str(m, 'createdDate', 'KbEntry'),
    );
  }
}

// ------------------------------------------------------------------ 知识库总控
class KnowledgeBase implements Entity {
  final List<Notebook> notebooks;
  final List<KbEntry> entries;
  final bool onlineSupplement;

  KnowledgeBase({
    List<Notebook>? notebooks,
    List<KbEntry>? entries,
    this.onlineSupplement = false,
  })  : notebooks = notebooks ?? <Notebook>[],
        entries = entries ?? <KbEntry>[];

  /// 某笔记本条目数（收纳页红点计数）。
  int countOf(String notebookId) =>
      entries.where((e) => e.notebookId == notebookId).length;

  Notebook? notebook(String id) {
    for (final n in notebooks) {
      if (n.id == id) return n;
    }
    return null;
  }

  void addNotebook(Notebook n) {
    if (notebooks.any((x) => x.id == n.id)) {
      throw ValidationError('笔记本 id 重复: ${n.id}');
    }
    notebooks.add(n);
  }

  void addEntry(KbEntry e) {
    if (!notebooks.any((n) => n.id == e.notebookId)) {
      throw ValidationError('条目所属笔记本不存在: ${e.notebookId}');
    }
    if (entries.any((x) => x.id == e.id)) {
      throw ValidationError('条目 id 重复: ${e.id}');
    }
    entries.add(e);
  }

  void removeEntry(String id) => entries.removeWhere((e) => e.id == id);

  /// 按关键词检索：题干 / 知识点 / 标签 命中即返回。
  List<KbEntry> search(String q) {
    final k = q.trim().toLowerCase();
    if (k.isEmpty) return List<KbEntry>.unmodifiable(entries);
    return List<KbEntry>.unmodifiable(entries
        .where((e) =>
            e.question.toLowerCase().contains(k) ||
            e.knowledgePoint.toLowerCase().contains(k) ||
            e.tags.any((t) => t.toLowerCase().contains(k)))
        .toList());
  }

  /// 按知识点检索（AI 出题前先用它匹配母题）。
  List<KbEntry> byKnowledgePoint(String kp) {
    final k = kp.trim().toLowerCase();
    if (k.isEmpty) return const [];
    return List<KbEntry>.unmodifiable(entries
        .where((e) => e.knowledgePoint.toLowerCase().contains(k))
        .toList());
  }

  /// 给 AI 的最小必要上下文：返回命中知识点的最相关母题（最多 limit 条）。
  /// 只含题干 / 知识点 / 难度 / 母题关系，绝不外发 sourceFile 等隐私字段。
  List<Map<String, dynamic>> retrievalForAi(String knowledgePoint,
      {int limit = 5}) {
    final hits = byKnowledgePoint(knowledgePoint);
    final out = hits
        .take(limit)
        .map((e) => <String, dynamic>{
              'id': e.id,
              'question': e.question,
              'knowledgePoint': e.knowledgePoint,
              'difficulty': e.difficulty,
              'motherId': e.motherId,
            })
        .toList();
    return List<Map<String, dynamic>>.unmodifiable(out);
  }

  @override
  Map<String, dynamic> toJson() => {
        'notebooks': notebooks.map((n) => n.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'onlineSupplement': onlineSupplement,
      };

  static KnowledgeBase fromJson(Object? json) {
    final m = _map(json, 'KnowledgeBase');
    return KnowledgeBase(
      notebooks: _maps(m, 'notebooks', 'KnowledgeBase')
          .map(Notebook.fromJson)
          .toList(),
      entries: _maps(m, 'entries', 'KnowledgeBase')
          .map(KbEntry.fromJson)
          .toList(),
      onlineSupplement: _bool(m, 'onlineSupplement', 'KnowledgeBase'),
    );
  }
}

// ------------------------------------------------------------------ JSON 助手（与 models.dart 同款，保持零依赖）
Map<String, dynamic> _map(Object? v, String w) {
  if (v is! Map) throw ValidationError('$w 应为对象');
  return Map<String, dynamic>.from(v);
}

String _str(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! String) throw ValidationError('$w.$k 应为字符串');
  return v;
}

String? _optStr(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v == null ? null : v as String;
}

List<String> _strs(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! List) throw ValidationError('$w.$k 应为数组');
  return v.map((e) => e.toString()).toList();
}

bool _bool(Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! bool) throw ValidationError('$w.$k 应为布尔');
  return v;
}

List<Map<String, dynamic>> _maps(
    Map<String, dynamic> m, String k, String w) {
  final v = m[k];
  if (v is! List) throw ValidationError('$w.$k 应为数组');
  return v.map((e) => _map(e, '$w.$k[]')).toList();
}
