/// F14 · 界面契约层（业务规则真源，PRD §4 F14 / §5）。
///
/// 本层不依赖任何 UI 框架：断点判定、11 类页面路由、语义色、打印态、
/// Widget 最小态、`.studypack` 数据读写全部可写成断言。
/// `lib/viewer.dart` 只负责把本层契约渲染成可运行 HTML 查看器。
///
/// 零第三方依赖，兼容 Dart 2.17。
library study_agent.ui;

import 'core.dart';
import 'models.dart';
import 'preferences.dart';
import 'studypack.dart';

// ------------------------------------------------------------------ 断点
class Breakpoint {
  static const String compact = 'compact';
  static const String medium = 'medium';
  static const String expanded = 'expanded';
  static const List<String> all = [compact, medium, expanded];

  /// Compact: <600dp；Medium: 600–839dp；Expanded: >=840dp。
  static const int compactMax = 600;
  static const int expandedMin = 840;

  static const Map<String, String> labels = {
    compact: 'Compact · 手机竖屏（vivo S7 360dp）',
    medium: 'Medium · 分屏回落 / S7 横屏',
    expanded: 'Expanded · Pad 全屏（Lenovo Y900 13"）',
  };
}

/// 某一窗口宽度下的布局规格。
class LayoutSpec implements Entity {
  final String breakpoint;
  final int width;
  final String navigation; // bottomTabs / navigationRail
  final int columns;
  final bool bottomTabVisible;
  final String deviceHint;
  final String noteTakingMode;

  const LayoutSpec({
    required this.breakpoint,
    required this.width,
    required this.navigation,
    required this.columns,
    required this.bottomTabVisible,
    required this.deviceHint,
    required this.noteTakingMode,
  });

  @override
  Map<String, dynamic> toJson() => {
        'breakpoint': breakpoint,
        'width': width,
        'navigation': navigation,
        'columns': columns,
        'bottomTabVisible': bottomTabVisible,
        'deviceHint': deviceHint,
        'noteTakingMode': noteTakingMode,
      };

  static LayoutSpec fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return LayoutSpec(
      breakpoint: m['breakpoint'] as String,
      width: m['width'] as int,
      navigation: m['navigation'] as String,
      columns: m['columns'] as int,
      bottomTabVisible: m['bottomTabVisible'] as bool,
      deviceHint: m['deviceHint'] as String,
      noteTakingMode: m['noteTakingMode'] as String,
    );
  }
}

/// 按**当前窗口宽度**判定，不按设备型号；分屏导致宽度回落会自动重组。
LayoutSpec layoutFor(int width) {
  if (width < 0) throw ValidationError('窗口宽度不可为负: $width');
  if (width < Breakpoint.compactMax) {
    return LayoutSpec(
      breakpoint: Breakpoint.compact,
      width: width,
      navigation: 'bottomTabs',
      columns: 1,
      bottomTabVisible: true,
      deviceHint: 'vivo S7 · 360dp · 碎片端',
      noteTakingMode: '分段切换 + 角标跳转',
    );
  }
  if (width < Breakpoint.expandedMin) {
    return LayoutSpec(
      breakpoint: Breakpoint.medium,
      width: width,
      navigation: 'navigationRail',
      columns: 2,
      bottomTabVisible: false,
      deviceHint: 'Y900 分屏半屏 / S7 横屏 · 自动重组',
      noteTakingMode: '双栏 list-detail',
    );
  }
  return LayoutSpec(
    breakpoint: Breakpoint.expanded,
    width: width,
    navigation: 'navigationRail',
    columns: 2,
    bottomTabVisible: false,
    deviceHint: 'Lenovo Y900 13" · 整块端 · A 通道分屏主战场',
    noteTakingMode: '真双栏：左 AI 笔记 ‖ 右手写',
  );
}

/// 分屏导致窗口宽度回落时，返回新布局并断言确实发生了重组。
LayoutSpec recomposeAfterSplit(int originalWidth, int splitWidth) {
  final before = layoutFor(originalWidth);
  final after = layoutFor(splitWidth);
  if (after.width >= before.width) {
    throw ValidationError('分屏后窗口宽度应回落，实际 ${before.width} → ${after.width}');
  }
  return after;
}

// ------------------------------------------------------------------ 页面与路由
class PageId {
  /// PRD §5.2 的 11 类页面 / 组件。
  static const List<String> all = [
    'widget',
    'today',
    'calendar',
    'taskDetail',
    'planCreate',
    'studySession',
    'reviewLoop',
    'examCard',
    'notes',
    'mine',
    'dataTransfer',
  ];

  static const Map<String, String> labels = {
    'widget': '桌面 Widget 最小态',
    'today': '今日视图',
    'calendar': '全局日历',
    'taskDetail': '任务详情 / 编辑',
    'planCreate': '规划创建',
    'studySession': '学习会话页',
    'reviewLoop': '复习闭环页',
    'examCard': '薄弱点速查卡',
    'notes': '笔记',
    'mine': '我的（L0 开关）',
    'dataTransfer': '数据导入导出',
  };

  /// 底部 4 Tab（Compact）。
  static const List<String> bottomTabs = [
    'today',
    'planCreate',
    'notes',
    'mine',
  ];

  /// L0 策略开关页必须覆盖的项（接 F4）。
  static const List<String> l0Switches = [
    'reminderMode',
    'leadMinutes',
    'pretestVisible',
    'noteVisible',
    'dataOutboundWhitelist',
    'aiProvider',
  ];
}

class PageRoute implements Entity {
  final String id;
  final String path;
  final String navGroup; // widget / tab / rail / flow
  final List<String> linksTo;

  const PageRoute({
    required this.id,
    required this.path,
    required this.navGroup,
    required this.linksTo,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'navGroup': navGroup,
        'linksTo': linksTo,
      };

  static PageRoute fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return PageRoute(
      id: m['id'] as String,
      path: m['path'] as String,
      navGroup: m['navGroup'] as String,
      linksTo: (m['linksTo'] as List).map((e) => e.toString()).toList(),
    );
  }
}

/// 路由表：11 类页面构成一个连通图，保证「可达且无死链」。
class RouteTable {
  static const List<PageRoute> pages = [
    PageRoute(id: 'today', path: '/today', navGroup: 'tab',
        linksTo: ['taskDetail', 'planCreate', 'calendar', 'studySession', 'widget']),
    PageRoute(id: 'calendar', path: '/calendar', navGroup: 'rail',
        linksTo: ['today', 'planCreate', 'taskDetail']),
    PageRoute(id: 'taskDetail', path: '/task/:id', navGroup: 'flow',
        linksTo: ['today']),
    PageRoute(id: 'planCreate', path: '/plan/new', navGroup: 'tab',
        linksTo: ['calendar', 'studySession', 'today']),
    PageRoute(id: 'studySession', path: '/session/:id', navGroup: 'flow',
        linksTo: ['reviewLoop', 'examCard', 'notes', 'today']),
    PageRoute(id: 'reviewLoop', path: '/review/:id', navGroup: 'flow',
        linksTo: ['studySession', 'examCard']),
    PageRoute(id: 'examCard', path: '/exam-card', navGroup: 'flow',
        linksTo: ['notes', 'today']),
    PageRoute(id: 'notes', path: '/notes', navGroup: 'tab',
        linksTo: ['mine', 'examCard', 'studySession']),
    PageRoute(id: 'mine', path: '/mine', navGroup: 'tab',
        linksTo: ['notes', 'dataTransfer', 'today']),
    PageRoute(id: 'dataTransfer', path: '/data', navGroup: 'rail',
        linksTo: ['mine', 'today']),
    PageRoute(id: 'widget', path: '/widget', navGroup: 'widget',
        linksTo: ['today', 'calendar', 'examCard']),
  ];

  static List<String> get ids => pages.map((p) => p.id).toList();

  static PageRoute byId(String id) {
    for (final p in pages) {
      if (p.id == id) return p;
    }
    throw ValidationError('未登记的页面: $id');
  }

  /// 页面清单必须与 PRD §5.2 的 11 类完全一致。
  static void assertPageInventory() {
    if (pages.length != 11) {
      throw ValidationError('页面清单应为 11 类，实际 ${pages.length}');
    }
    final allIds = ids.toSet();
    if (allIds.length != 11) throw ValidationError('页面 id 重复');
    for (final id in PageId.all) {
      if (!allIds.contains(id)) throw ValidationError('缺少页面: $id');
    }
  }

  /// 每个出站链接都必须指向已登记页面（无死链）。
  static void assertNoDeadLinks() {
    final allIds = ids.toSet();
    for (final p in pages) {
      for (final l in p.linksTo) {
        if (!allIds.contains(l)) {
          throw ValidationError('死链：${p.id} → $l');
        }
      }
    }
  }

  /// 从「今日」出发做 BFS，所有页面都必须可达。
  static List<String> reachableFrom(String start) {
    if (!ids.contains(start)) throw ValidationError('起始页面不存在: $start');
    final seen = <String>{};
    final queue = <String>[start];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (seen.contains(cur)) continue;
      seen.add(cur);
      queue.addAll(byId(cur).linksTo);
    }
    return seen.toList()..sort();
  }

  static void assertAllReachable() {
    final seen = reachableFrom('today').toSet();
    final missing = ids.toSet().difference(seen);
    if (missing.isNotEmpty) {
      throw ValidationError('存在不可达页面: ${missing.join(', ')}');
    }
  }

  static String resolve(String path) {
    for (final p in pages) {
      if (p.path == path) return p.id;
    }
    throw ValidationError('无法解析路由: $path');
  }

  static Map<String, dynamic> toJson() => {
        'pages': pages.map((p) => p.toJson()).toList(),
      };
}

// ------------------------------------------------------------------ 视觉语义
class ColorTokens {
  /// 千问定稿 tokens（PRD §5.1），四色不增不减。
  static const String brand = '#204066'; // 墨蓝 · 导航 / 品牌 / 主按钮
  static const String action = '#E0892E'; // 琥珀 · 倒计时 / 进行中 / 提醒
  static const String pine = '#2E7D5B'; // 松绿 · 仅「可学习空闲时段」
  static const String alert = '#C0492F'; // 朱砂 · 薄弱点 / 未达标 / 挑战

  static const Map<String, String> palette = {
    'brand': brand,
    'action': action,
    'pine': pine,
    'alert': alert,
  };

  /// 方案 A：松绿只绑这一个语义。
  static const String greenMeaning = 'slotAvailable';
}

/// 语义色映射：绿色绝不挪作「达标 / 完成 / ≥75%」。
class SemanticColor {
  static String forMeaning(String meaning) {
    switch (meaning) {
      case 'slotAvailable':
        return ColorTokens.pine;
      case 'achieved':
      case 'passed':
      case 'completed':
        return ColorTokens.brand; // 墨蓝实心 + 对勾 / 文字
      case 'inProgress':
      case 'countdown':
        return ColorTokens.action;
      case 'weak':
      case 'failed':
      case 'challenge':
        return ColorTokens.alert;
      default:
        throw ValidationError('未知颜色语义: $meaning');
    }
  }

  /// 非颜色冗余编码（不能只靠颜色区分）。
  static String markerFor(String meaning) {
    switch (meaning) {
      case 'achieved':
      case 'passed':
      case 'completed':
        return '✓ 已达标（墨蓝实心 + 对勾 + 文字）';
      case 'slotAvailable':
        return '可学习时段（松绿专色 + 「可学」文字）';
      case 'weak':
      case 'failed':
        return '▲ 薄弱（朱砂 + 三角形 + 文字标签）';
      default:
        return '文字标签';
    }
  }

  /// 方案 A 自检：除 slotAvailable 外，任何语义都不得返回松绿。
  static void assertGreenOnlyForSlots() {
    if (forMeaning(ColorTokens.greenMeaning) != ColorTokens.pine) {
      throw ValidationError('可学习时段必须绑定松绿');
    }
    for (final m in [
      'achieved', 'passed', 'completed', 'inProgress', 'countdown',
      'weak', 'failed', 'challenge'
    ]) {
      if (forMeaning(m) == ColorTokens.pine) {
        throw ValidationError('绿色被挪作 "$m"，违反方案 A');
      }
    }
  }
}

// ------------------------------------------------------------------ 打印态
/// 速查卡屏幕态 / 打印态同源，且黑白可读（非颜色标记冗余编码）。
class PrintCard implements Entity {
  final String id;
  final String screenText;
  final String printText;
  final List<String> nonColorMarkers;
  final bool monochromeReadable;

  PrintCard({
    required this.id,
    required this.screenText,
    required this.printText,
    required this.nonColorMarkers,
    this.monochromeReadable = true,
  }) {
    if (screenText != printText) {
      throw ValidationError('屏幕态与打印态必须同源，文本一字不差');
    }
    if (nonColorMarkers.length < 3) {
      throw ValidationError(
          '打印态不能只靠颜色：需至少 3 个非颜色标记（描边 / 图标 / 文字标签）');
    }
    if (!monochromeReadable) {
      throw ValidationError('打印态必须黑白可读');
    }
  }

  /// 复用 F9 的 ExamReminderCard（content 是唯一文本源）。
  static PrintCard fromReminder(ExamReminderCard card) => PrintCard(
        id: card.id,
        screenText: card.screenText,
        printText: card.printText,
        nonColorMarkers: List<String>.from(card.badges),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'screenText': screenText,
        'printText': printText,
        'nonColorMarkers': nonColorMarkers,
        'monochromeReadable': monochromeReadable,
      };

  static PrintCard fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    return PrintCard(
      id: m['id'] as String,
      screenText: m['screenText'] as String,
      printText: m['printText'] as String,
      nonColorMarkers:
          (m['nonColorMarkers'] as List).map((e) => e.toString()).toList(),
      monochromeReadable: m['monochromeReadable'] as bool,
    );
  }
}

// ------------------------------------------------------------------ Widget 最小态
class WidgetContract {
  static const List<String> requiredFields = [
    'nextTask',
    'countdown',
    'oneTapOpen',
  ];

  /// 信息克制：最小态不得塞整张日程 / 全部任务 / 图表 / 笔记。
  static const List<String> forbiddenFields = [
    'fullSchedule',
    'allTasks',
    'charts',
    'notes',
  ];

  static Map<String, dynamic> minimal({
    required String task,
    required String countdown,
    bool examMode = false,
  }) =>
      <String, dynamic>{
        'nextTask': task,
        'countdown': countdown,
        'oneTapOpen': true,
        'examMode': examMode,
      };

  static void assertMinimal(Map<String, dynamic> widget) {
    for (final f in requiredFields) {
      if (!widget.containsKey(f) || widget[f] == null) {
        throw ValidationError('Widget 最小态缺少 $f');
      }
    }
    if (widget['nextTask'] is! String) {
      throw ValidationError('Widget 只显示**最近一个**任务，nextTask 必须是单个字符串');
    }
    if (widget['oneTapOpen'] != true) {
      throw ValidationError('Widget 必须提供一键打开');
    }
    for (final f in forbiddenFields) {
      if (widget.containsKey(f)) {
        throw ValidationError('Widget 最小态不得含 $f（信息克制）');
      }
    }
  }

  /// 考前速览态：一行一个坑，信息克制。
  static Map<String, dynamic> examQuickLook(List<String> lines) {
    if (lines.isEmpty) throw ValidationError('考前速览至少一条');
    if (lines.length > 8) {
      throw ValidationError('考前速览信息克制：最多 8 行，实际 ${lines.length}');
    }
    return <String, dynamic>{
      'mode': 'examQuickLook',
      'lines': lines,
    };
  }
}

// ------------------------------------------------------------------ 数据契约
/// 界面读写的数据：消费同一份 `.studypack` schema，可导出 / 导入。
class UiState implements Entity {
  final PreferencesLayer prefs;
  final ExamProfile profile;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> slots;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> weakPoints;
  final List<Map<String, dynamic>> aiNotes;
  final List<Map<String, dynamic>> myNotes;
  final List<Map<String, dynamic>> anchorLinks;
  final List<Map<String, dynamic>> resources;

  UiState({
    PreferencesLayer? prefs,
    ExamProfile? profile,
    List<Map<String, dynamic>>? tasks,
    List<Map<String, dynamic>>? plans,
    List<Map<String, dynamic>>? slots,
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? weakPoints,
    List<Map<String, dynamic>>? aiNotes,
    List<Map<String, dynamic>>? myNotes,
    List<Map<String, dynamic>>? anchorLinks,
    List<Map<String, dynamic>>? resources,
  })  : prefs = prefs ?? PreferencesLayer(),
        profile = profile ?? ExamProfile.shenzhen(),
        tasks = tasks ?? <Map<String, dynamic>>[],
        plans = plans ?? <Map<String, dynamic>>[],
        slots = slots ?? <Map<String, dynamic>>[],
        sessions = sessions ?? <Map<String, dynamic>>[],
        weakPoints = weakPoints ?? <Map<String, dynamic>>[],
        aiNotes = aiNotes ?? <Map<String, dynamic>>[],
        myNotes = myNotes ?? <Map<String, dynamic>>[],
        anchorLinks = anchorLinks ?? <Map<String, dynamic>>[],
        resources = resources ?? <Map<String, dynamic>>[];

  /// 转成 `.studypack` 的 13 类实体（缺的由 exportPack 补空数组）。
  DataPackage toPackage() => DataPackage(
        entities: <String, List<Map<String, dynamic>>>{
          'preferences.json': <Map<String, dynamic>>[prefs.toEntityJson()],
          'exam_profile.json': <Map<String, dynamic>>[profile.toJson()],
          'school_calendar.json': <Map<String, dynamic>>[],
          'slot_pool.json': slots,
          'tasks.json': tasks,
          'plans.json': plans,
          'sessions.json': sessions,
          'weak_points.json': weakPoints,
          'review.json': <Map<String, dynamic>>[],
          'ai_notes.json': aiNotes,
          'my_notes.json': myNotes,
          'anchor_links.json': anchorLinks,
          'resources.json': resources,
        },
      );

  static List<Map<String, dynamic>> _list(
          Map<String, List<Map<String, dynamic>>> e, String key) =>
      List<Map<String, dynamic>>.from(e[key] ?? <Map<String, dynamic>>[]);

  static UiState fromPackage(DataPackage pack) {
    final e = pack.entities;
    return UiState(
      prefs: (e['preferences.json'] ?? const <Map<String, dynamic>>[]).isEmpty
          ? PreferencesLayer()
          : PreferencesLayer.fromJson(e['preferences.json']!.first),
      profile: (e['exam_profile.json'] ?? const <Map<String, dynamic>>[]).isEmpty
          ? ExamProfile.shenzhen()
          : ExamProfile.fromJson(e['exam_profile.json']!.first),
      tasks: _list(e, 'tasks.json'),
      plans: _list(e, 'plans.json'),
      slots: _list(e, 'slot_pool.json'),
      sessions: _list(e, 'sessions.json'),
      weakPoints: _list(e, 'weak_points.json'),
      aiNotes: _list(e, 'ai_notes.json'),
      myNotes: _list(e, 'my_notes.json'),
      anchorLinks: _list(e, 'anchor_links.json'),
      resources: _list(e, 'resources.json'),
    );
  }

  /// 验收⑤：界面数据导出为 `.studypack`。
  Map<String, String> exportStudypack({String device = 'unknown'}) =>
      StudyPack.exportPack(toPackage(), device: device);

  /// 验收⑤：从 `.studypack` 恢复界面数据（接 F2）。
  static UiState importStudypack(Map<String, String> files) =>
      fromPackage(StudyPack.importPack(files));

  @override
  Map<String, dynamic> toJson() => {
        'prefs': prefs.toJson(),
        'profile': profile.toJson(),
        'tasks': tasks,
        'plans': plans,
        'slots': slots,
        'sessions': sessions,
        'weakPoints': weakPoints,
        'aiNotes': aiNotes,
        'myNotes': myNotes,
        'anchorLinks': anchorLinks,
        'resources': resources,
      };

  static UiState fromJson(Object? json) {
    final m = Map<String, dynamic>.from(json as Map);
    List<Map<String, dynamic>> li(String k) =>
        (m[k] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return UiState(
      prefs: PreferencesLayer.fromJson(m['prefs']),
      profile: ExamProfile.fromJson(m['profile']),
      tasks: li('tasks'),
      plans: li('plans'),
      slots: li('slots'),
      sessions: li('sessions'),
      weakPoints: li('weakPoints'),
      aiNotes: li('aiNotes'),
      myNotes: li('myNotes'),
      anchorLinks: li('anchorLinks'),
      resources: li('resources'),
    );
  }
}
