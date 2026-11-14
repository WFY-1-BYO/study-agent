/// F12 · 资源适配器与高考对齐约束层（PRD §4 F12）。
///
/// 四种统一接入模式：A 分屏/跳转 · C 文件桥接 · ref 引用登记+跳转 · local 本地导入。
/// 硬约束：
///  - 缺 `source` 的资源被拒绝；**禁止无来源题冒充高考题**；
///  - 变式题必须挂靠真实母题 `parentId`，且不得标为真题；
///  - B站只存元数据（标题 / BV号 / 时长）+ 跳转引用，**不含视频二进制**；
///  - 学科网内容不进包；`.studypack` 只带走引用与标签；
///  - 考纲标签必须能映射到 `ExamProfile` 知识点树；教材版本对齐人教 A 版；
///  - AI 从「生成者」降级为「检索匹配 + 讲解 + 基于真实母题的变式」，禁止凭空造题；
///  - 资料优先级：自己的资料 > 权威题库 > B站视频(仅跳转) > AI 生成(受限)。
///
/// 零第三方依赖，兼容 Dart 2.17。
library study_agent.resources;

import 'dart:convert';

import 'core.dart';
import 'models.dart';
import 'studypack.dart';

/// 四种统一接入通道。
class ResourceChannel {
  static const List<String> all = ['A', 'C', 'ref', 'local'];
  static const Map<String, String> labels = {
    'A': '系统分屏 / 一键跳转（外部引用）',
    'C': 'PDF / 文件桥接归档',
    'ref': '引用登记 + 跳转（B站等）',
    'local': '本地导入（自己的资料）',
  };
}

/// 资料优先级（从高到低）。
class SourceTier {
  static const String own = 'own';
  static const String authoritative = 'authoritative';
  static const String bilibili = 'bilibili';
  static const String aiGenerated = 'aiGenerated';

  static const List<String> order = [own, authoritative, bilibili, aiGenerated];
  static const Map<String, String> labels = {
    own: '自己的资料',
    authoritative: '权威题库',
    bilibili: 'B站视频（仅跳转）',
    aiGenerated: 'AI 生成（受限：基于真实母题的变式）',
  };
}

/// 拒绝任何内嵌二进制 / 第三方版权正文：只准存引用与标签。
void assertNoEmbeddedContent(Object? value, [String where = 'payload']) {
  if (value is Map) {
    for (final e in value.entries) {
      final k = e.key.toString().toLowerCase();
      if (StudyPack.forbiddenKeys.contains(k) ||
          k == 'binary' ||
          k.endsWith('binary') ||
          k.contains('embedded') ||
          k.contains('base64')) {
        throw ValidationError(
            '$where 含二进制 / 第三方版权正文字段 "${e.key}"，禁止进包（只存引用）');
      }
      assertNoEmbeddedContent(e.value, '$where.${e.key}');
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      assertNoEmbeddedContent(value[i], '$where[$i]');
    }
  } else if (value is String) {
    if (value.startsWith('data:') ||
        value.startsWith('base64:') ||
        value.contains(';base64,')) {
      throw ValidationError(
          '$where 含内嵌二进制（data: / base64:），禁止进包（只存引用）');
    }
  }
}

/// 接入描述：**只存引用 + 元数据**，绝不含视频 / PDF 二进制正文。
class AccessDescriptor implements Entity {
  final String resourceId;
  final String channel;
  final String tier;
  final String uri; // 跳转地址 / 归档引用 / 本地路径
  final String title;
  final String? bv;
  final int? durationSeconds;
  final String? provider;

  AccessDescriptor({
    required this.resourceId,
    required this.channel,
    required this.tier,
    required this.uri,
    this.title = '',
    this.bv,
    this.durationSeconds,
    this.provider,
  }) {
    ensureEnum(channel, ResourceChannel.all, 'AccessDescriptor.channel');
    ensureEnum(tier, SourceTier.order, 'AccessDescriptor.tier');
    if (uri.trim().isEmpty) {
      throw ValidationError('AccessDescriptor.uri 必填（只存引用，不存正文）');
    }
    if (tier == SourceTier.bilibili) {
      if (channel != 'ref') {
        throw ValidationError('B站资源只做引用登记 + 跳转（channel 必须为 ref）');
      }
      if (bv == null || bv!.trim().isEmpty) {
        throw ValidationError('B站资源必须登记 BV 号');
      }
    }
    if (channel == 'ref' && tier != SourceTier.bilibili) {
      throw ValidationError('ref 通道只用于 B站引用登记');
    }
    if (provider == '学科网' && !uri.startsWith('https://')) {
      throw ValidationError(
          '学科网内容不进包：只允许 https:// 外部引用，不得内嵌正文');
    }
    // 自校验：序列化结果里不得出现任何二进制 / 内嵌正文。
    assertNoEmbeddedContent(toJson(), 'AccessDescriptor');
  }

  @override
  Map<String, dynamic> toJson() => {
        'resourceId': resourceId,
        'channel': channel,
        'tier': tier,
        'uri': uri,
        'title': title,
        'bv': bv,
        'durationSeconds': durationSeconds,
        'provider': provider,
      };

  static AccessDescriptor fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return AccessDescriptor(
      resourceId: m['resourceId'] as String,
      channel: m['channel'] as String,
      tier: m['tier'] as String,
      uri: m['uri'] as String,
      title: m['title'] as String,
      bv: m['bv'] as String?,
      durationSeconds: m['durationSeconds'] as int?,
      provider: m['provider'] as String?,
    );
  }
}

/// 资源适配器主入口：四通道统一接入 + 高考对齐校验 + 优先级。
class ResourceAdapter implements Entity {
  final ExamProfile profile;

  final List<Resource> _resources = <Resource>[];
  final Map<String, AccessDescriptor> _access = <String, AccessDescriptor>{};
  int _seq = 0;

  ResourceAdapter({ExamProfile? profile})
      : profile = profile ?? ExamProfile.shenzhen();

  List<Resource> get resources =>
      List<Resource>.unmodifiable(_resources);

  // ---------------------------------------------------------------- 对齐校验
  /// 验收⑥：考纲标签必须命中 `ExamProfile` 知识点树（含分支 / 叶子）。
  KnowledgeNode assertExamTagMapped(String examTag) {
    if (examTag.trim().isEmpty) {
      throw ValidationError('考纲标签 examTag 不可为空');
    }
    final node = profile.knowledgeTree.find(examTag);
    if (node == null) {
      throw ValidationError(
          '考纲标签 "$examTag" 未映射到 ${profile.textbook} 知识点树');
    }
    return node;
  }

  /// 验收③：变式题必须挂靠已登记的真实母题，且不冒充高考真题。
  void assertValidVariant(Resource r) {
    if (r.parentId == null || r.parentId!.isEmpty) {
      throw ValidationError('变式题必须挂靠真实母题 parentId（禁止无来源题）');
    }
    if (!_resources.any((x) => x.id == r.parentId)) {
      throw ValidationError('parentId "${r.parentId}" 必须指向已登记的真实母题');
    }
    if (r.source.trim().isEmpty) {
      throw ValidationError('变式题必须继承母题来源 source');
    }
    if (r.isGaokao) {
      throw ValidationError('变式题不得标记为高考真题（禁止冒充）');
    }
  }

  Resource _byId(String id) {
    for (final r in _resources) {
      if (r.id == id) return r;
    }
    throw ValidationError('未登记的资源 $id');
  }

  // ---------------------------------------------------------------- 四通道接入
  /// 统一入口：四通道产出**同一种** `Resource` + `AccessDescriptor`，
  /// 下游（F10 变式 / F8 会话）消费不变，接新服务不改主流程。
  Resource ingest({
    required String channel,
    required String tier,
    required String source,
    required String uri,
    required String examTag,
    String? id,
    String? textbookTag,
    String yearRegion = '',
    String questionType = '',
    int score = 0,
    String difficulty = 'medium',
    String variantLevel = 'L1',
    bool isGaokao = false,
    String? parentId,
    String title = '',
    String? bv,
    int? durationSeconds,
    String? provider,
  }) {
    ensureEnum(channel, ResourceChannel.all, 'ingest.channel');
    ensureEnum(tier, SourceTier.order, 'ingest.tier');

    // 验收①：缺 source 直接拒绝（含纯空白）。
    if (source.trim().isEmpty) {
      throw ValidationError('Resource.source 必填（禁止无来源题）');
    }
    // 验收④：任何内嵌二进制 / 版权正文都拒绝。
    assertNoEmbeddedContent(<String, dynamic>{
      'source': source,
      'uri': uri,
      'title': title,
      'bv': bv,
      'provider': provider,
    }, 'ingest');
    if (uri.trim().isEmpty) {
      throw ValidationError('接入引用 uri 必填');
    }

    // 验收②：无来源题不得标记为高考题。
    if (isGaokao) {
      if (tier == SourceTier.bilibili || tier == SourceTier.aiGenerated) {
        throw ValidationError(
            '无来源题不得标记为「高考题」（B站 / AI 生成禁止冒充真题）');
      }
      if (yearRegion.trim().isEmpty) {
        throw ValidationError('高考真题必须带年份地区 yearRegion');
      }
      if (parentId != null) {
        throw ValidationError('变式题不得标记为高考真题');
      }
    }

    // AI 生成资源只能经 attachVariant 基于真实母题产出（禁止凭空造题）。
    if (tier == SourceTier.aiGenerated) {
      throw ValidationError(
          'AI 生成资源只能经 attachVariant() 基于真实母题产出，禁止凭空造题');
    }

    // 变式题统一走 attachVariant，避免接入层混入半合法变式。
    if (variantLevel != 'L1' || parentId != null) {
      throw ValidationError('变式题请走 attachVariant()，接入层只登记原始资源');
    }

    // 验收⑥：考纲标签 / 教材版本 / 题型对齐。
    assertExamTagMapped(examTag);
    final tag = textbookTag ?? profile.textbook;
    if (!tag.contains('人教 A 版')) {
      throw ValidationError('教材版本未对齐人教 A 版: "$tag"');
    }
    if (questionType.isNotEmpty &&
        !profile.questionTypes.any((q) => q['name'] == questionType)) {
      throw ValidationError('题型 "$questionType" 不在 ${profile.paper} 题型表内');
    }
    if (score < 0) throw ValidationError('分值不可为负');

    final rid = id ?? makeId('R', ++_seq);
    if (_resources.any((r) => r.id == rid)) {
      throw ValidationError('资源 id 重复: $rid');
    }
    final resource = Resource(
      id: rid,
      source: source,
      textbookTag: tag,
      examTag: examTag,
      yearRegion: yearRegion,
      questionType: questionType,
      score: score,
      difficulty: difficulty,
      variantLevel: variantLevel,
      isGaokao: isGaokao,
    );
    final descriptor = AccessDescriptor(
      resourceId: rid,
      channel: channel,
      tier: tier,
      uri: uri,
      title: title,
      bv: bv,
      durationSeconds: durationSeconds,
      provider: provider,
    );
    _resources.add(resource);
    _access[rid] = descriptor;
    return resource;
  }

  /// AI 侧唯一「出题」入口：基于已登记的真实母题做变式。
  /// 自动继承母题来源 / 标签，强制 `parentId`，恒 `isGaokao=false`。
  Resource attachVariant({
    required String motherId,
    String difficulty = 'medium',
    String variantLevel = 'L2',
    String? id,
  }) {
    if (motherId.trim().isEmpty) {
      throw ValidationError('变式题必须指定真实母题 motherId');
    }
    final mother = _byId(motherId);
    if (mother.parentId != null) {
      throw ValidationError('母题必须是原始题，不得基于变式再变式');
    }
    final rid = id ?? makeId('V', ++_seq);
    if (_resources.any((r) => r.id == rid)) {
      throw ValidationError('资源 id 重复: $rid');
    }
    final r = Resource(
      id: rid,
      source: mother.source,
      textbookTag: mother.textbookTag,
      examTag: mother.examTag,
      yearRegion: mother.yearRegion,
      questionType: mother.questionType,
      score: mother.score,
      difficulty: difficulty,
      parentId: mother.id,
      variantLevel: variantLevel,
      isGaokao: false,
    );
    assertValidVariant(r); // 自校验：生成结果也必须满足硬约束
    _resources.add(r);
    _access[rid] = AccessDescriptor(
      resourceId: rid,
      channel: 'local',
      tier: SourceTier.aiGenerated,
      uri: 'local://variant/$rid',
      title: '基于 ${mother.id} 的变式（${variantLevel}）',
    );
    return r;
  }

  /// 系统层面明确拒绝「凭空造题」。
  Never generateFromScratch() => throw ValidationError(
      'AI 已从「生成者」降级：禁止凭空造题，只能检索匹配 / 讲解 / 基于真实母题做变式');

  // ---------------------------------------------------------------- 查询
  AccessDescriptor resolve(String resourceId) {
    final d = _access[resourceId];
    if (d == null) {
      throw ValidationError('资源 $resourceId 无接入描述');
    }
    return d;
  }

  /// 资料优先级排序：自己的资料 > 权威题库 > B站视频 > AI 生成。
  List<Resource> priorityOrdered() {
    int rank(String id) => SourceTier.order.indexOf(_access[id]!.tier);
    final out = _resources.toList();
    out.sort((a, b) => rank(a.id).compareTo(rank(b.id)));
    return List<Resource>.unmodifiable(out);
  }

  /// 按考纲标签检索（先校验标签映射）。
  List<Resource> resourcesForExamTag(String examTag) {
    assertExamTagMapped(examTag);
    return List<Resource>.unmodifiable(
        _resources.where((r) => r.examTag == examTag).toList());
  }

  // ---------------------------------------------------------------- 数据带走
  /// `.studypack` 只带走引用与标签（Resource 本就只有元数据）。
  Map<String, List<Map<String, dynamic>>> packageEntities() => {
        'resources.json': _resources.map((r) => r.toJson()).toList(),
      };

  Map<String, String> packageAssets() => {
        'resources/access.json':
            jsonEncode(_access.values.map((d) => d.toJson()).toList()),
      };

  @override
  Map<String, dynamic> toJson() => {
        'profile': profile.toJson(),
        'resources': _resources.map((r) => r.toJson()).toList(),
        'access': _access.values.map((d) => d.toJson()).toList(),
        'seq': _seq,
      };

  static ResourceAdapter fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    final a = ResourceAdapter(
        profile: ExamProfile.fromJson(m['profile']));
    for (final e in (m['resources'] as List)) {
      a._resources.add(Resource.fromJson(e));
    }
    for (final e in (m['access'] as List)) {
      final d = AccessDescriptor.fromJson(e);
      a._access[d.resourceId] = d;
    }
    a._seq = m['seq'] as int;
    return a;
  }
}
