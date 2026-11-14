/// F4 · L0 策略与开关层（横切）。
///
/// 所有「有这个功能，但用不用由我定」的点统一归此处：
/// 提醒方式 / 提前量 / 开始时机 / 摸底测验 / 笔记显隐 / 数据外发白名单 / SessionIntent。
/// 唯一不可配的是**复习模式（固定模式 2）** —— 不提供 setter，反序列化里偷改也会被拒。
library study_agent.preferences;

import 'core.dart';
import 'models.dart';

/// 单次会话覆盖：只当次生效，绝不写回全局。
class SessionOverrides implements Entity {
  final int? leadMinutes;
  final bool? noteVisible;
  final bool? pretestSkipped;
  final String? sessionIntent;

  SessionOverrides({
    this.leadMinutes,
    this.noteVisible,
    this.pretestSkipped,
    this.sessionIntent,
  }) {
    if (leadMinutes != null && leadMinutes! <= 0) {
      throw ValidationError('提前量必须为正整数');
    }
    if (sessionIntent != null) {
      ensureEnum(sessionIntent!, E.sessionIntents, 'SessionOverrides.sessionIntent');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'leadMinutes': leadMinutes,
        'noteVisible': noteVisible,
        'pretestSkipped': pretestSkipped,
        'sessionIntent': sessionIntent,
      };

  static SessionOverrides fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return SessionOverrides(
      leadMinutes: m['leadMinutes'] as int?,
      noteVisible: m['noteVisible'] as bool?,
      pretestSkipped: m['pretestSkipped'] as bool?,
      sessionIntent: m['sessionIntent'] as String?,
    );
  }
}

/// 全局默认策略。
class Preferences implements Entity {
  String reminderMode;
  int defaultLeadMinutes;
  List<int> leadPresets;
  String startMode;
  bool pretestVisible;
  bool noteVisible;
  List<String> dataOutboundWhitelist;
  String sessionIntent;

  Preferences({
    this.reminderMode = 'vibration',
    this.defaultLeadMinutes = 5,
    List<int>? leadPresets,
    this.startMode = 'immediate',
    this.pretestVisible = true,
    this.noteVisible = true,
    List<String>? dataOutboundWhitelist,
    this.sessionIntent = 'follow',
  })  : leadPresets = leadPresets ?? [2, 5],
        dataOutboundWhitelist =
            dataOutboundWhitelist ?? <String>[] {
    ensureEnum(reminderMode, E.reminderModes, 'Preferences.reminderMode');
    ensureEnum(startMode, E.startModes, 'Preferences.startMode');
    ensureEnum(sessionIntent, E.sessionIntents, 'Preferences.sessionIntent');
    if (defaultLeadMinutes <= 0) {
      throw ValidationError('默认提前量必须为正整数');
    }
    if (leadPresets != null && leadPresets.isEmpty) {
      throw ValidationError('快捷预设不可为空');
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'reminderMode': reminderMode,
        'defaultLeadMinutes': defaultLeadMinutes,
        'leadPresets': leadPresets,
        'startMode': startMode,
        'pretestVisible': pretestVisible,
        'noteVisible': noteVisible,
        'dataOutboundWhitelist': dataOutboundWhitelist,
        'sessionIntent': sessionIntent,
      };

  static Preferences fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return Preferences(
      reminderMode: m['reminderMode'] as String,
      defaultLeadMinutes: m['defaultLeadMinutes'] as int,
      leadPresets: (m['leadPresets'] as List).map((e) => e as int).toList(),
      startMode: m['startMode'] as String,
      pretestVisible: m['pretestVisible'] as bool,
      noteVisible: m['noteVisible'] as bool,
      dataOutboundWhitelist: (m['dataOutboundWhitelist'] as List)
          .map((e) => e.toString())
          .toList(),
      sessionIntent: m['sessionIntent'] as String,
    );
  }
}

/// 策略层总入口：全局默认 + 单次覆盖 + 归档索引。
class PreferencesLayer implements Entity {
  static const String reviewModeFixed = 'fixed2';

  Preferences global;
  final Map<String, SessionOverrides> overrides;
  final Map<String, List<String>> archivedByAnchor;

  PreferencesLayer({
    Preferences? global,
    Map<String, SessionOverrides>? overrides,
    Map<String, List<String>>? archivedByAnchor,
  })  : global = global ?? Preferences(),
        overrides = overrides ?? <String, SessionOverrides>{},
        archivedByAnchor = archivedByAnchor ?? <String, List<String>>{};

  /// 复习模式只读，恒为固定模式 2。
  String get reviewMode => reviewModeFixed;

  /// 明确拒绝任何「配置复习模式」的尝试（不静默忽略）。
  Never setReviewMode(String value) {
    throw ValidationError('复习闭环固定模式 2，不可配置（尝试设为 "$value"）');
  }

  int leadFor(String sessionId) =>
      overrides[sessionId]?.leadMinutes ?? global.defaultLeadMinutes;

  bool noteVisibleFor(String sessionId) =>
      overrides[sessionId]?.noteVisible ?? global.noteVisible;

  bool pretestSkippedFor(String sessionId) =>
      overrides[sessionId]?.pretestSkipped ?? !global.pretestVisible;

  String intentFor(String sessionId) =>
      overrides[sessionId]?.sessionIntent ?? global.sessionIntent;

  bool allowOutbound(String kind) =>
      global.dataOutboundWhitelist.contains(kind);

  void setOverride(String sessionId, SessionOverrides value) =>
      overrides[sessionId] = value;

  void clearOverride(String sessionId) => overrides.remove(sessionId);

  /// 归档登记：显隐开关**只影响渲染，不删除数据**。
  void registerArchived(String anchorId, String noteId) {
    archivedByAnchor.putIfAbsent(anchorId, () => <String>[]).add(noteId);
  }

  /// 检索归档内容，不受笔记显隐影响。
  List<String> findArchived(String anchorId) =>
      List<String>.unmodifiable(archivedByAnchor[anchorId] ?? <String>[]);

  @override
  Map<String, dynamic> toJson() => {
        'global': global.toJson(),
        'overrides':
            overrides.map((k, v) => MapEntry(k, v.toJson())),
        'archivedByAnchor': archivedByAnchor,
        'reviewMode': reviewMode,
      };

  /// 直接作为 .studypack 的 preferences.json 内容。
  Map<String, dynamic> toEntityJson() => toJson();

  static PreferencesLayer fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    if (m['reviewMode'] != null && m['reviewMode'] != reviewModeFixed) {
      throw ValidationError('复习模式被篡改为 "${m['reviewMode']}"，只允许 $reviewModeFixed');
    }
    final ov = <String, SessionOverrides>{};
    for (final e in (m['overrides'] as Map).entries) {
      ov[e.key as String] = SessionOverrides.fromJson(e.value);
    }
    final arch = <String, List<String>>{};
    for (final e in (m['archivedByAnchor'] as Map).entries) {
      arch[e.key as String] =
          (e.value as List).map((x) => x.toString()).toList();
    }
    return PreferencesLayer(
      global: Preferences.fromJson(m['global']),
      overrides: ov,
      archivedByAnchor: arch,
    );
  }
}
