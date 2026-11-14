/// F14 · 可运行轻量查看器层。
///
/// 只做一件事：把 `lib/ui.dart` 的契约（断点 / 11 类页面 / 语义色 /
/// 打印态 / Widget 最小态 / .studypack）渲染成**单文件 HTML**，
/// 供 Chromium 实际渲染验收。业务规则仍以 `lib/` 为唯一真源。
library study_agent.viewer;

import 'ui.dart';

class HtmlRenderer {
  /// 渲染完整、自包含、无需外链的 HTML。
  static String render(UiState state) => _template
      .replaceAll('{{BRAND}}', ColorTokens.brand)
      .replaceAll('{{ACTION}}', ColorTokens.action)
      .replaceAll('{{PINE}}', ColorTokens.pine)
      .replaceAll('{{ALERT}}', ColorTokens.alert)
      .replaceAll('{{PAGE_CARDS}}', _pageCards())
      .replaceAll('{{TAB_ITEMS}}', _tabItems())
      .replaceAll('{{RAIL_ITEMS}}', _railItems())
      .replaceAll('{{BREAKPOINT_ROWS}}', _breakpointRows())
      .replaceAll('{{L0_ITEMS}}', _l0Items())
      .replaceAll('{{DATA_SUMMARY}}', _dataSummary(state))
      .replaceAll('{{WIDGET_TASK}}', '打开不背单词 · 背单词（习惯性任务）')
      .replaceAll('{{COUNTDOWN}}', '00:12');

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static const Map<String, List<String>> _points = {
    'widget': [
      '只显示最近一个任务 + 倒计时，一键打开',
      '常驻桌面，不打开 App 也能看',
      '另有考前速览态：一行一个坑',
      '信息克制：不塞整张日程 / 全部任务',
    ],
    'today': [
      '最近任务一键跳转外部 App（习惯性任务可抽象替换）',
      '今日时间轴：任务 / 规划学习 / 复习在同一条线',
      '距下一个任务倒计时（等宽数字，跳动不抖动）',
      '绿色 = 可学习空闲时段，叠加在时间轴上',
    ],
    'calendar': [
      '月 / 周视图，全局而非仅今日',
      '任务 / 规划学习 / 校历三层叠加',
      '绿色时段可点选，直接作为规划排期入口',
      '特殊时段（校运会等）可自定义',
    ],
    'taskDetail': [
      '习惯性任务 vs 一次性任务',
      '周期、提醒方式：振动 / 声音 / 无',
      '提前量可自定义，也可直接点 2 min / 5 min',
      '一键跳转动作不含任何凭证',
    ],
    'planCreate': [
      '目标 + 75% + 15 天 + 挑绿色空闲时段',
      '立即开始 / 将来开始两个选项（不代选）',
      '分步向导，一屏一步，别一屏塞满',
      'Pad 端单屏双栏：左表单，右日历 + 容量匹配预览',
    ],
    'studySession': [
      '视频 / 题目 / 内置笔记区（可显示 / 不显示）',
      '测验 → 达标进费曼总结；未达标记错因归因回路',
      '5 阶段状态可见；AI 待处理不阻塞看视频 / 记笔记',
      'SessionIntent：跟随 / 挑战 / 刷自信，进练习前点选',
    ],
    'reviewLoop': [
      '下次学习前先复述上次理解 → AI 纠正',
      '没问题后给几道题简单练手 → 今日学习内容',
      '固定模式 2，不可跳过、不可配置',
      '碎片时段（20/30min）跑复习，整块时段上新内容',
    ],
    'examCard': [
      '每条一行：知识点 + 一行提醒 + 薄弱程度',
      '屏幕态与打印态同源，文本一字不差',
      '教学区域禁用电子设备 → 纸质卡是刚需',
      '打印态黑白可读：描边 + ▲ 图标 + 文字标签，不只靠颜色',
    ],
    'notes': [
      'AI 笔记 / 我的笔记两份独立存，不合订',
      '角标「笔迹 2」双向跳转（anchorId 本地索引）',
      'A 分屏跳转 / C PDF 归档 / D 内置笔记区三通道',
      '默认不把笔记交给 AI；OCR 摘要不覆盖原始笔迹',
    ],
    'mine': [
      'L0 策略开关：有这个功能，但用不用由我定',
      '提醒方式 / 提前量 / 摸底测验 / 笔记区显隐',
      '数据外发白名单 / AI Provider 配置',
      '复习模式固定 2，此处不提供开关',
    ],
    'dataTransfer': [
      '.studypack 纯开放不加密，所有用户数据能带走',
      '13 类实体 + manifest（schemaVersion / checksum）',
      '凭证不进包；第三方版权内容只存引用与标签',
      '导出 / 导入 / 校验 / 敏感内容说明',
    ],
  };

  static String _pageCards() {
    final buf = StringBuffer();
    for (final p in RouteTable.pages) {
      final label = PageId.labels[p.id] ?? p.id;
      final pts = _points[p.id] ?? const <String>[];
      buf.writeln('<section class="card" id="page-${p.id}">');
      buf.writeln('  <div class="card-head">');
      buf.writeln('    <span class="page-no">${RouteTable.pages.indexOf(p) + 1}</span>');
      buf.writeln('    <h2>${_esc(label)}</h2>');
      buf.writeln('    <span class="chip muted">${_esc(p.navGroup)}</span>');
      buf.writeln('  </div>');
      buf.writeln('  <p class="route">路由 <code>${_esc(p.path)}</code></p>');
      buf.writeln('  <ul>');
      for (final t in pts) {
        buf.writeln('    <li>${_esc(t)}</li>');
      }
      buf.writeln('  </ul>');
      buf.writeln('  <p class="links">可达：${p.linksTo.map(_esc).join(' · ')}</p>');
      buf.writeln('</section>');
    }
    return buf.toString();
  }

  static String _tabItems() {
    final buf = StringBuffer();
    for (final id in PageId.bottomTabs) {
      buf.writeln('<a class="tab" href="#page-$id" data-page="$id">'
          '<span class="tab-dot"></span>${_esc(PageId.labels[id] ?? id)}</a>');
    }
    return buf.toString();
  }

  static String _railItems() {
    final buf = StringBuffer();
    for (final id in PageId.all) {
      buf.writeln('<a class="rail-item" href="#page-$id" data-page="$id">'
          '${_esc(PageId.labels[id] ?? id)}</a>');
    }
    return buf.toString();
  }

  static String _breakpointRows() {
    final specs = <LayoutSpec>[
      layoutFor(360),
      layoutFor(720),
      layoutFor(1280),
    ];
    final buf = StringBuffer();
    for (final s in specs) {
      buf.writeln('<tr>');
      buf.writeln('  <td><strong>${_esc(Breakpoint.labels[s.breakpoint] ?? s.breakpoint)}</strong></td>');
      buf.writeln('  <td class="num">${s.width}dp</td>');
      buf.writeln('  <td>${_esc(s.navigation)}</td>');
      buf.writeln('  <td class="num">${s.columns}</td>');
      buf.writeln('  <td>${s.bottomTabVisible ? '底部 4 Tab' : '取消底部 Tab'}</td>');
      buf.writeln('  <td>${_esc(s.noteTakingMode)}</td>');
      buf.writeln('</tr>');
    }
    return buf.toString();
  }

  static String _l0Items() {
    final buf = StringBuffer();
    for (final k in PageId.l0Switches) {
      buf.writeln('<span class="chip">${_esc(k)}</span>');
    }
    return buf.toString();
  }

  static String _dataSummary(UiState s) {
    final rows = <String, int>{
      '任务': s.tasks.length,
      '规划': s.plans.length,
      '时段': s.slots.length,
      '会话': s.sessions.length,
      '薄弱点': s.weakPoints.length,
      'AI 笔记': s.aiNotes.length,
      '我的笔记': s.myNotes.length,
      '锚点关联': s.anchorLinks.length,
      '资源': s.resources.length,
    };
    final buf = StringBuffer();
    for (final e in rows.entries) {
      buf.writeln('<div class="stat"><span>${_esc(e.key)}</span>'
          '<strong class="num">${e.value}</strong></div>');
    }
    return buf.toString();
  }

  static const String _template = r"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>学习助手 App · 界面第一版（F14 可验收查看器）</title>
<style>
:root{
  --brand:{{BRAND}}; --action:{{ACTION}}; --pine:{{PINE}}; --alert:{{ALERT}};
  --ink:#1B2A3A; --paper:#F7F5F0; --line:#D9D4C8; --muted:#6B7684;
  --radius:16px;
}
*{box-sizing:border-box;}
html,body{margin:0;padding:0;}
body{
  font-family:"Noto Sans CJK SC","Noto Sans SC","Source Han Sans SC",sans-serif;
  background:var(--paper); color:var(--ink); line-height:1.6;
  -webkit-font-smoothing:antialiased;
}
h1,h2,h3{font-family:"Noto Serif CJK SC","Noto Serif SC",serif;margin:0;}
.num,.countdown{font-variant-numeric:tabular-nums;font-feature-settings:"tnum";}
a{color:inherit;text-decoration:none;}
code{font-family:ui-monospace,monospace;background:#EFEBE1;padding:1px 5px;border-radius:4px;font-size:12px;}
.app{max-width:100%;min-height:100vh;padding-bottom:76px;}
.topbar{
  background:var(--brand); color:#fff; padding:16px;
  display:flex;flex-wrap:wrap;gap:8px;align-items:baseline;
}
.topbar h1{font-size:18px;}
.topbar .sub{font-size:12px;opacity:.85;}
.topbar .badge{margin-left:auto;font-size:11px;border:1px solid rgba(255,255,255,.5);border-radius:999px;padding:2px 10px;}
.shell{display:block;}
.rail{display:none;background:#fff;border-right:1px solid var(--line);padding:12px 8px;}
.rail-item{display:block;padding:8px 10px;border-radius:10px;font-size:13px;color:var(--muted);}
.rail-item:hover,.rail-item.active{background:#EFEBE1;color:var(--brand);font-weight:600;}
.content{padding:16px;max-width:100%;}
.hero{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:16px;margin-bottom:16px;}
.hero h2{font-size:16px;margin-bottom:6px;}
.hero p{margin:0;font-size:13px;color:var(--muted);}
.cards{display:grid;grid-template-columns:1fr;gap:12px;}
.card{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:14px;min-width:0;}
.card.active{outline:2px solid var(--brand);}
.card-head{display:flex;align-items:center;gap:8px;flex-wrap:wrap;}
.card-head h2{font-size:15px;}
.page-no{
  display:inline-flex;align-items:center;justify-content:center;
  width:24px;height:24px;border-radius:8px;background:var(--brand);color:#fff;
  font-size:12px;font-weight:700;flex:0 0 auto;
}
.chip{display:inline-block;font-size:11px;border-radius:999px;padding:2px 9px;background:#EFEBE1;color:var(--brand);margin:2px 4px 2px 0;}
.chip.muted{background:#EDEAE2;color:var(--muted);}
.route{font-size:12px;color:var(--muted);margin:8px 0;}
.card ul{margin:8px 0;padding-left:18px;font-size:13px;}
.card li{margin:3px 0;word-break:break-word;}
.links{font-size:11px;color:var(--muted);border-top:1px dashed var(--line);padding-top:8px;margin:8px 0 0;word-break:break-word;}
.tabbar{
  position:fixed;left:0;right:0;bottom:0;display:flex;background:#fff;
  border-top:1px solid var(--line);z-index:10;
}
.tab{flex:1;text-align:center;padding:9px 2px;font-size:11px;color:var(--muted);min-width:0;}
.tab-dot{display:block;width:6px;height:6px;border-radius:50%;background:var(--line);margin:0 auto 4px;}
.tab.active{color:var(--brand);font-weight:700;}
.tab.active .tab-dot{background:var(--brand);}
.block{background:#fff;border:1px solid var(--line);border-radius:var(--radius);padding:14px;margin-top:16px;}
.block h2{font-size:16px;margin-bottom:8px;}
.block p{font-size:13px;color:var(--muted);margin:6px 0;}
table{border-collapse:collapse;width:100%;font-size:12px;}
th,td{border-bottom:1px solid var(--line);padding:7px 6px;text-align:left;vertical-align:top;word-break:break-word;}
th{background:#EFEBE1;color:var(--brand);font-weight:600;}
.table-wrap{overflow-x:auto;}
.widget{
  background:var(--brand);color:#fff;border-radius:22px;padding:16px;max-width:340px;
}
.widget .label{font-size:11px;opacity:.8;letter-spacing:.08em;}
.widget .task{font-size:15px;font-weight:700;margin:6px 0;word-break:break-word;}
.widget .row{display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;}
.widget .countdown{font-size:26px;font-weight:700;}
.widget .open{font-size:12px;border:1px solid rgba(255,255,255,.7);border-radius:999px;padding:3px 12px;}
.slot-chip{background:var(--pine);color:#fff;border-radius:8px;padding:3px 10px;font-size:12px;}
.achieved-chip{background:var(--brand);color:#fff;border-radius:8px;padding:3px 10px;font-size:12px;}
.weak-chip{background:var(--alert);color:#fff;border-radius:8px;padding:3px 10px;font-size:12px;}
.legend{display:flex;gap:8px;flex-wrap:wrap;margin:10px 0;font-size:12px;align-items:center;}
.print-card{
  border:2px dashed #222;background:#fff;color:#111;padding:12px;margin-top:10px;
  font-size:13px;word-break:break-word;
}
.print-card .marker{font-weight:700;letter-spacing:.04em;}
.mono-note{font-size:12px;color:var(--muted);}
.stats{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-top:10px;}
.stat{display:flex;justify-content:space-between;background:#EFEBE1;border-radius:10px;padding:7px 10px;font-size:12px;}
.device-row{display:grid;grid-template-columns:1fr;gap:10px;margin-top:10px;}
.device{background:#EFEBE1;border-radius:12px;padding:10px;font-size:12px;word-break:break-word;}
.device b{color:var(--brand);}
.footer{text-align:center;font-size:11px;color:var(--muted);padding:18px 12px 8px;}
/* Compact: <600dp —— 底部 4 Tab 单栏 */
@media (min-width:600px){
  .app{padding-bottom:0;}
  .tabbar{display:none;}
  .shell{display:grid;grid-template-columns:80px minmax(0,1fr);}
  .rail{display:block;}
  .content{padding:20px;}
  .cards{grid-template-columns:repeat(2,minmax(0,1fr));}
  .device-row{grid-template-columns:repeat(2,minmax(0,1fr));}
  .stats{grid-template-columns:repeat(3,minmax(0,1fr));}
}
/* Expanded: >=840dp —— 常驻 Rail，取消底部 Tab，双栏 */
@media (min-width:840px){
  .shell{grid-template-columns:200px minmax(0,1fr);}
  .content{max-width:1180px;margin:0 auto;padding:24px;}
  .cards{grid-template-columns:repeat(2,minmax(0,1fr));}
  .topbar{padding:18px 28px;}
  .topbar h1{font-size:22px;}
}
@media print{
  .topbar,.rail,.tabbar,.no-print{display:none !important;}
  .app{padding:0;}
  .shell{display:block;}
  .content{padding:0;max-width:none;}
  body{background:#fff;color:#000;}
  .card,.block,.hero{box-shadow:none;border:1px solid #000;break-inside:avoid;}
  .print-card{border:2px dashed #000;}
  .cards{grid-template-columns:repeat(2,1fr);}
}
</style>
</head>
<body>
<div class="app">
  <header class="topbar no-print">
    <h1>学习助手 App · 界面第一版</h1>
    <span class="sub">静观专注 · 学术克制 ｜ F14 可验收查看器</span>
    <span class="badge">v0.1.0 · 双端响应式</span>
  </header>

  <div class="shell">
    <nav class="rail no-print" aria-label="侧栏导航">
      {{RAIL_ITEMS}}
    </nav>

    <main class="content">
      <section class="hero">
        <h2>建设蓝图落地页</h2>
        <p>按 PRD §5 视觉规范实现：墨蓝 / 琥珀 / 松绿 / 朱砂四色不增不减；绿色只表示可学习空闲时段（方案 A）；手机与 Pad 两端同源响应式；打印态黑白可读。</p>
        <p>首个知识点锚点：人教 A 版·必修第一册·第二章·2.2 <strong>基本不等式</strong>（一正二定三相等）。</p>
      </section>

      <div class="cards">
        {{PAGE_CARDS}}
      </div>

      <section class="block" id="widget-demo">
        <h2>桌面 Widget 最小态契约</h2>
        <p>只显示最近一个任务 + 倒计时 + 一键打开；信息克制，不打开 App 也能用。</p>
        <div class="widget">
          <div class="label">最近任务</div>
          <div class="task">{{WIDGET_TASK}}</div>
          <div class="row">
            <span class="countdown">{{COUNTDOWN}}</span>
            <span class="open">一键打开 ›</span>
          </div>
        </div>
      </section>

      <section class="block" id="semantic-colors">
        <h2>语义色（方案 A）</h2>
        <p>松绿只绑「可学习空闲时段」；达标 / 完成 / ≥75% 改用墨蓝实心 + 对勾或文字，绝不挪作绿色。</p>
        <div class="legend">
          <span class="slot-chip">可学 · 07:00–07:30</span>
          <span class="achieved-chip">✓ 已达标（文字）</span>
          <span class="weak-chip">▲ 薄弱（文字标签）</span>
        </div>
        <p class="mono-note">墨蓝 {{BRAND}} ｜ 琥珀 {{ACTION}} ｜ 松绿 {{PINE}} ｜ 朱砂 {{ALERT}}</p>
      </section>

      <section class="block" id="print-card">
        <h2>考前速查卡 · 屏幕态 / 打印态同源</h2>
        <p>教学区域禁用电子设备，纸质卡是刚需；进考场前可用手机，所以屏幕态同样有效。两态文本一字不差，黑白打印不只靠颜色。</p>
        <div class="print-card">
          <span class="marker">【程度:重】</span>
          等号成立条件｜一正二定三相等，先问等号取不取得到
          <span class="marker"> ▲ 描边 文字标签</span>
        </div>
        <div class="print-card">
          <span class="marker">【程度:中】</span>
          一正二定三相等｜凑积为定值前先确认各项为正
          <span class="marker"> ▲ 描边 文字标签</span>
        </div>
      </section>

      <section class="block no-print" id="breakpoints">
        <h2>双端断点契约（按窗口宽度，不按设备型号）</h2>
        <p>分屏导致窗口宽度回落到 Medium 时自动重组：底部 Tab 取消、NavigationRail 出现、笔记降级为双栏 list-detail。</p>
        <div class="table-wrap">
          <table>
            <thead><tr><th>档位</th><th>示例宽度</th><th>导航</th><th>栏数</th><th>底部 Tab</th><th>笔记形态</th></tr></thead>
            <tbody>{{BREAKPOINT_ROWS}}</tbody>
          </table>
        </div>
      </section>

      <section class="block" id="device-matrix">
        <h2>设备矩阵 · 两台设备各跑一半闭环</h2>
        <div class="device-row">
          <div class="device"><b>vivo S7 · 360dp · Compact</b><br>碎片端：07:00 / 13:00 / 21:30 的 20·30min → 闭环①提醒、倒计时、复习复述、考前速览。笔记「双栏对应」降级为分段切换 + 角标跳转；A 通道降级为一键跳转 Notein + 自动回位。</div>
          <div class="device"><b>Lenovo Y900 13" · Expanded</b><br>整块端：17:20–18:20 的 60min → 闭环②视频、测验、费曼、手写笔记、打印。真双栏：左 AI 笔记 ‖ 右手写，anchorId 双向跳；A 通道系统分屏主战场。</div>
        </div>
      </section>

      <section class="block" id="l0">
        <h2>L0 策略开关（有这个功能，但用不用由我定）</h2>
        <div>{{L0_ITEMS}}</div>
        <p>复习闭环固定模式 2 不可配；笔记显隐只影响渲染，不删除 A/C 归档；默认不把笔记交给 AI。</p>
      </section>

      <section class="block" id="data">
        <h2>数据导入导出 · .studypack</h2>
        <p>纯开放不加密；13 类实体 + manifest（schemaVersion / checksum）；凭证不进包，第三方版权内容只存引用与考纲标签。界面读写的数据可导出并被 F2 导入。</p>
        <div class="stats">{{DATA_SUMMARY}}</div>
        <p class="mono-note">格式：studypack-open-v1 ｜ 本地储存 · 主动 / 手动保存 · 全量可迁移</p>
      </section>

      <div class="footer">学习助手 App · 第一版 v0.1.0 ｜ 业务规则唯一真源 lib/ ｜ 本页为轻量查看器形态</div>
    </main>
  </div>

  <nav class="tabbar no-print" aria-label="底部导航">
    {{TAB_ITEMS}}
  </nav>
</div>
<script>
(function(){
  var links=document.querySelectorAll('[data-page]');
  links.forEach(function(a){
    a.addEventListener('click',function(){
      document.querySelectorAll('.card').forEach(function(c){c.classList.remove('active');});
      document.querySelectorAll('[data-page]').forEach(function(x){x.classList.remove('active');});
      var el=document.getElementById('page-'+a.getAttribute('data-page'));
      if(el){el.classList.add('active');}
      a.classList.add('active');
    });
  });
  var first=document.querySelector('.tab');
  if(first){first.classList.add('active');}
})();
(function(){
  var winW=window.innerWidth;
  var docW=document.documentElement.scrollWidth;
  var overflow=docW>winW+1;
  var boxes=[];
  document.querySelectorAll('.card,.block,.hero,.widget,.device').forEach(function(el){
    var r=el.getBoundingClientRect();
    if(r.right>winW+1){boxes.push(el.id||el.className);}
  });
  var d=document.createElement('div');
  d.id='layout-audit';
  d.setAttribute('data-overflow',overflow?'YES':'NO');
  d.setAttribute('data-doc',String(docW));
  d.setAttribute('data-win',String(winW));
  d.setAttribute('data-boxes',boxes.length?boxes.join('|'):'none');
  d.textContent='LAYOUT_AUDIT overflow='+(overflow?'YES':'NO')+
    ' doc='+docW+' win='+winW+' boxes='+(boxes.length?boxes.join('|'):'none');
  document.body.appendChild(d);
})();
</script>
</body>
</html>
""";
}
