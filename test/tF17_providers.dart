/// F14 · 多模型 Provider 注册表测试（2.x 新增）。
/// 单独运行：dart test/tF17_providers.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/ai.dart';
import '../lib/preferences.dart';
import '../lib/providers.dart';

/// 捕获传输层收到的 (url, body, key) 以便断言凭证隔离。
class _CaptureTransport {
  String? lastUrl;
  Map<String, dynamic>? lastBody;
  String? lastKey;
  Map<String, dynamic> call(String url, Map<String, dynamic> body, String key) {
    lastUrl = url;
    lastBody = Map<String, dynamic>.from(body);
    lastKey = key;
    return <String, dynamic>{'ok': true};
  }
}

void runF17(Harness h) {
  // ------------------------------------------------------------------ 注册表
  h.group('F14 预置 Provider 注册表', () {
    h.test('覆盖主流 + 分领域共 9 个 Provider', () {
      h.eq(ProviderRegistry.presets.length, 9);
    });
    h.test('每个预设默认 baseUrl 合法（云端 https / 本地 localhost）', () {
      for (final p in ProviderRegistry.presets) {
        final ok = p.defaultBaseUrl.startsWith('https://') ||
            p.defaultBaseUrl.startsWith('http://localhost');
        h.ok(ok, '${p.id} 的 baseUrl 不合法: ${p.defaultBaseUrl}');
      }
    });
    h.test('每个预设至少有一个建议型号', () {
      for (final p in ProviderRegistry.presets) {
        h.ok(p.suggestedModels.isNotEmpty, '${p.id} 无建议型号');
      }
    });
    h.test('byId 可定位、未知 id 抛错', () {
      h.eq(ProviderRegistry.byId('deepseek').label.contains('DeepSeek'), true);
      h.throwsValidation(() => ProviderRegistry.byId('nope'));
    });
  });

  // ------------------------------------------------------------------ 适配器
  h.group('F14 OpenAiCompatibleProvider 适配器', () {
    h.test('modelId 为空被拒绝', () {
      h.throwsValidation(() => OpenAiCompatibleProvider(
          id: 'x', baseUrl: 'https://a.com/v1', modelId: ''));
    });
    h.test('非 https 且非 localhost 的 baseUrl 被拒绝', () {
      h.throwsValidation(() => OpenAiCompatibleProvider(
          id: 'x', baseUrl: 'ftp://a.com', modelId: 'm'));
      h.throwsValidation(() => OpenAiCompatibleProvider(
          id: 'x', baseUrl: 'http://evil.com/v1', modelId: 'm'));
    });
    h.test('本地 Ollama http://localhost 允许', () {
      final p = OpenAiCompatibleProvider(
          id: 'ollama', baseUrl: 'http://localhost:11434/v1', modelId: 'llama3');
      h.eq(p.id, 'ollama');
    });
    h.test('无 key / 无传输层 → 优雅降级 pending（不抛、不伪造）', () {
      final p = OpenAiCompatibleProvider(
          id: 'ds', baseUrl: 'https://api.deepseek.com/v1', modelId: 'deepseek-chat',
          transport: _CaptureTransport().call);
      final resp = p.call(AiRequest(
          capability: 'generateQuestions', context: {'motherIds': ['R-1']}));
      h.eq(resp.status, 'pending');
      h.ok(resp.reason != null &&
          (resp.reason!.contains('key') || resp.reason!.contains('传输')));
    });
    h.test('凭证隔离：configJson 不含 key；key 只经传输层第三参数', () {
      final cap = _CaptureTransport();
      final p = OpenAiCompatibleProvider(
          id: 'ds', baseUrl: 'https://api.deepseek.com/v1', modelId: 'deepseek-chat',
          keyAlias: 'my_ds_key',
          vault: MemoryKeyVault(<String, String>{'my_ds_key': 'sk-SECRET-XYZ'}),
          transport: cap.call);
      // 配置导出无凭证
      final cfg = p.configJson();
      h.isFalse(cfg.containsKey('api_key'));
      h.isFalse(cfg.containsKey('key'));
      h.isFalse(cfg.values.any((v) => v.toString().contains('sk-SECRET')));
      // 实际调用时 key 经第三参数
      final resp = p.call(AiRequest(
          capability: 'generateQuestions', context: {'motherIds': ['R-1']}));
      h.eq(resp.status, 'ok');
      h.eq(cap.lastKey, 'sk-SECRET-XYZ');
      h.isFalse(cap.lastBody!.containsKey('api_key'));
      h.isFalse(cap.lastBody!.toString().contains('sk-SECRET'));
    });
  });

  // ------------------------------------------------------------------ AiService 多模型
  h.group('F14 AiService 多模型切换（不破坏单 Provider 契约）', () {
    h.test('registerProvider + selectProvider 切换激活 Provider', () {
      final svc = AiService(prefs: PreferencesLayer());
      svc.registerProvider(ProviderRegistry.build('deepseek',
          modelId: 'deepseek-chat', transport: _CaptureTransport().call));
      svc.registerProvider(ProviderRegistry.build('qwen',
          modelId: 'qwen-max', transport: _CaptureTransport().call));
      h.eq(svc.providerIds.length, 2);
      svc.selectProvider('qwen');
      h.eq(svc.activeProviderId, 'qwen');
      h.eq(svc.provider.modelId, 'qwen-max');
    });
    h.test('未知 Provider 切换被拒绝', () {
      final svc = AiService(prefs: PreferencesLayer());
      h.throwsValidation(() => svc.selectProvider('ghost'));
    });
    h.test('单 Provider 构造下 toJson/fromJson 仍逐字节往返（不破坏 tF13 契约）', () {
      final svc = AiService(
          provider: MockProvider(id: 'mock-1'), prefs: PreferencesLayer());
      svc.invoke('generateQuestions', context: {'motherIds': ['R-1']});
      final back = AiService.fromJson(svc.toJson());
      h.jsonEq(back.toJson(), svc.toJson());
    });
    h.test('构造即传入多 Provider 列表：默认激活首个', () {
      final svc = AiService(providers: [
        ProviderRegistry.build('deepseek', transport: _CaptureTransport().call),
        ProviderRegistry.build('openai', transport: _CaptureTransport().call),
      ]);
      h.eq(svc.activeProviderId, 'deepseek');
      h.eq(svc.providerIds.length, 2);
    });
  });
}

void main() {
  final h = Harness();
  runF17(h);
  h.report();
}
