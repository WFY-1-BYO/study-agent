/// F4 · L0 策略与开关层测试（PRD §4 F4 逐条验收）。
/// 单独运行：dart test/tF4_preferences.dart
import 'framework.dart';
import '../lib/core.dart';
import '../lib/preferences.dart';

void runF4(Harness h) {
  h.group('F4 验收① 每个策略点默认值正确', () {
    final layer = PreferencesLayer();
    h.test('提醒方式 / 开始时机 / SessionIntent', () {
      h.eq(layer.global.reminderMode, 'vibration');
      h.eq(layer.global.startMode, 'immediate');
      h.eq(layer.global.sessionIntent, 'follow');
      h.eq(layer.intentFor('S-1'), 'follow');
    });
    h.test('提前量：全局默认 5，快捷预设 2 / 5', () {
      h.eq(layer.global.defaultLeadMinutes, 5);
      h.eq(layer.global.leadPresets.length, 2);
      h.eq(layer.global.leadPresets[0], 2);
      h.eq(layer.global.leadPresets[1], 5);
      h.eq(layer.leadFor('S-1'), 5);
    });
    h.test('摸底测验默认显示 / 笔记区默认显示 / 白名单默认空', () {
      h.isTrue(layer.global.pretestVisible);
      h.isTrue(layer.noteVisibleFor('S-1'));
      h.isFalse(layer.pretestSkippedFor('S-1'));
      h.eq(layer.global.dataOutboundWhitelist.length, 0);
    });
    h.test('复习模式恒为固定模式 2', () {
      h.eq(layer.reviewMode, 'fixed2');
      h.eq(PreferencesLayer.reviewModeFixed, 'fixed2');
    });
  });

  h.group('F4 验收② 会话级覆盖不污染全局', () {
    h.test('单会话覆盖提前量 / 笔记显隐 / 摸底跳过', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(
          leadMinutes: 2, noteVisible: false, pretestSkipped: true));
      h.eq(layer.leadFor('S-1'), 2);
      h.isFalse(layer.noteVisibleFor('S-1'));
      h.isTrue(layer.pretestSkippedFor('S-1'));
      h.eq(layer.leadFor('S-2'), 5, '未覆盖会话仍用全局默认');
      h.isTrue(layer.noteVisibleFor('S-2'));
      h.isFalse(layer.pretestSkippedFor('S-2'));
      h.eq(layer.global.defaultLeadMinutes, 5, '全局默认不被改写');
      h.isTrue(layer.global.noteVisible, '全局显隐不被改写');
    });
    h.test('清除覆盖后回落全局', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(leadMinutes: 2));
      h.eq(layer.leadFor('S-1'), 2);
      layer.clearOverride('S-1');
      h.eq(layer.leadFor('S-1'), 5);
    });
    h.test('两个会话覆盖互不干扰', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(leadMinutes: 2));
      layer.setOverride('S-2', SessionOverrides(leadMinutes: 15));
      h.eq(layer.leadFor('S-1'), 2);
      h.eq(layer.leadFor('S-2'), 15);
    });
  });

  h.group('F4 验收③ 关闭笔记区不影响已归档内容', () {
    h.test('显隐只影响渲染，归档仍可检索', () {
      final layer = PreferencesLayer();
      layer.registerArchived('a::b::c', 'N-1');
      layer.registerArchived('a::b::c', 'N-2');
      layer.setOverride('S-1', SessionOverrides(noteVisible: false));
      h.isFalse(layer.noteVisibleFor('S-1'));
      h.eq(layer.findArchived('a::b::c').length, 2);
      h.contains(layer.findArchived('a::b::c').join('|'), 'N-1');
    });
    h.test('换会话 / 打开显隐后归档依旧在', () {
      final layer = PreferencesLayer();
      layer.registerArchived('a', 'N-9');
      layer.setOverride('S-1', SessionOverrides(noteVisible: false));
      h.eq(layer.findArchived('a').length, 1);
      layer.setOverride('S-1', SessionOverrides(noteVisible: true));
      h.eq(layer.findArchived('a').length, 1);
    });
    h.test('未登记的锚点返回空列表', () {
      h.eq(PreferencesLayer().findArchived('none').length, 0);
    });
  });

  h.group('F4 验收④ 复习模式不可配', () {
    h.test('setReviewMode 明确报错', () {
      h.throwsValidation(() => PreferencesLayer().setReviewMode('free'));
      h.throwsValidation(() => PreferencesLayer().setReviewMode('模式1'));
    });
    h.test('反序列化里偷改 reviewMode 被拒绝', () {
      final j = PreferencesLayer().toJson();
      j['reviewMode'] = 'free';
      h.throwsValidation(() => PreferencesLayer.fromJson(j));
    });
    h.test('toJson 里复习模式始终是 fixed2', () {
      final j = PreferencesLayer().toJson();
      h.eq(j['reviewMode'], 'fixed2');
    });
  });

  h.group('F4 验收⑤ 配置往返无损 & 随包导出', () {
    h.test('PreferencesLayer JSON 往返', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(
          leadMinutes: 2, noteVisible: false,
          pretestSkipped: true, sessionIntent: 'challenge'));
      layer.registerArchived('a::b::c', 'N-1');
      h.jsonEq(PreferencesLayer.fromJson(layer.toJson()).toJson(),
          layer.toJson());
    });
    h.test('Preferences / SessionOverrides 单独往返', () {
      final p = Preferences(defaultLeadMinutes: 8,
          dataOutboundWhitelist: ['quiz', 'restatement']);
      h.jsonEq(Preferences.fromJson(p.toJson()).toJson(), p.toJson());
      final o = SessionOverrides(leadMinutes: 3, sessionIntent: 'confidence');
      h.jsonEq(SessionOverrides.fromJson(o.toJson()).toJson(), o.toJson());
    });
    h.test('toEntityJson 可作为 preferences.json 内容', () {
      final j = PreferencesLayer().toEntityJson();
      h.contains(j.keys.join('|'), 'global');
      h.contains(j.keys.join('|'), 'overrides');
      h.contains(j.keys.join('|'), 'reviewMode');
      h.eq(j['reviewMode'], 'fixed2');
    });
  });

  h.group('F4 验收⑥⑦⑧ 提前量 / 白名单 / 临场意图', () {
    h.test('自定义提前量合法，非正数被拒', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(leadMinutes: 15));
      h.eq(layer.leadFor('S-1'), 15);
      h.throwsValidation(() => SessionOverrides(leadMinutes: 0));
      h.throwsValidation(() => SessionOverrides(leadMinutes: -3));
      h.throwsValidation(() => Preferences(defaultLeadMinutes: 0));
    });
    h.test('快捷预设为空被拒', () {
      h.throwsValidation(() => Preferences(leadPresets: []));
    });
    h.test('数据外发白名单可配置', () {
      final layer = PreferencesLayer(
          global: Preferences(dataOutboundWhitelist: ['quiz', 'restatement']));
      h.isTrue(layer.allowOutbound('quiz'));
      h.isTrue(layer.allowOutbound('restatement'));
      h.isFalse(layer.allowOutbound('all_notes'), '未列入的不得外发');
    });
    h.test('SessionIntent 仅当次生效，不改全局', () {
      final layer = PreferencesLayer();
      layer.setOverride('S-1', SessionOverrides(sessionIntent: 'challenge'));
      h.eq(layer.intentFor('S-1'), 'challenge');
      h.eq(layer.intentFor('S-2'), 'follow');
      h.eq(layer.global.sessionIntent, 'follow');
    });
    h.test('三种意图取值合法', () {
      for (final v in ['follow', 'challenge', 'confidence']) {
        h.eq(SessionOverrides(sessionIntent: v).sessionIntent, v);
      }
    });
  });

  h.group('F4 非法枚举被拒（不静默降级）', () {
    h.test('全局策略非法值', () {
      h.throwsValidation(() => Preferences(reminderMode: 'flash'));
      h.throwsValidation(() => Preferences(startMode: 'later'));
      h.throwsValidation(() => Preferences(sessionIntent: 'whatever'));
    });
    h.test('会话覆盖非法意图', () {
      h.throwsValidation(
          () => SessionOverrides(sessionIntent: 'yolo'));
    });
    h.test('反序列化里的非法值同样被拒', () {
      final j = Preferences().toJson();
      j['reminderMode'] = 'flash';
      h.throwsValidation(() => Preferences.fromJson(j));
    });
  });
}

void main() {
  final h = Harness();
  runF4(h);
  h.report();
}
