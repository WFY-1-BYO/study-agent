#!/usr/bin/env python3.11
"""
文档构建脚本：Markdown → 带封面/目录/页码的 PDF + 网页版 HTML。

用法：
    python3.11 tools/build_docs.py

输入（docs/）：
    学习助手App_软件框架.md
    给千问_页面设计交接简报.md
输出（docs/）：
    学习助手App_软件框架.pdf / .html
    给千问_页面设计交接简报.pdf

说明：
- 中文用 Noto Sans CJK SC 嵌入，PDF 文字可复制、可搜索。
- 两张 ASCII 字符画（框架总览 / 会话状态机）自动替换为结构化表格：
  字符画在「中文全角 + ASCII 等宽」混排下必然错位，表格排版可控且信息不丢。
- 目录页码由 weasyprint 的 target-counter 生成，改文档后无需手工维护。
依赖：markdown, weasyprint, fontconfig(Noto CJK 字体)。
"""
from __future__ import annotations

import html as htmlmod
import re
from pathlib import Path

import markdown
from weasyprint import HTML

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
TMP = Path("/tmp/studyagent-pdfbuild")
TMP.mkdir(exist_ok=True)

# ---------------------------------------------------------------- 字符画 → 表格
ARCH = """
<table class="arch">
<thead><tr><th>层</th><th>内容</th></tr></thead>
<tbody>
<tr><td><strong>L0 策略与开关层</strong>（横切）<br><span class="note">Preferences / Feature Toggles</span></td>
<td>提醒方式 · 开始时机 · 摸底测验 · 笔记显隐 · 数据外发范围<br>提前量(2/5/自定义) · SessionIntent(跟随/挑战/刷自信)</td></tr>
<tr><td><strong>闭环① 任务/习惯维系</strong></td><td>Widget / 今日 / 全局日历</td></tr>
<tr><td><strong>闭环② 能力精进</strong></td><td>发现薄弱 → 建规划 → 会话学习 → 费曼总结 → 复习闭环(模式2) → 达成量化目标<br>
<span class="note">子回路：未达标 → 归因 → 费曼 → 再测；SlotPool 供时段，Session 按容量匹配环节</span></td></tr>
<tr><td><strong>L1 能力层</strong>（可插拔）</td><td>AI 服务层＝能力接口(固定) + Provider 适配器(可换)<br>
资源适配器层＝分屏跳转(A) · 文件桥接(C) · 引用登记 · 本地导入<br>
笔记子系统＝A/C/D 三通道 + 两份独立笔记 + anchorId 关联<br>
高考对齐约束层＝来源 / 考纲标签 / 年份地区 / 题型分值难度<br>
全局时间视图＝Widget(最小) → 今日 → 日历(任务·规划·校历叠加)</td></tr>
<tr><td><strong>L2 数据底座</strong></td><td>本地存储 + 主动/手动保存 + .studypack 全量迁移<br><span class="note">① 纯开放不加密；密钥与第三方版权内容不进包</span></td></tr>
</tbody></table>
"""

FLOW = """
<table class="arch flow">
<thead><tr><th>阶段</th><th>流转</th></tr></thead>
<tbody>
<tr><td>1 资源就绪</td><td>AI 准备资源 → <strong>摸底测验（可选，可跳过）</strong> → 视频学习 + 笔记</td></tr>
<tr><td>2 测验</td><td>相关测验 → 判定达标</td></tr>
<tr><td>3a 达标 → 总结</td><td>我复述 → AI 纠正 → 反复 → 确认理解 → 生成个性化 AI 笔记 → 生成复习计划纳入规划</td></tr>
<tr><td>3b 未达标 → 归因回路</td><td>AI 错因归因（产出 WeakPoint）→ 回到费曼复述-纠正 → <strong>再测一遍</strong> → 回到第 2 步，循环至通过线</td></tr>
<tr><td>4 复习闭环（固定）</td><td>下次学习前：复述上次理解 → AI 纠正 → 反复确认 → 几道简单练手题 → 今日新内容</td></tr>
</tbody></table>
"""


def fix_diagrams(rendered: str) -> str:
    """把封闭框线的字符画换成结构化表格；树形目录（仅 ├──）保持原样。"""
    def sub(m: re.Match) -> str:
        block = m.group(0)
        if "L0 策略与开关层" in block or "闭环①" in block:
            return ARCH
        if "AI 准备资源" in block and ("达标" in block or "归因" in block):
            return FLOW
        return block
    return re.sub(r"<pre><code[\s\S]*?</code></pre>", sub, rendered)


# ---------------------------------------------------------------- 打印样式
PRINT_CSS = r"""
@page { size:A4; margin:19mm 16mm 18mm 16mm;
  @top-left{content:string(doctitle);font-family:"Noto Sans CJK SC";font-size:8pt;color:#8b949e}
  @top-right{content:"v1.0 · 2026-11-14";font-family:"Noto Sans CJK SC";font-size:8pt;color:#8b949e}
  @bottom-left{content:"study-agent · WFY-1-BYO";font-family:"Noto Sans CJK SC";font-size:8pt;color:#8b949e}
  @bottom-right{content:"第 " counter(page) " / " counter(pages) " 页";font-family:"Noto Sans CJK SC";font-size:8pt;color:#8b949e} }
@page :first { @top-left{content:none} @top-right{content:none} @bottom-left{content:none} @bottom-right{content:none} margin:0 }
*{box-sizing:border-box}
body{font-family:"Noto Sans CJK SC","Noto Sans CJK",sans-serif;font-size:10pt;line-height:1.72;color:#1f2328;margin:0}
h1,h2,h3,h4{string-set:doctitle content()}
.cover{page-break-after:always;height:297mm;padding:34mm 24mm 20mm;background:#f6f8fa}
.cover .kicker{font-size:10pt;color:#0969da;letter-spacing:.18em;margin-bottom:12mm}
.cover h1{font-size:30pt;line-height:1.35;border:0;margin:0 0 8mm;padding:0;white-space:pre-line}
.cover .sub{font-size:13pt;color:#57606a;margin-bottom:16mm}
.cover .rule{width:38mm;height:3px;background:#0969da;margin-bottom:16mm}
.cover table{width:100%;border-collapse:collapse;font-size:10pt;margin-bottom:14mm}
.cover td{border:0;border-bottom:1px solid #d8dee4;padding:7px 4px;vertical-align:top}
.cover td:first-child{width:32mm;color:#57606a;font-weight:600}
.cover .foot{position:absolute;bottom:22mm;left:24mm;font-size:9pt;color:#8b949e;line-height:1.9}
.tocpage{page-break-after:always;padding-top:6mm}
.tocpage h2{border:0;font-size:18pt;margin:0 0 10mm;padding:0;color:#0969da}
.toc ul{list-style:none;padding-left:0;margin:0}.toc ul ul{padding-left:7mm}
.toc li{margin:2.1mm 0;font-size:10pt}.toc a{color:#1f2328;text-decoration:none}
.toc a::after{content:leader('.') target-counter(attr(href),page);color:#8b949e}
main h1{display:none}
main>h2{font-size:15pt;margin:9mm 0 4mm;padding-bottom:2.5mm;border-bottom:1.5px solid #0969da;color:#0969da;break-after:avoid}
main>h3{font-size:12pt;margin:7mm 0 3mm;break-after:avoid}
main>h4{font-size:10.5pt;margin:5mm 0 2mm;color:#0969da;break-after:avoid}
p{margin:2.4mm 0;orphans:2;widows:2}
blockquote{margin:3.5mm 0;padding:3mm 4mm;background:#ddf4ff;border-left:3px solid #0969da;border-radius:0 3px 3px 0;break-inside:avoid}
blockquote p{margin:1mm 0}
table{border-collapse:collapse;width:100%;margin:3.5mm 0;font-size:8.6pt}
thead{display:table-header-group}tr{break-inside:avoid}
th,td{border:0.6px solid #d0d7de;padding:2.1mm 2.4mm;text-align:left;vertical-align:top;word-break:break-word}
th{background:#f6f8fa;font-weight:650}tbody tr:nth-child(even) td{background:#fbfcfd}
.note{color:#57606a;font-size:8.4pt}
table.arch th:first-child,table.arch td:first-child{width:42mm}
table.arch td:first-child{background:#f6f8fa;font-weight:600}
code{font-family:"DejaVu Sans Mono",monospace;background:#f6f8fa;border:0.5px solid #d8dee4;border-radius:2px;padding:0 2px;font-size:8.4pt}
pre{background:#f6f8fa;border:0.6px solid #d8dee4;border-radius:4px;padding:3.5mm;margin:3.5mm 0;
    font-family:"DejaVu Sans Mono",monospace;font-size:7.0pt;line-height:1.5;white-space:pre-wrap;overflow:hidden;break-inside:avoid}
pre code{background:none;border:0;padding:0;font-size:inherit;font-family:inherit}
hr{border:0;border-top:0.6px solid #d8dee4;margin:6mm 0}
a{color:#0969da}strong{font-weight:700}ul,ol{padding-left:6mm;margin:2.4mm 0}li{margin:1.2mm 0}
"""

WEB_CSS = """
:root{--bg:#fff;--fg:#1f2328;--muted:#656d76;--line:#d8dee4;--accent:#0969da;--accent-soft:#ddf4ff;--panel:#f6f8fa;--code:#f6f8fa}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8b949e;--line:#30363d;--accent:#58a6ff;--accent-soft:#122b45;--panel:#161b22;--code:#161b22}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;line-height:1.75;font-size:16px}
.wrap{max-width:1080px;margin:0 auto;padding:32px 20px 80px;display:grid;grid-template-columns:250px 1fr;gap:40px}
nav{position:sticky;top:20px;align-self:start;max-height:calc(100vh - 40px);overflow:auto;font-size:13px;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px}
nav h3{margin:0 0 10px;font-size:13px;color:var(--muted);letter-spacing:.05em}
nav ul{list-style:none;padding-left:0;margin:0}nav ul ul{padding-left:14px}nav li{margin:4px 0}
nav a{color:var(--muted);text-decoration:none;display:block;padding:2px 0}nav a:hover{color:var(--accent)}
main{min-width:0}main h1{font-size:30px;line-height:1.35;border-bottom:1px solid var(--line);padding-bottom:14px;margin-top:0}
main h2{font-size:22px;margin-top:44px;border-bottom:1px solid var(--line);padding-bottom:8px}
main h3{font-size:18px;margin-top:30px}main h4{font-size:16px;margin-top:22px;color:var(--accent)}
blockquote{margin:16px 0;padding:12px 16px;background:var(--accent-soft);border-left:4px solid var(--accent);border-radius:0 8px 8px 0}blockquote p{margin:6px 0}
table{border-collapse:collapse;width:100%;margin:16px 0;font-size:14px;display:block;overflow-x:auto}
th,td{border:1px solid var(--line);padding:9px 12px;text-align:left;vertical-align:top}th{background:var(--panel);font-weight:600;white-space:nowrap}
tr:nth-child(even) td{background:color-mix(in srgb,var(--panel) 40%,transparent)}
table.arch td:first-child{background:var(--panel);font-weight:600;min-width:170px}.note{color:var(--muted);font-size:13px}
code{background:var(--code);border:1px solid var(--line);border-radius:5px;padding:1px 5px;font-size:13px;font-family:ui-monospace,Menlo,Consolas,monospace}
pre{background:var(--code);border:1px solid var(--line);border-radius:10px;padding:16px;overflow-x:auto;line-height:1.55;white-space:pre-wrap}
pre code{background:none;border:0;padding:0;font-size:13px}
hr{border:0;border-top:1px solid var(--line);margin:36px 0}a{color:var(--accent)}strong{font-weight:650}ul,ol{padding-left:24px}li{margin:5px 0}
.meta{display:inline-block;background:var(--panel);border:1px solid var(--line);border-radius:20px;padding:4px 12px;font-size:12px;color:var(--muted);margin-bottom:20px}
@media(max-width:820px){.wrap{grid-template-columns:1fr;gap:0}nav{position:static;max-height:none;margin-bottom:24px}body{font-size:15px}}
"""

# ---------------------------------------------------------------- 文档配置
SPECS = [
    dict(
        md="学习助手App_软件框架.md",
        title="学习助手 App\n需求与框架定稿",
        subtitle="两个闭环 · 一个横切层 · 可插拔能力层 · 数据底座",
        meta=[
            ("版本", "v1.0 定稿 · 2026-11-14"),
            ("内容", "完整回顾与自查 / 领域模型 / 11 个子系统 / 平台选型 / .studypack 格式 / 25 条决策台账 / 分工与推进顺序"),
            ("基准", "九轮需求澄清 + 七轮待拍板问题全部收敛"),
            ("学情基线", "广东深圳 · 深圳中学 · 新高考 I 卷 · 人教 A 版 2019"),
            ("仓库", "WFY-1-BYO/study-agent"),
        ],
        foot="本文件为「App 内容」唯一真源。<br>页面结构与画风由千问负责，编码实现由本助手负责。<br>若 §1.6 自查任一条有偏差，纠正后重传最终版。",
        web=True,
    ),
    dict(
        md="给千问_页面设计交接简报.md",
        title="页面结构与画风\n交接简报",
        subtitle="给千问的设计输入 · 自包含，只看本文件即可开工",
        meta=[
            ("版本", "v1.0 · 2026-11-14"),
            ("用途", "可直接转发给千问，作为「页面结构 + 整体画风」设计的输入"),
            ("内容", "App 自包含速览 / 8 条硬约束 / 11 个页面清单 / 画风意见 / 边界声明 / 一句话任务"),
            ("定位", "约束 + 意见 + 草稿；最终设计由千问定稿"),
            ("基准文档", "学习助手App_软件框架.md v1.0（另附 PDF）"),
        ],
        foot="编码实现由本助手按千问定稿承担。<br>三者共用框架文档 v1.0 作为输入基准。",
        web=False,
    ),
]


def render_md(path: Path):
    md = markdown.Markdown(
        extensions=["fenced_code", "tables", "toc", "sane_lists"],
        extension_configs={"toc": {"toc_depth": "2-3"}},
    )
    return fix_diagrams(md.convert(path.read_text(encoding="utf-8"))), md.toc


def build(spec: dict) -> None:
    body, toc = render_md(DOCS / spec["md"])
    rows = "".join(
        f"<tr><td>{htmlmod.escape(k)}</td><td>{v}</td></tr>" for k, v in spec["meta"]
    )
    doc = f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><style>{PRINT_CSS}</style></head><body>
<div class="cover"><div class="kicker">STUDY-AGENT · 需求与框架</div>
<h1>{htmlmod.escape(spec['title'])}</h1><div class="sub">{spec['subtitle']}</div><div class="rule"></div>
<table>{rows}</table><div class="foot">{spec['foot']}</div></div>
<div class="tocpage"><h2>目录</h2><div class="toc">{toc}</div></div>
<main>{body}</main></body></html>"""
    stem = Path(spec["md"]).stem
    tmp = TMP / f"{stem}.html"
    tmp.write_text(doc, encoding="utf-8")
    HTML(filename=str(tmp), base_url=str(DOCS)).write_pdf(str(DOCS / f"{stem}.pdf"))
    print(f"  PDF  -> docs/{stem}.pdf")

    if spec["web"]:
        page = f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>学习助手 App · 需求与框架定稿 v1.0</title><style>{WEB_CSS}</style></head><body><div class="wrap">
<nav><h3>目录</h3>{toc}</nav><main><span class="meta">v1.0 定稿 · 完整回顾 + 七问收口 · 2026-11-14</span>
{body}</main></div></body></html>"""
        (DOCS / f"{stem}.html").write_text(page, encoding="utf-8")
        print(f"  HTML -> docs/{stem}.html")


if __name__ == "__main__":
    for s in SPECS:
        print(f"构建: {s['md']}")
        build(s)
    print("完成。")
