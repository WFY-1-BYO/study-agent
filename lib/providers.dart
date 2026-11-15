/// F14 · 多模型 Provider 注册表（2.x 新增，承接「主流 + 分领域」决策）。
///
/// 设计要点：
///  - 统一用 **OpenAI 兼容** 通道承载 DeepSeek / GPT / Qwen / Kimi / 豆包 / GLM /
///    Gemini / Claude（各家 OpenAI 兼容网关）与本地 Ollama；
///  - baseUrl / modelId / key 全可插拔，换模型只改配置，主流程零改动；
///  - **凭证隔离**：key 只经传输层第三参数外发，绝不进 body / 配置 / 日志 / 导出；
///  - 本地 Ollama 允许 http://localhost，云端一律 https://。
///
/// 零第三方依赖，兼容 Dart 2.17。
library study_agent.providers;

import 'core.dart';
import 'ai.dart';

/// 默认传输层（无真实网络 I/O）：返回不可用占位，仅供离线测试。
Map<String, dynamic> _defaultTransport(
        String url, Map<String, dynamic> body, String apiKey) =>
    <String, dynamic>{'kind': 'unavailable', 'fields': <dynamic>[]};

/// OpenAI 兼容通用 Provider 适配器：所有主流与分领域模型统一接入。
class OpenAiCompatibleProvider implements AiProvider {
  @override
  final String id;
  final String label;
  final String baseUrl;
  final String modelId;
  final String keyAlias;
  final ApiKeyVault vault;
  final AiTransport transport;
  final bool online;
  final bool hasTransport;

  /// 传输层收到的最后一个 body（供测试断言，不含凭证）。
  Map<String, dynamic>? lastBody;
  String? lastUrl;

  OpenAiCompatibleProvider({
    required this.id,
    this.label = '',
    required this.baseUrl,
    required this.modelId,
    this.keyAlias = 'api_key',
    ApiKeyVault? vault,
    AiTransport? transport,
    this.online = true,
  })  : vault = vault ?? MemoryKeyVault(),
        transport = transport ?? _defaultTransport,
        hasTransport = transport != null {
    if (modelId.trim().isEmpty) {
      throw ValidationError('$id.modelId 不可为空');
    }
    if (!baseUrl.startsWith('https://') && !baseUrl.startsWith('http://')) {
      throw ValidationError('$id.baseUrl 必须为 http(s)://');
    }
    // 云端必须 https；仅本地 Ollama 允许 http://localhost。
    if (!baseUrl.startsWith('https://') &&
        !baseUrl.startsWith('http://localhost')) {
      throw ValidationError('$id.baseUrl 云端必须 https://（本地可 http://localhost）');
    }
  }

  @override
  bool get available =>
      online && hasTransport && (vault.read(keyAlias)?.isNotEmpty ?? false);

  @override
  Map<String, dynamic> configJson() => <String, dynamic>{
        'provider': id,
        'label': label,
        'baseUrl': baseUrl,
        'modelId': modelId,
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
    final body = <String, dynamic>{
      'model': modelId,
      'capability': request.capability,
      'context': request.context,
    };
    lastBody = body;
    lastUrl = baseUrl;
    // apiKey 只作第三参数交给传输层，绝不写进 body / 日志 / 导出。
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

/// 单个 Provider 预设（默认 baseUrl + 建议型号）。
class ProviderPreset {
  final String id;
  final String label;
  final String defaultBaseUrl;
  final List<String> suggestedModels;
  final bool local;
  final String? note;

  const ProviderPreset({
    required this.id,
    required this.label,
    required this.defaultBaseUrl,
    required this.suggestedModels,
    this.local = false,
    this.note,
  });
}

/// 预置 Provider 注册表：覆盖主流 + 分领域（数学/推理/中文/多模态/本地隐私）。
class ProviderRegistry {
  static const List<ProviderPreset> presets = [
    ProviderPreset(
      id: 'deepseek',
      label: 'DeepSeek（推理 / 数学，默认）',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      suggestedModels: ['deepseek-chat', 'deepseek-reasoner'],
      note: '数学与推理强，按量计费经济',
    ),
    ProviderPreset(
      id: 'openai',
      label: 'OpenAI · GPT（通用 / 写作）',
      defaultBaseUrl: 'https://api.openai.com/v1',
      suggestedModels: ['gpt-4o', 'gpt-4o-mini', 'o1-mini'],
    ),
    ProviderPreset(
      id: 'claude',
      label: 'Claude（长文 / 讲解）',
      defaultBaseUrl: 'https://api.anthropic.com/v1',
      suggestedModels: ['claude-3-5-sonnet', 'claude-opus-4'],
    ),
    ProviderPreset(
      id: 'qwen',
      label: '通义千问 Qwen（中文）',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      suggestedModels: ['qwen-max', 'qwen-plus', 'qwen2.5-72b-instruct'],
    ),
    ProviderPreset(
      id: 'kimi',
      label: 'Kimi（长上下文 / 中文 K12）',
      defaultBaseUrl: 'https://api.moonshot.cn/v1',
      suggestedModels: ['moonshot-v1-8k', 'moonshot-v1-32k'],
    ),
    ProviderPreset(
      id: 'doubao',
      label: '豆包（中文 / 字节）',
      defaultBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      suggestedModels: ['doubao-pro-32k', 'doubao-lite-4k'],
    ),
    ProviderPreset(
      id: 'glm',
      label: '智谱 GLM（中文 / 学术）',
      defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      suggestedModels: ['glm-4-plus', 'glm-4-air'],
    ),
    ProviderPreset(
      id: 'gemini',
      label: 'Gemini（多模态 / 视觉）',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      suggestedModels: ['gemini-1.5-pro', 'gemini-2.0-flash'],
      note: '支持截图视觉理解',
    ),
    ProviderPreset(
      id: 'ollama',
      label: 'Ollama（本地 / 离线隐私）',
      defaultBaseUrl: 'http://localhost:11434/v1',
      suggestedModels: ['llama3', 'qwen2.5', 'deepseek-r1'],
      local: true,
      note: '完全离线，数据不出本机',
    ),
  ];

  static ProviderPreset byId(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    throw ValidationError('未知 Provider: "$id"');
  }

  /// 按预设构造一个可插拔 Provider（key 由 vault 提供）。
  static OpenAiCompatibleProvider build(
    String id, {
    String? modelId,
    String? baseUrl,
    ApiKeyVault? vault,
    AiTransport? transport,
  }) {
    final preset = byId(id);
    return OpenAiCompatibleProvider(
      id: preset.id,
      label: preset.label,
      baseUrl: baseUrl ?? preset.defaultBaseUrl,
      modelId: modelId ?? preset.suggestedModels.first,
      vault: vault,
      transport: transport,
    );
  }
}
