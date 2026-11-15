/// F14 · 界面第一版测试（PRD §4 F14 六条验收逐条 + 硬约束）。
/// 单独运行：dart test/tF14_ui.dart
/// 浏览器渲染校验另见 tools/gen_viewer.dart + Chromium headless 截图。
import 'framework.dart';
import '../lib/core.dart';
import '../lib/models.dart';
import '../lib/studypack.dart';
import '../lib/ui.dart';
import '../lib/viewer.dart';
import '../lib/weakpoint.dart';

const leaf = 'RJ-A-BX1-CH2-2.2-EQ';

UiState _state() => UiState(
      tasks: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'T-1', 'title': '背单词', 'type': 'habit'},
        <String, dynamic>{'id': 'T-2', 'title': '数学专项', 'type': 'once'},
      ],
      plans: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'P-1', 'goal': '精进基本不等式', 'quantTarget': 0.75},
      ],
      slots: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'S-1', 'start': '07:00', 'end': '07:30'},
      ],
      sessions: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'SE-1', 'stage': 'study'},
      ],
      weakPoints: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'WP-1', 'knowledgeNodeId': leaf, 'severity': 4},
      ],
      aiNotes: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'AN-1', 'owner': 'ai'},
      ],
      myNotes: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'MN-1', 'owner': 'mine', 'channel': 'D'},
      ],
      anchorLinks: <Map<String, dynamic>>[
        <String, dynamic>{
          'anchorId': 'a::b::c',
          'aiNoteIds': <String>['AN-1'],
          'myNoteIds': <String>['MN-1'],
        },
      ],
      resources: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'R-1', 'source': '我的资料·讲义.pdf'},
      ],
    );

void runF14(Harness h) {
  // ------------------------------------------------------------------ 验收①
  h.group('F14 验收① 三档断点切换正确', () {
    h.test('宽度 <600 → Compact', () {
      h.eq(layoutFor(0).breakpoint, Breakpoint.compact);
      h.eq(layoutFor(359).breakpoint, Breakpoint.compact);
      h.eq(layoutFor(360).breakpoint, Breakpoint.compact);
      h.eq(layoutFor(599).breakpoint, Breakpoint.compact);
    });

    h.test('宽度 600–839 → Medium', () {
      h.eq(layoutFor(600).breakpoint, Breakpoint.medium);
      h.eq(layoutFor(720).breakpoint, Breakpoint.medium);
      h.eq(layoutFor(839).breakpoint, Breakpoint.medium);
    });

    h.test('宽度 >=840 → Expanded', () {
      h.eq(layoutFor(840).breakpoint, Breakpoint.expanded);
      h.eq(layoutFor(1280).breakpoint, Breakpoint.expanded);
      h.eq(layoutFor(1920).breakpoint, Breakpoint.expanded);
    });

    h.test('负宽度被拒绝', () {
      h.throwsValidation(() => layoutFor(-1));
    });

    h.test('Compact = 底部 4 Tab / 单栏 / Tab 可见', () {
      final s = layoutFor(360);
      h.eq(s.navigation, 'bottomTabs');
      h.eq(s.columns, 1);
      h.isTrue(s.bottomTabVisible);
      h.contains(s.deviceHint, 'vivo S7');
      h.contains(s.noteTakingMode, '分段切换');
    });

    h.test('Medium = NavigationRail / 双栏 / 取消底部 Tab', () {
      final s = layoutFor(720);
      h.eq(s.navigation, 'navigationRail');
      h.eq(s.columns, 2);
      h.isFalse(s.bottomTabVisible);
      h.contains(s.deviceHint, '自动重组');
    });

    h.test('Expanded = 常驻 Rail / 双栏 / 取消底部 Tab', () {
      final s = layoutFor(1280);
      h.eq(s.navigation, 'navigationRail');
      h.eq(s.columns, 2);
      h.isFalse(s.bottomTabVisible);
      h.contains(s.deviceHint, 'Y900');
      h.contains(s.noteTakingMode, '真双栏');
    });

    h.test('分屏导致宽度回落 Medium 时自动重组', () {
      final before = layoutFor(1280);
      final after = recomposeAfterSplit(1280, 720);
      h.eq(before.breakpoint, Breakpoint.expanded);
      h.eq(after.breakpoint, Breakpoint.medium);
      h.eq(after.navigation, 'navigationRail');
      h.isFalse(after.bottomTabVisible);
    });

    h.test('分屏宽度未回落被拒绝（不算重组）', () {
      h.throwsValidation(() => recomposeAfterSplit(720, 1280));
    });

    h.test('三档断点标签与常量齐全', () {
      h.eq(Breakpoint.all.length, 3);
      h.eq(Breakpoint.compactMax, 600);
      h.eq(Breakpoint.expandedMin, 840);
      h.eq(Breakpoint.labels.length, 3);
    });

    h.test('LayoutSpec 可 JSON 往返', () {
      final s = layoutFor(720);
      h.jsonEq(LayoutSpec.fromJson(s.toJson()).toJson(), s.toJson());
    });
  });

  // ------------------------------------------------------------------ 验收②
  h.group('F14 验收② 11 类页面可达且无死链', () {
    h.test('页面清单恰好 11 类且与 PRD §5.2 一致', () {
      RouteTable.assertPageInventory();
      h.eq(RouteTable.pages.length, 11);
      h.eq(PageId.all.length, 11);
    });

    h.test('每个页面 id 都有中文标题', () {
      for (final id in PageId.all) {
        h.isTrue(PageId.labels.containsKey(id), '$id 缺标题');
        h.ok((PageId.labels[id] ?? '').isNotEmpty);
      }
    });

    h.test('无死链：所有 linksTo 都指向已登记页面', () {
      RouteTable.assertNoDeadLinks();
    });

    h.test('从「今日」BFS 可到达全部 11 页', () {
      RouteTable.assertAllReachable();
      h.eq(RouteTable.reachableFrom('today').length, 11);
    });

    h.test('每个页面都能被路由解析', () {
      for (final p in RouteTable.pages) {
        h.eq(RouteTable.resolve(p.path), p.id);
      }
    });

    h.test('非法路径 / 未登记页面被拒绝', () {
      h.throwsValidation(() => RouteTable.resolve('/nope'));
      h.throwsValidation(() => RouteTable.byId('nope'));
      h.throwsValidation(() => RouteTable.reachableFrom('nope'));
    });

    h.test('底部 4 Tab 正好今日 / 规划 / 笔记 / 我的', () {
      h.eq(PageId.bottomTabs.join(','), 'today,planCreate,notes,mine');
      for (final id in PageId.bottomTabs) {
        h.isTrue(PageId.all.contains(id));
      }
    });

    h.test('L0 开关 6 项齐全（接 F4）', () {
      h.eq(PageId.l0Switches.length, 6);
      h.isTrue(PageId.l0Switches.contains('dataOutboundWhitelist'));
      h.isTrue(PageId.l0Switches.contains('aiProvider'));
      h.isFalse(PageId.l0Switches.contains('reviewMode'));
    });

    h.test('PageRoute 可 JSON 往返', () {
      final p = RouteTable.byId('notes');
      h.jsonEq(PageRoute.fromJson(p.toJson()).toJson(), p.toJson());
    });
  });

  // ------------------------------------------------------------------ 验收③
  h.group('F14 验收③ 绿色语义未挪作达标', () {
    h.test('松绿只绑「可学习时段」', () {
      h.eq(SemanticColor.forMeaning('slotAvailable'), ColorTokens.pine);
      h.eq(ColorTokens.greenMeaning, 'slotAvailable');
    });

    h.test('达标 / 通过 / 完成用墨蓝实心，不是松绿', () {
      for (final m in ['achieved', 'passed', 'completed']) {
        h.eq(SemanticColor.forMeaning(m), ColorTokens.brand);
        h.isFalse(SemanticColor.forMeaning(m) == ColorTokens.pine);
      }
    });

    h.test('方案 A 自检通过', () {
      SemanticColor.assertGreenOnlyForSlots();
    });

    h.test('达标带非颜色标记：对勾 + 文字', () {
      final marker = SemanticColor.markerFor('achieved');
      h.contains(marker, '✓');
      h.contains(marker, '已达标');
      h.contains(marker, '文字');
    });

    h.test('薄弱 / 倒计时 / 进行中语义各归其色', () {
      h.eq(SemanticColor.forMeaning('weak'), ColorTokens.alert);
      h.eq(SemanticColor.forMeaning('countdown'), ColorTokens.action);
      h.eq(SemanticColor.forMeaning('inProgress'), ColorTokens.action);
    });

    h.test('未知语义被拒绝；四色不增不减', () {
      h.throwsValidation(() => SemanticColor.forMeaning('vague'));
      h.eq(ColorTokens.palette.length, 4);
      h.eq(ColorTokens.brand, '#204066');
      h.eq(ColorTokens.action, '#E0892E');
      h.eq(ColorTokens.pine, '#2E7D5B');
      h.eq(ColorTokens.alert, '#C0492F');
    });
  });

  // ------------------------------------------------------------------ 验收④
  h.group('F14 验收④ 打印态含非颜色标记', () {
    PrintCard _ok() => PrintCard(
          id: 'RC-1',
          screenText: '等号成立条件｜一正二定三相等',
          printText: '等号成立条件｜一正二定三相等',
          nonColorMarkers: <String>['程度:重', '描边', '▲', '文字标签'],
        );

    h.test('屏幕态与打印态文本一字不差', () {
      final c = _ok();
      h.eq(c.screenText, c.printText);
      h.isTrue(c.monochromeReadable);
    });

    h.test('两态文本不一致被拒绝', () {
      h.throwsValidation(() => PrintCard(
          id: 'X',
          screenText: 'A',
          printText: 'B',
          nonColorMarkers: <String>['a', 'b', 'c']));
    });

    h.test('非颜色标记少于 3 个被拒绝（不能只靠颜色）', () {
      h.throwsValidation(() => PrintCard(
          id: 'X',
          screenText: 'A',
          printText: 'A',
          nonColorMarkers: <String>['描边']));
    });

    h.test('黑白不可读被拒绝', () {
      h.throwsValidation(() => PrintCard(
          id: 'X',
          screenText: 'A',
          printText: 'A',
          nonColorMarkers: <String>['a', 'b', 'c'],
          monochromeReadable: false));
    });

    h.test('复用 F9 速查卡（content 唯一文本源，badges 冗余编码）', () {
      final eng = WeakPointEngine();
      final wp = eng.attribute(AttributionInput(
        knowledgeNodeId: leaf,
        axisKnowledge: 'condition',
        axisGaokao: 'deRoutine',
        axisFeynman: 'fakeUnderstanding',
        evidence: <String>['第 3 题'],
        reminderLine: '一正二定三相等，先问等号取不取得到',
        occurrences: 2,
        distinctSessions: 2,
        sessionId: 'SE-1',
      ));
      final card = eng.buildCard(wp);
      final pc = PrintCard.fromReminder(card);
      h.eq(pc.screenText, pc.printText);
      h.isTrue(pc.nonColorMarkers.length >= 3);
      h.isTrue(pc.nonColorMarkers.contains('▲'));
      h.isTrue(pc.nonColorMarkers.contains('描边'));
    });

    h.test('PrintCard 可 JSON 往返', () {
      final c = _ok();
      h.jsonEq(PrintCard.fromJson(c.toJson()).toJson(), c.toJson());
    });

    h.test('HTML 打印态含 ▲ / 描边 / 文字标签（不只靠颜色）', () {
      final html = HtmlRenderer.render(_state());
      h.contains(html, '▲');
      h.contains(html, '描边');
      h.contains(html, '文字标签');
      h.contains(html, '@media print');
      h.contains(html, 'border:2px dashed #000');
    });
  });

  // ------------------------------------------------------------------ Widget
  h.group('F14 信息克制 · Widget 最小态契约', () {
    h.test('最小态只含最近一个任务 + 倒计时 + 一键打开', () {
      final w = WidgetContract.minimal(task: '背单词', countdown: '00:12');
      WidgetContract.assertMinimal(w);
      h.eq(w['nextTask'], '背单词');
      h.eq(w['countdown'], '00:12');
      h.eq(w['oneTapOpen'], true);
    });

    h.test('出现整张日程 / 全部任务 / 图表 / 笔记被拒绝', () {
      for (final f in WidgetContract.forbiddenFields) {
        h.throwsValidation(() => WidgetContract.assertMinimal(
            <String, dynamic>{...WidgetContract.minimal(
                task: '背单词', countdown: '00:12'), f: 'x'}), '字段 $f');
      }
    });

    h.test('nextTask 必须是单个任务（不能是列表）', () {
      h.throwsValidation(() => WidgetContract.assertMinimal(
          <String, dynamic>{
            'nextTask': <String>['A', 'B'],
            'countdown': '00:12',
            'oneTapOpen': true,
          }));
    });

    h.test('缺一键打开被拒绝', () {
      h.throwsValidation(() => WidgetContract.assertMinimal(
          <String, dynamic>{
            'nextTask': 'A',
            'countdown': '00:12',
            'oneTapOpen': false,
          }));
    });

    h.test('考前速览态一行一个坑、最多 8 行', () {
      final m = WidgetContract.examQuickLook(<String>['一正', '二定', '三相等']);
      h.eq(m['mode'], 'examQuickLook');
      h.eq((m['lines'] as List).length, 3);
      h.throwsValidation(() => WidgetContract.examQuickLook(<String>[]));
      h.throwsValidation(() => WidgetContract.examQuickLook(
          List<String>.generate(9, (i) => '坑$i')));
    });

    h.test('HTML Widget 区块只呈现一个任务', () {
      final html = HtmlRenderer.render(_state());
      h.eq('class="task"'.allMatches(html).length, 1);
      h.contains(html, '一键打开');
    });
  });

  // ------------------------------------------------------------------ 验收⑤
  h.group('F14 验收⑤ 界面数据可导出 .studypack 并被 F2 导入', () {
    h.test('UiState.toPackage 输出 14 类实体文件（含 knowledge_base.json）', () {
      final p = _state().toPackage();
      h.eq(p.entities.length, 14);
      for (final f in DataPackage.entityFiles) {
        h.isTrue(p.entities.containsKey(f), '缺 $f');
      }
    });

    h.test('导出 / 导入往返后数据一致', () {
      final s = _state();
      final files = s.exportStudypack(device: 'vivo S7');
      final back = UiState.importStudypack(files);
      h.eq(back.tasks.length, s.tasks.length);
      h.eq(back.plans.length, s.plans.length);
      h.eq(back.myNotes.length, s.myNotes.length);
      h.eq(back.profile.totalScore, 150);
      h.jsonEq(back.toJson(), s.toJson());
    });

    h.test('导出的包能被 F2 StudyPack.importPack 直接导入', () {
      final files = _state().exportStudypack(device: 'Lenovo Y900');
      final pack = StudyPack.importPack(files);
      h.eq(pack.entities['tasks.json']!.length, 2);
      h.eq(pack.entities['resources.json']!.length, 1);
      h.eq(pack.manifest['schemaVersion'], 1);
    });

    h.test('导出包含 manifest + 14 类实体，且不含凭证字段', () {
      final files = _state().exportStudypack();
      h.ok(files.containsKey(StudyPack.manifestFile));
      for (final f in DataPackage.entityFiles) {
        h.ok(files.containsKey(f));
      }
      h.isFalse(files.values.any((v) => v.toLowerCase().contains('api_key')));
      h.isFalse(files.values.any((v) => v.contains('sk-')));
    });

    h.test('UiState 可 JSON 全量往返', () {
      final s = _state();
      h.jsonEq(UiState.fromJson(s.toJson()).toJson(), s.toJson());
    });

    h.test('空界面状态也能导出合法固定格式', () {
      final files = UiState().exportStudypack();
      final back = UiState.importStudypack(files);
      h.eq(back.tasks.length, 0);
      h.eq(back.profile.paper, '新高考 I 卷（新课标 I 卷）');
    });
  });

  // ------------------------------------------------------------------ 验收⑥
  h.group('F14 验收⑥ 可运行 HTML 查看器契约（浏览器渲染前置）', () {
    final html = HtmlRenderer.render(_state());

    h.test('HTML 自包含：中文声明 / 视口 / 内联样式，无外链资源', () {
      h.contains(html, '<html lang="zh-CN">');
      h.contains(html, '<meta charset="utf-8">');
      h.contains(html, 'name="viewport"');
      h.contains(html, '<style>');
      h.isFalse(html.contains('src="http'));
      h.isFalse(html.contains('href="http'));
    });

    h.test('三档媒体查询齐全：600 / 840 / print', () {
      h.contains(html, '@media (min-width:600px)');
      h.contains(html, '@media (min-width:840px)');
      h.contains(html, '@media print');
    });

    h.test('11 类页面锚点全部存在', () {
      for (final id in PageId.all) {
        h.contains(html, 'id="page-$id"', '缺页面 $id 锚点');
      }
    });

    h.test('四个视觉 token 与语义色区块都在', () {
      h.contains(html, ColorTokens.brand);
      h.contains(html, ColorTokens.action);
      h.contains(html, ColorTokens.pine);
      h.contains(html, ColorTokens.alert);
      h.contains(html, '绿色只表示可学习空闲时段');
      h.contains(html, '✓ 已达标');
    });

    h.test('断点契约表 3 行 + 设备矩阵含 S7 与 Y900', () {
      h.contains(html, 'Compact · 手机竖屏');
      h.contains(html, 'Medium · 分屏回落');
      h.contains(html, 'Expanded · Pad 全屏');
      h.contains(html, 'vivo S7');
      h.contains(html, 'Lenovo Y900');
    });

    h.test('底部 4 Tab 与侧栏导航都在，且无死链锚点', () {
      h.contains(html, 'class="tabbar');
      h.contains(html, 'class="rail ');
      for (final id in PageId.bottomTabs) {
        h.contains(html, 'data-page="$id"');
      }
      for (final id in PageId.all) {
        h.contains(html, 'href="#page-$id"');
      }
    });

    h.test('所有占位符都已替换，中文内容正常', () {
      h.isFalse(html.contains('{{'));
      h.contains(html, '基本不等式');
      h.contains(html, '一正二定三相等');
      h.contains(html, '.studypack');
      h.contains(html, '固定模式 2');
    });

    h.test('L0 开关与数据统计随 UiState 注入', () {
      h.contains(html, 'dataOutboundWhitelist');
      h.contains(html, 'aiProvider');
      h.contains(html, '<strong class="num">2</strong>'); // 任务数
    });
  });
}

void main() {
  final h = Harness();
  runF14(h);
  h.report();
}
