/// F13 · AI 服务层测试（PRD §4 F13 六条验收逐条 + 硬约束）。
/// 单独运行：dart test/tF13_ai.dart
import 'framework.dart';
import '../lib/ai.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/preferences.dart';
import '../lib/session.dart';
import '../lib/studypack.dart';

const leaf = 'RJ-A-BX1-CH2-2.2-EQ';
const testKey = 'sk-test-ABCDEFGH12345678';

/// 开启「aiContext」外发白名单的策略层。
PreferencesLayer _openPrefs() => PreferencesLayer(
    global: Preferences(
        dataOutboundWhitelist: <String>[AiService.outboundKind]));

AiService _svc({AiProvider? provider, PreferencesLayer? prefs}) =>
    AiService(provider: provider, prefs: prefs ?? _openPrefs());

/// 结构化传输层替身（不做真实网络 I/O）。
Map<String, dynamic> _transport(
        String url, Map<String, dynamic> body, String apiKey) =>
    <String, dynamic>{
      'kind': 'structured',
      'fields': <Map<String, dynamic>>[
        {'capability': body['capability'], 'model': body['model']},
      ],
      'result': 'ok',
    };

DeepSeekAdapter _ds({
  String modelId = DeepSeekAdapter.defaultModelId,
  String? key = testKey,
  bool online = true,
  AiTransport? transport,
}) =>
    DeepSeekAdapter(
      modelId: modelId,
      vault: MemoryKeyVault(
          key == null ? <String, String>{} : <String, String>{DeepSeekAdapter.defaultKeyAlias: key}),
      transport: transport ?? _transport,
      online: online,
    );

/// 故意返回 PDF 文本的坏 Provider，用于验收⑥的反例。
class BadProvider implements AiProvider {
  @override
  String get id => 'bad';

  @override
  String get modelId => 'bad';

  @override
  bool get available => true;

  @override
  Map<String, dynamic> configJson() => <String, dynamic>{
        'provider': 'bad',
        'modelId': modelId,
      };

  @override
  AiResponse call(AiRequest request) => AiResponse(
        status: 'ok',
        capability: request.capability,
        providerId: id,
        modelId: modelId,
        data: <String, dynamic>{
          'pdfText': '2026-11-14 数学 07:00-07:30 ...',
        },
      );
}

void runF13(Harness h) {
  // ------------------------------------------------------------------ 验收①
  h.group('F13 验收① 能力接口调用不依赖具体模型', () {
    h.test('9 个固定能力可枚举，且每个都有最小上下文白名单', () {
      h.eq(AiCapability.all.length, 9);
      for (final c in AiCapability.all) {
        h.isTrue(AiCapability.allowedContext.containsKey(c), '$c 缺白名单');
      }
    });

    h.test('9 个能力经统一入口全部可调用', () {
      final svc = _svc();
      for (final c in AiCapability.all) {
        final r = svc.invoke(c);
        h.eq(r.status, 'ok', '$c 应成功');
        h.eq(r.capability, c);
      }
      h.eq(svc.sentCount, 9);
    });

    h.test('AiRequest 只带 capability + context，不含 modelId / apiKey', () {
      final req = AiRequest(
          capability: 'gradeQuiz',
          context: <String, dynamic>{'resourceIds': <String>['R-1']});
      final keys = req.toJson().keys.toList();
      h.eq(keys.length, 2);
      h.isTrue(keys.contains('capability'));
      h.isTrue(keys.contains('context'));
      h.isFalse(keys.any((k) => k.toLowerCase().contains('model')));
      h.isFalse(keys.any((k) => k.toLowerCase().contains('key')));
    });

    h.test('非法 capability 被拒绝', () {
      h.throwsValidation(() => _svc().invoke('freeformMagic'));
      h.throwsValidation(() => AiRequest(
          capability: 'notACapability', context: <String, dynamic>{}));
    });

    h.test('不同模型配置下，同一能力调用结果结构一致', () {
      final a = _svc(provider: _ds());
      final b = _svc(provider: _ds(modelId: 'deepseek-chat'));
      final ra = a.invoke('analyzeWeakness',
          context: <String, dynamic>{'knowledgeNodeId': leaf});
      final rb = b.invoke('analyzeWeakness',
          context: <String, dynamic>{'knowledgeNodeId': leaf});
      h.eq(ra.status, 'ok');
      h.eq(rb.status, 'ok');
      h.eq(ra.data['capability'], rb.data['capability']);
    });
  });

  // ------------------------------------------------------------------ 验收②
  h.group('F13 验收② 换 Provider 主流程零改动', () {
    h.test('switchProvider 后同一 invoke 仍成功且响应 schema 一致', () {
      final svc = _svc(provider: MockProvider(id: 'mock-1'));
      final r1 = svc.invoke('generateNote');
      svc.switchProvider(MockProvider(id: 'mock-2'));
      final r2 = svc.invoke('generateNote');
      h.eq(r1.status, 'ok');
      h.eq(r2.status, 'ok');
      h.eq(r1.providerId, 'mock-1');
      h.eq(r2.providerId, 'mock-2');
      h.eq(r1.data['capability'], r2.data['capability']);
    });

    h.test('换成 DeepSeekAdapter 后主流程零改动', () {
      final svc = _svc(provider: MockProvider());
      svc.invoke('retrieveResources');
      svc.switchProvider(_ds());
      final r = svc.invoke('retrieveResources');
      h.eq(r.status, 'ok');
      h.eq(r.providerId, 'deepseek');
      h.eq(r.modelId, 'deepseek-flash');
    });

    h.test('换模型只改配置：model 出现在传输 body，调用方代码不变', () {
      final svc = _svc(provider: _ds(modelId: 'deepseek-chat'));
      final r = svc.invoke('gradeQuiz');
      h.eq(r.status, 'ok');
      h.eq(svc.provider.modelId, 'deepseek-chat');
    });

    h.test('configJson 反映当前 Provider', () {
      final svc = _svc(provider: MockProvider(id: 'mock-x'));
      h.eq(svc.toJson()['providerConfig']['id'], 'mock-x');
      svc.switchProvider(_ds());
      h.eq(svc.toJson()['providerConfig']['provider'], 'deepseek');
    });
  });

  // ------------------------------------------------------------------ 验收③
  h.group('F13 验收③ 导出包不含任何凭证字段', () {
    h.test('DeepSeek 配置不含 api_key / apikey 类字段', () {
      final cfg = _ds().configJson();
      h.isFalse(cfg.keys.any((k) => k.toLowerCase().contains('apikey')));
      h.isFalse(cfg.keys.any((k) => k.toLowerCase().contains('secret')));
    });

    h.test('配置不含 key 明文，只有系统密钥库别名', () {
      final cfg = _ds().configJson();
      h.isFalse(cfg.values.any((v) => v.toString().contains('sk-test')));
      h.eq(cfg['keyAlias'], DeepSeekAdapter.defaultKeyAlias);
    });

    h.test('packageAssets 导出后扫描不含任何凭证', () {
      final svc = _svc(provider: _ds());
      svc.invoke('analyzeWeakness',
          context: <String, dynamic>{'knowledgeNodeId': leaf});
      final assets = svc.packageAssets();
      h.eq(assets.keys.length, 2);
      h.isFalse(assets.values.any((v) => v.contains('sk-test')));
      h.isFalse(assets.values.any((v) => v.toLowerCase().contains('api_key')));
    });

    h.test('.studypack 导出（含 AI 资产）全包不含凭证', () {
      final svc = _svc(provider: _ds());
      svc.invoke('gradeQuiz');
      final files = StudyPack.exportPack(
        DataPackage(),
        device: 'vivo S7',
        assets: svc.packageAssets(),
      );
      h.isFalse(files.values.any((v) => v.contains('sk-test')));
      h.isFalse(files.values.any((v) => v.toLowerCase().contains('api_key')));
      h.eq(StudyPack.importPack(files).entities.length, 14);
    });

    h.test('把 api_key 直接塞进实体被 F2 拒绝（集成 F2 校验）', () {
      h.throwsValidation(() => StudyPack.exportPack(DataPackage(
          entities: <String, List<Map<String, dynamic>>>{
            'ai_notes.json': <Map<String, dynamic>>[
              <String, dynamic>{'api_key': testKey}
            ],
          })));
    });

    h.test('fromJson 恢复后不恢复 apiKey（Provider 变为不可用）', () {
      final svc = _svc(provider: _ds());
      svc.invoke('gradeQuiz');
      final back = AiService.fromJson(svc.toJson());
      h.isFalse(back.provider.available);
      h.eq(back.provider.configJson()['modelId'], 'deepseek-flash');
    });
  });

  // ------------------------------------------------------------------ 验收④
  h.group('F13 验收④ 无 key / 无网返回「待处理」且非 AI 功能可用', () {
    h.test('无 key → pending', () {
      final r = _svc(provider: _ds(key: null)).invoke('analyzeWeakness');
      h.eq(r.status, 'pending');
      h.isTrue(r.isPending);
      h.contains(r.reason!, '待处理');
    });

    h.test('无网 → pending', () {
      final r = _svc(provider: _ds(online: false)).invoke('analyzeWeakness');
      h.eq(r.status, 'pending');
    });

    h.test('未配置传输层 → pending', () {
      final adapter = DeepSeekAdapter(
          vault: MemoryKeyVault(<String, String>{DeepSeekAdapter.defaultKeyAlias: testKey}));
      h.isFalse(adapter.available);
      h.eq(_svc(provider: adapter).invoke('gradeQuiz').status, 'pending');
    });

    h.test('pending 时零外发：Provider 一次都没被调用', () {
      final mock = MockProvider(online: false);
      final svc = _svc(provider: mock);
      svc.invoke('generateNote');
      h.eq(mock.callCount, 0);
      h.eq(svc.sentCount, 0);
      h.isTrue(svc.aiPending);
      h.eq(svc.pendingNodes.length, 1);
    });

    h.test('非 AI 环节恒定可用：看视频 / 记笔记 / 做已有题目', () {
      final f = _svc().nonAiFeatures();
      h.eq(f.length, 3);
      h.isTrue(f.contains('watchVideo'));
      h.isTrue(f.contains('takeNotes'));
      h.isTrue(f.contains('doExistingQuiz'));
    });

    h.test('集成 F8：AI 待处理时看视频 / 记笔记 / 做已有题目不阻塞', () {
      final svc = _svc(provider: MockProvider(online: false));
      final r = svc.invoke('retrieveResources');
      h.eq(r.status, 'pending');

      final e = SessionEngine(
        plan: Plan(
            id: 'P-1',
            goal: '精进基本不等式',
            quantTarget: 0.75,
            passLine: 0.75,
            deadlineDays: 15,
            startMode: 'immediate',
            createdDate: '2026-11-14'),
        initial: Session(
            id: 'SE-1',
            planId: 'P-1',
            slotId: 'T3-2026-11-14',
            capacityMinutes: 60,
            pretestSkipped: true,
            noteVisible: true),
      );
      e.start(resources: <String>['视频：2.2 基本不等式'], aiReady: false);
      h.eq(e.stage, 'study');
      h.isTrue(e.aiPending);
      e.addNoteBlock('一正二定三相等');
      e.finishStudy();
      h.eq(e.stage, 'quiz');
      e.submitQuizScore(0.8);
      h.eq(e.stage, 'summary');
    });

    h.test('pending 之后仍可继续本地调用，不抛异常', () {
      final svc = _svc(provider: MockProvider(online: false));
      h.eq(svc.invoke('gradeQuiz').status, 'pending');
      h.eq(svc.invoke('generateNote').status, 'pending');
      h.eq(svc.pendingCount, 2);
    });
  });

  // ------------------------------------------------------------------ 验收⑤
  h.group('F13 验收⑤ 外发上下文受白名单约束', () {
    h.test('白名单未开 → 零外发、pending、原因标明白名单', () {
      final mock = MockProvider();
      final svc = AiService(provider: mock); // 默认白名单空
      final r = svc.invoke('analyzeWeakness',
          context: <String, dynamic>{'knowledgeNodeId': leaf});
      h.eq(r.status, 'pending');
      h.eq(mock.callCount, 0);
      h.eq(svc.sentCount, 0);
      h.eq(svc.blockedCount, 1);
      h.contains(svc.log.first.reason, '白名单');
    });

    h.test('白名单开启 → 才真正调用 Provider', () {
      final mock = MockProvider();
      final svc = _svc(provider: mock);
      h.eq(svc.invoke('gradeQuiz').status, 'ok');
      h.eq(mock.callCount, 1);
      h.eq(svc.sentCount, 1);
    });

    h.test('最小必要：白名单外字段一律不外发', () {
      final mock = MockProvider();
      final svc = _svc(provider: mock);
      svc.invoke('analyzeWeakness', context: <String, dynamic>{
        'knowledgeNodeId': leaf,
        'quizScores': <double>[0.6],
        'fullTranscript': '整节课逐字稿（不该外发）',
        'deviceId': 'vivo S7',
        'api_key': testKey,
      });
      final ctx = mock.lastRequest!.context;
      h.eq((ctx.keys.toList()..sort()).join(','),
          'knowledgeNodeId,quizScores');
      h.isFalse(ctx.containsKey('fullTranscript'));
      h.isFalse(ctx.containsKey('deviceId'));
      h.isFalse(ctx.containsKey('api_key'));
      h.eq(ctx['knowledgeNodeId'], leaf);
    });

    h.test('凭证字段即使出现在上下文也被剔除', () {
      final mock = MockProvider();
      final svc = _svc(provider: mock);
      svc.invoke('gradeQuiz', context: <String, dynamic>{
        'resourceIds': <String>['R-1'],
        'token': 'abc',
        'authorization': 'Bearer abc',
      });
      final ctx = mock.lastRequest!.context;
      h.eq(ctx.keys.join(','), 'resourceIds');
    });

    h.test('上下文超长被拒绝（最小必要）', () {
      h.throwsValidation(() => _svc().invoke('analyzeWeakness',
          context: <String, dynamic>{
            'evidence': <String>['x' * 5000],
          }));
    });

    h.test('调用台账只记上下文键名，不记值', () {
      final svc = _svc();
      svc.invoke('analyzeWeakness',
          context: <String, dynamic>{'knowledgeNodeId': leaf});
      final log = svc.log.first;
      h.eq(log.contextKeys.join(','), 'knowledgeNodeId');
      h.isFalse(log.toJson().toString().contains(leaf));
      h.eq(log.status, 'ok');
    });
  });

  // ------------------------------------------------------------------ 验收⑥
  h.group('F13 验收⑥ 截图识别产出结构化数据而非 PDF 文本', () {
    h.test('recognizeScreenshot 返回 kind=structured + 非空 fields', () {
      final r = _svc().invoke('recognizeScreenshot',
          context: <String, dynamic>{'imageRef': 'screenshot://schedule/1'});
      h.eq(r.status, 'ok');
      h.eq(r.data['kind'], 'structured');
      h.isTrue(r.data['fields'] is List);
      h.isTrue((r.data['fields'] as List).isNotEmpty);
    });

    h.test('结果不含 pdfText / plainText，且不是纯字符串', () {
      final r = _svc().invoke('recognizeScreenshot');
      h.isFalse(r.data.containsKey('pdfText'));
      h.isFalse(r.data.containsKey('plainText'));
      h.isTrue(r.data is Map);
      h.isTrue(r.data['fields'] is List);
    });

    h.test('Provider 若返回 PDF 文本正文，被能力层明确拒绝', () {
      h.throwsValidation(() => _svc(provider: BadProvider())
          .invoke('recognizeScreenshot'));
    });

    h.test('deepseek-v4-pro 用于截图识别被拒（不支持图像理解）', () {
      h.throwsValidation(() => _svc(provider: _ds(modelId: 'deepseek-v4-pro'))
          .invoke('recognizeScreenshot'));
    });

    h.test('「DeepSeek 4.1 Pro」非正式在售型号，禁止写入配置', () {
      h.throwsValidation(
          () => DeepSeekAdapter(modelId: 'DeepSeek4.1Pro'));
      h.throwsValidation(
          () => DeepSeekAdapter(modelId: 'deepseek-4.1-pro'));
    });

    h.test('默认型号为 deepseek-flash', () {
      h.eq(DeepSeekAdapter.defaultModelId, 'deepseek-flash');
      h.eq(_ds().modelId, 'deepseek-flash');
      h.eq(DeepSeekAdapter().modelId, 'deepseek-flash');
    });
  });

  // ------------------------------------------------------------------ 往返
  h.group('F13 全量往返与传输层凭证隔离', () {
    h.test('toJson / fromJson 全量往返', () {
      final svc = _svc(provider: _ds());
      svc.invoke('gradeQuiz');
      svc.invoke('generateNote');
      final back = AiService.fromJson(svc.toJson());
      h.eq(back.log.length, 2);
      h.eq(back.provider.configJson()['modelId'], 'deepseek-flash');
      h.eq(back.sentCount, 2);
      h.jsonEq(back.toJson(), svc.toJson());
    });

    h.test('transport body 含 model / capability / context，不含凭证字段', () {
      final ds = _ds();
      final svc = _svc(provider: ds);
      svc.invoke('gradeQuiz',
          context: <String, dynamic>{'resourceIds': <String>['R-1']});
      h.eq(ds.lastUrl, 'https://api.deepseek.com/v1');
      h.eq(ds.lastBody!['model'], 'deepseek-flash');
      h.eq(ds.lastBody!['capability'], 'gradeQuiz');
      h.isFalse(ds.lastBody!.keys
          .any((k) => k.toLowerCase().contains('api')));
      h.isFalse(stableStringify(ds.lastBody!).contains('sk-test'));
    });

    h.test('apiKey 只在传输层第三参数，绝不进 body', () {
      String? captured;
      final ds = DeepSeekAdapter(
        vault: MemoryKeyVault(<String, String>{DeepSeekAdapter.defaultKeyAlias: testKey}),
        transport: (String url, Map<String, dynamic> body, String key) {
          captured = key;
          return _transport(url, body, key);
        },
      );
      _svc(provider: ds).invoke('gradeQuiz');
      h.eq(captured, testKey);
      h.isFalse(stableStringify(ds.lastBody!).contains('sk-test'));
    });

    h.test('assertNoCredentials 直接拒绝凭证字段 / sk- 明文', () {
      h.throwsValidation(() => assertNoCredentials(
          <String, dynamic>{'api_key': testKey}));
      h.throwsValidation(() => assertNoCredentials(
          <String, dynamic>{'nested': <String, dynamic>{'token': 'x'}}));
      h.throwsValidation(
          () => assertNoCredentials(<String, dynamic>{'v': testKey}));
    });

    h.test('AiResponse / AiRequest / AiCallLog 均可 JSON 往返', () {
      final req = AiRequest(
          capability: 'gradeQuiz',
          context: <String, dynamic>{'answers': <bool>[true, false]});
      h.jsonEq(AiRequest.fromJson(req.toJson()).toJson(), req.toJson());

      final resp = AiResponse(
          status: 'ok',
          capability: 'gradeQuiz',
          providerId: 'mock',
          modelId: 'mock-offline',
          data: <String, dynamic>{'score': 0.8});
      h.jsonEq(AiResponse.fromJson(resp.toJson()).toJson(), resp.toJson());

      final log = AiCallLog(
          capability: 'gradeQuiz',
          providerId: 'mock',
          status: 'ok',
          contextKeys: <String>['answers'],
          reason: '');
      h.jsonEq(AiCallLog.fromJson(log.toJson()).toJson(), log.toJson());
    });
  });
}

void main() {
  final h = Harness();
  runF13(h);
  h.report();
}
