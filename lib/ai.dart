/// F13 · AI 服务层（可插拔，PRD §4 F13）。
///
/// 硬约束：
///  - **能力接口固定**（9 个），调用方只给 capability + 最小上下文，不依赖具体模型；
///  - **Provider 适配器可换**（DeepSeekAdapter / MockAdapter），换模型只改配置，主流程零改动；
///  - `api_key` 存系统密钥库（ApiKeyVault）、**不进 `.studypack`**、不进日志 / 导出；
///  - **最小必要上下文**：按能力白名单裁剪，凭证字段剔除，超限拒绝；
///  - **优雅降级**：无 key / 无网 / 白名单未开时 AI 节点标「待处理」，
///    不阻塞看视频、记笔记、做已有题目；
///  - 截图识别产出**结构化数据**（课表字段），而非 PDF 文本；
///  - 默认 `deepseek-flash`；「4.1 Pro」非正式在售型号，禁止写入配置。
///
/// 零第三方依赖（不做真实网络 I/O，传输层可注入），兼容 Dart 2.17。
library study_agent.ai;

import 'dart:convert';

import 'core.dart';
import 'models.dart';
import 'preferences.dart';
import 'studypack.dart';

/// 固定的 9 个 AI 能力接口 + 每个能力允许外发的最小上下文字段。
class AiCapability {
  static const List<String> all = [
    'analyzeWeakness',
    'retrieveResources',
    'generateQuestions',
    'gradeQuiz',
    'attributeError',
    'correctRestatement',
    'generateNote',
    'generateReviewPlan',
    'recognizeScreenshot',
  ];

  /// 最小必要上下文白名单：不在表内的字段一律不外发。
  static const Map<String, List<String>> allowedContext = {
    'analyzeWeakness': ['knowledgeNodeId', 'quizScores', 'evidence'],
    'retrieveResources': ['knowledgeNodeId', 'slotMinutes', 'examTag'],
    'generateQuestions': ['motherIds', 'weakPointId', 'intent'],
    'gradeQuiz': ['resourceIds', 'answers'],
    'attributeError': ['wrongItems', 'restatements'],
    'correctRestatement': ['restatement', 'knowledgeNodeId'],
    'generateNote': ['sessionId', 'restatements', 'corrections'],
    'generateReviewPlan': ['planId', 'passedSessions'],
    'recognizeScreenshot': ['imageRef', 'hint'],
  };
}

/// 拒绝任何凭证字段 / 明文 key 出现在外发上下文或导出数据里。
void assertNoCredentials(Object? value, [String where = 'data']) {
  if (value is Map) {
    for (final e in value.entries) {
      final k = e.key.toString().toLowerCase();
      if (StudyPack.sensitiveKeys.contains(k) ||
          k.contains('apikey') ||
          k.contains('secret') ||
          k.contains('credential')) {
        throw ValidationError(
            '$where 含凭证字段 "${e.key}"，禁止外发 / 进包');
      }
      assertNoCredentials(e.value, '$where.${e.key}');
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      assertNoCredentials(value[i], '$where[$i]');
    }
  } else if (value is String && value.trim().startsWith('sk-')) {
    throw ValidationError(
        '$where 含疑似 API key 明文（sk- 开头），禁止外发 / 进包');
  }
}

/// 发给 Provider 的请求：**不含 modelId / apiKey**，只有能力 + 已裁剪上下文。
class AiRequest implements Entity {
  final String capability;
  final Map<String, dynamic> context;

  AiRequest({required this.capability, required this.context}) {
    ensureEnum(capability, AiCapability.all, 'AiRequest.capability');
  }

  @override
  Map<String, dynamic> toJson() => {
        'capability': capability,
        'context': context,
      };

  static AiRequest fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return AiRequest(
      capability: m['capability'] as String,
      context: Map<String, dynamic>.from(m['context'] as Map),
    );
  }
}

/// Provider 统一返回结构。`status=pending` = AI 待处理（不阻塞非 AI 环节）。
class AiResponse implements Entity {
  final String status; // ok / pending
  final String capability;
  final String providerId;
  final String modelId;
  final Map<String, dynamic> data;
  final String? reason;

  AiResponse({
    required this.status,
    required this.capability,
    required this.providerId,
    required this.modelId,
    required this.data,
    this.reason,
  }) {
    if (status != 'ok' && status != 'pending') {
      throw ValidationError('AiResponse.status 非法: "$status"');
    }
  }

  bool get isPending => status == 'pending';

  @override
  Map<String, dynamic> toJson() => {
        'status': status,
        'capability': capability,
        'providerId': providerId,
        'modelId': modelId,
        'data': data,
        'reason': reason,
      };

  static AiResponse fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return AiResponse(
      status: m['status'] as String,
      capability: m['capability'] as String,
      providerId: m['providerId'] as String,
      modelId: m['modelId'] as String,
      data: Map<String, dynamic>.from(m['data'] as Map),
      reason: m['reason'] as String?,
    );
  }
}

/// 可审计调用台账：**只记上下文键名，不记值**，杜绝凭证泄漏。
class AiCallLog implements Entity {
  final String capability;
  final String providerId;
  final String status;
  final List<String> contextKeys;
  final String reason;

  AiCallLog({
    required this.capability,
    required this.providerId,
    required this.status,
    required this.contextKeys,
    required this.reason,
  });

  @override
  Map<String, dynamic> toJson() => {
        'capability': capability,
        'providerId': providerId,
        'status': status,
        'contextKeys': contextKeys,
        'reason': reason,
      };

  static AiCallLog fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return AiCallLog(
      capability: m['capability'] as String,
      providerId: m['providerId'] as String,
      status: m['status'] as String,
      contextKeys: (m['contextKeys'] as List).map((e) => e.toString()).toList(),
      reason: m['reason'] as String,
    );
  }
}

/// Provider 适配器统一接口：能力层只认这个契约。
abstract class AiProvider {
  String get id;
  String get modelId;
  bool get available;

  /// 可导出配置：**绝不含 apiKey 明文**。
  Map<String, dynamic> configJson();

  AiResponse call(AiRequest request);
}

/// 传输层：真实网络 I/O 由宿主注入；apiKey 只作为第三参数出现，不进 body。
typedef AiTransport = Map<String, dynamic> Function(
    String url, Map<String, dynamic> body, String apiKey);

Map<String, dynamic> _defaultTransport(
        String url, Map<String, dynamic> body, String apiKey) =>
    <String, dynamic>{'kind': 'unavailable', 'fields': <dynamic>[]};

/// 系统密钥库抽象：key 只从这里读，不落在可序列化配置里。
abstract class ApiKeyVault {
  String? read(String alias);
}

class MemoryKeyVault implements ApiKeyVault {
  final Map<String, String> _store;
  MemoryKeyVault([Map<String, String>? initial])
      : _store = initial ?? <String, String>{};

  @override
  String? read(String alias) => _store[alias];
}

/// 离线测试用 Provider：确定性返回，记录收到的请求以便断言最小上下文。
class MockProvider implements AiProvider {
  @override
  final String id;
  final bool online;
  int callCount = 0;
  AiRequest? lastRequest;

  MockProvider({this.id = 'mock', this.online = true});

  @override
  String get modelId => 'mock-offline';

  @override
  bool get available => online;

  @override
  Map<String, dynamic> configJson() => <String, dynamic>{
        'provider': 'mock',
        'id': id,
        'modelId': modelId,
      };

  @override
  AiResponse call(AiRequest request) {
    callCount++;
    lastRequest = request;
    if (request.capability == 'recognizeScreenshot') {
      return AiResponse(
        status: 'ok',
        capability: request.capability,
        providerId: id,
        modelId: modelId,
        data: <String, dynamic>{
          'kind': 'structured',
          'source': 'screenshot',
          'fields': <Map<String, dynamic>>[
            {'date': '2026-11-14', 'start': '07:00', 'end': '07:30',
              'course': '数学'},
            {'date': '2026-11-14', 'start': '13:00', 'end': '13:30',
              'course': '自习'},
          ],
          'blocks': <String>['教学管理 / 日程'],
        },
      );
    }
    return AiResponse(
      status: 'ok',
      capability: request.capability,
      providerId: id,
      modelId: modelId,
      data: <String, dynamic>{
        'result': 'ok',
        'capability': request.capability,
        'contextKeys': request.context.keys.toList(),
      },
    );
  }
}

/// DeepSeek Provider 适配器：配置可换、凭证隔离、传输层可注入。
class DeepSeekAdapter implements AiProvider {
  /// 官方在售且支持图像理解的默认型号。
  static const String defaultModelId = 'deepseek-flash';

  /// 系统密钥库条目别名。**不含 `api_key` 等凭证字样**，
  /// 使导出文本连凭证字段名都不出现（便于最严格的静态扫描）。
  static const String defaultKeyAlias = 'deepseek_key';

  /// 明确禁止写入配置的型号（非官方在售 / 不支持图像理解）。
  static const List<String> discouraged = [
    'DeepSeek4.1Pro',
    'deepseek-v4-pro',
  ];

  @override
  final String id = 'deepseek';

  final String baseUrl;
  final String modelId;
  final bool thinkingMode;
  final String keyAlias;
  final ApiKeyVault vault;
  final AiTransport transport;
  final bool online;
  final bool hasTransport;

  /// 传输层收到的最后一个 body（供测试断言，不含凭证）。
  Map<String, dynamic>? lastBody;
  String? lastUrl;

  DeepSeekAdapter({
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.modelId = defaultModelId,
    this.thinkingMode = false,
    this.keyAlias = defaultKeyAlias,
    ApiKeyVault? vault,
    AiTransport? transport,
    this.online = true,
  })  : vault = vault ?? MemoryKeyVault(),
        transport = transport ?? _defaultTransport,
        hasTransport = transport != null {
    if (modelId.trim().isEmpty) {
      throw ValidationError('DeepSeekAdapter.modelId 不可为空');
    }
    if (modelId.toLowerCase().contains('4.1')) {
      throw ValidationError(
          '「DeepSeek 4.1 Pro」非官方在售型号，禁止写入配置；默认 $defaultModelId');
    }
    if (!baseUrl.startsWith('https://')) {
      throw ValidationError('base_url 必须为 https://');
    }
  }

  @override
  bool get available =>
      online && hasTransport && (vault.read(keyAlias)?.isNotEmpty ?? false);

  /// 可导出配置：只有别名，没有 key 明文 / 凭证字段。
  @override
  Map<String, dynamic> configJson() => <String, dynamic>{
        'provider': 'deepseek',
        'baseUrl': baseUrl,
        'modelId': modelId,
        'thinkingMode': thinkingMode,
        'keyAlias': keyAlias,
      };

  @override
  AiResponse call(AiRequest request) {
    final key = vault.read(keyAlias);
    if (key == null || key.isEmpty || !online || !hasTransport) {
      return AiResponse(
        status: 'pending',
        capability: request.capability,
        providerId: id,
        modelId: modelId,
        data: const <String, dynamic>{},
        reason: '无 key / 无网 / 未配置传输层',
      );
    }
    if (request.capability == 'recognizeScreenshot' &&
        modelId == 'deepseek-v4-pro') {
      throw ValidationError(
          'deepseek-v4-pro 不支持图像理解，截图识别请用 $defaultModelId');
    }
    final body = <String, dynamic>{
      'model': modelId,
      'thinking': thinkingMode,
      'capability': request.capability,
      'context': request.context,
    };
    lastBody = body;
    lastUrl = baseUrl;
    // apiKey 只在这里交给传输层，绝不写进 body / 日志 / 导出。
    final data = transport(baseUrl, body, key);
    return AiResponse(
      status: 'ok',
      capability: request.capability,
      providerId: id,
      modelId: modelId,
      data: data,
    );
  }
}

/// AI 能力层总入口：调用方只依赖本类 + AiCapability，不碰具体模型。
class AiService implements Entity {
  /// 外发白名单键（接 F4 Preferences.dataOutboundWhitelist）。
  static const String outboundKind = 'aiContext';

  /// 最小必要上下文的序列化长度上限。
  static const int maxContextChars = 4000;

  final PreferencesLayer prefs;
  AiProvider _provider;

  /// 2.x 多模型注册表（运行时可插拔；不进序列化，避免改变 toJson 契约）。
  final Map<String, AiProvider> _providers = <String, AiProvider>{};

  final List<AiCallLog> _log = <AiCallLog>[];
  final List<String> pendingNodes = <String>[];

  AiService({AiProvider? provider, List<AiProvider>? providers, PreferencesLayer? prefs})
      : _provider = provider ?? MockProvider(),
        prefs = prefs ?? PreferencesLayer() {
    if (provider != null) _providers[provider.id] = provider;
    if (providers != null) {
      for (final p in providers) _providers[p.id] = p;
      if (provider == null && providers.isNotEmpty) _provider = providers.first;
    }
  }

  AiProvider get provider => _provider;
  List<AiCallLog> get log => List<AiCallLog>.unmodifiable(_log);

  /// 已注册 Provider id 列表（多模型切换用）。
  List<String> get providerIds =>
      List<String>.unmodifiable(_providers.keys);

  /// 当前激活 Provider id。
  String get activeProviderId => _provider.id;

  /// 注册一个可插拔 Provider（不覆盖序列化契约）。
  void registerProvider(AiProvider p) => _providers[p.id] = p;

  /// 在已注册 Provider 间切换（换模型只改这一处）。
  void selectProvider(String id) {
    final p = _providers[id];
    if (p == null) {
      throw ValidationError('未知 Provider: "$id"（请先 registerProvider）');
    }
    _provider = p;
  }

  int get sentCount => _log.where((l) => l.status == 'ok').length;
  int get pendingCount => _log.where((l) => l.status == 'pending').length;
  int get blockedCount =>
      _log.where((l) => l.reason.contains('白名单')).length;
  bool get aiPending => pendingCount > 0;

  /// 换 Provider / 换模型：只改这一处，主流程 invoke 零改动。
  void switchProvider(AiProvider p) {
    _providers[p.id] = p;
    _provider = p;
  }

  /// 优雅降级下始终可用的非 AI 环节。
  List<String> nonAiFeatures() =>
      const <String>['watchVideo', 'takeNotes', 'doExistingQuiz'];

  /// 最小必要上下文：只保留该能力允许的字段，剔除凭证，超限拒绝。
  Map<String, dynamic> _minimize(
      String capability, Map<String, dynamic> context) {
    final allowed = AiCapability.allowedContext[capability]!;
    final out = <String, dynamic>{};
    for (final k in allowed) {
      if (context.containsKey(k) && context[k] != null) {
        out[k] = context[k];
      }
    }
    if (stableStringify(out).length > maxContextChars) {
      throw ValidationError(
          '最小必要上下文超限（>${maxContextChars} 字符），请只送当次所需');
    }
    assertNoCredentials(out, 'AiService.minimizedContext');
    return out;
  }

  /// 统一调用入口：**不含任何模型 / 凭证参数**。
  AiResponse invoke(
    String capability, {
    Map<String, dynamic> context = const <String, dynamic>{},
    String? kindOverride,
  }) {
    ensureEnum(capability, AiCapability.all, 'AiCapability');
    final kind = kindOverride ?? outboundKind;
    final minimal = _minimize(capability, context);
    final keys = minimal.keys.toList()..sort();

    // 白名单未开 = 零外发，但不抛异常、不阻塞非 AI 功能。
    if (!prefs.allowOutbound(kind)) {
      return _pending(capability, keys,
          '外发白名单未开启 "$kind"，零外发（AI 待处理）');
    }
    // 无 key / 无网 / 未配置传输层 = 优雅降级。
    if (!_provider.available) {
      return _pending(capability, keys,
          '无 key / 无网 / 传输层未配置，AI 节点标「待处理」，不阻塞非 AI 功能');
    }

    final resp =
        _provider.call(AiRequest(capability: capability, context: minimal));
    _assertStructured(capability, resp);
    _log.add(AiCallLog(
      capability: capability,
      providerId: _provider.id,
      status: resp.status,
      contextKeys: keys,
      reason: resp.reason ?? '',
    ));
    if (resp.isPending) pendingNodes.add(capability);
    return resp;
  }

  AiResponse _pending(
      String capability, List<String> keys, String reason) {
    _log.add(AiCallLog(
      capability: capability,
      providerId: _provider.id,
      status: 'pending',
      contextKeys: keys,
      reason: reason,
    ));
    pendingNodes.add(capability);
    return AiResponse(
      status: 'pending',
      capability: capability,
      providerId: _provider.id,
      modelId: _provider.modelId,
      data: const <String, dynamic>{},
      reason: reason,
    );
  }

  /// 验收⑥：截图识别必须产出结构化数据，而不是 PDF / 纯文本。
  void _assertStructured(String capability, AiResponse resp) {
    if (capability != 'recognizeScreenshot') return;
    final d = resp.data;
    if (d['kind'] != 'structured') {
      throw ValidationError(
          '截图识别必须产出结构化数据（kind=structured），不得返回 PDF 文本');
    }
    final f = d['fields'];
    if (f is! List || f.isEmpty) {
      throw ValidationError(
          '截图识别必须产出结构化字段 fields，不得为 PDF 文本');
    }
    if (d.containsKey('pdfText') || d.containsKey('plainText')) {
      throw ValidationError(
          '截图识别不得返回 PDF / 纯文本正文，须为结构化字段');
    }
  }

  /// 导出资产：只含配置（无凭证）与台账（无上下文值）。
  Map<String, String> packageAssets() {
    final config = jsonEncode(_provider.configJson());
    final calls = jsonEncode(_log.map((l) => l.toJson()).toList());
    assertNoCredentials(jsonDecode(config), 'ai/config.json');
    assertNoCredentials(jsonDecode(calls), 'ai/calls.json');
    return <String, String>{
      'ai/config.json': config,
      'ai/calls.json': calls,
    };
  }

  @override
  Map<String, dynamic> toJson() => {
        'providerConfig': _provider.configJson(),
        'log': _log.map((l) => l.toJson()).toList(),
        'pendingNodes': pendingNodes,
        'prefs': prefs.toJson(),
      };

  /// 反序列化会重建 Provider，但**不会**恢复 apiKey（凭证不进包）。
  static AiService fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    final cfg = Map<String, dynamic>.from(m['providerConfig'] as Map);
    AiProvider p;
    if (cfg['provider'] == 'deepseek') {
      p = DeepSeekAdapter(
        baseUrl: cfg['baseUrl'] as String,
        modelId: cfg['modelId'] as String,
        thinkingMode: cfg['thinkingMode'] as bool,
        keyAlias: cfg['keyAlias'] as String,
      );
    } else {
      p = MockProvider(id: cfg['id'] as String? ?? 'mock');
    }
    final s = AiService(
      provider: p,
      prefs: PreferencesLayer.fromJson(m['prefs']),
    );
    s._log.addAll(
        (m['log'] as List).map((e) => AiCallLog.fromJson(e)).toList());
    s.pendingNodes.addAll(
        (m['pendingNodes'] as List).map((e) => e.toString()).toList());
    return s;
  }
}
