# study-agent

一款**辅助学习 App** 的项目仓库：提醒日常任务、呈现日程，并在发现知识薄弱点后用 AI 陪跑「学习 → 测验 → 费曼复述 → 个性化笔记 → 复习」的完整闭环。以 Android 为主，数据本地存储、可全量导入导出。

当前阶段：**`v2.0.0` 2.x 版已交付** —— 去硬编码学情基线、收纳式知识库、9 个可插拔 AI 模型、手机底栏 / 平板顶栏双形态布局，纯本地无后端。

> **演进**：v0.1.0 是 11 张静态卡片（点了没反应）；v0.2.0 重写为可交互 App 并把「真实点击验收」纳入全量门禁；**v2.0.0 移除全部硬编码场景（深圳中学 / 人教 A 版 / 基本不等式 / 背单词），把学情基线改为用户可配置，新增收纳式知识库与多模型 AI 注册表，重设计双形态布局与日历自定义空闲时段**。F1–F14 的第一版断言一条未删。

- **全量回归**：18 个功能测试文件、**494 用例全绿**（含 tF15 交互门禁，F16 知识库 / F17 多模型为新增）。
- **真实交互验收**：`tools/interaction_check.mjs` 用 CDP 在浏览器里真实点击 / 输入 / 上传 / 勾选，**42 条断言全绿、零静默操作**。详见 [docs/交互验收报告.pdf](docs/交互验收报告.pdf)。
- **正式发布页**：[GitHub Release `v2.0.0`](https://github.com/WFY-1-BYO/study-agent/releases/tag/v2.0.0)。[`v0.2.0`](https://github.com/WFY-1-BYO/study-agent/releases/tag/v0.2.0) / [`v0.1.0`](https://github.com/WFY-1-BYO/study-agent/releases/tag/v0.1.0) 保留为历史版本。
- **建设蓝图**：[docs/产品需求文档_PRD.pdf](docs/产品需求文档_PRD.pdf) · v2.0 · 26 页 A4（§1–§13 第一版地基 + **§14 2.x 增量建设蓝图**）。

主用设备：**vivo S7**（6.44" / 2400×1080 / 20:9 / 408ppi / 60Hz / Android 10）＋ **联想拯救者 Y900 13 英寸**（TB522FU / 约 3840×2560 / 144Hz / Android 16）。

## 文档（**PDF 为主交付格式**，用户端打不开 md）

| 文件 | 内容 |
|---|---|
| **[docs/产品需求文档_PRD.pdf](docs/产品需求文档_PRD.pdf)** | **建设蓝图 · 主交付 · v2.0 · 26 页 A4**：§1–§13 需求基线 / F1–F14 规格与验收 / 双端规范 / 契约 / 门禁 / 追溯矩阵；**§14 2.x 增量建设蓝图**（去硬编码 / 知识库 / 多模型 / 双形态布局 / 14 实体 / 494 用例 + 42 断言）。后续开发与修改以它为准 |
| [docs/产品需求文档_PRD.html](docs/产品需求文档_PRD.html) | PRD 网页版，带侧栏目录、深浅色自适应 |
| [docs/学习助手App_软件框架.pdf](docs/学习助手App_软件框架.pdf) | **需求真源 · 19 页 A4**（第一版）：完整回顾与自查 / 领域模型 / 11 个子系统 / 平台选型 / `.studypack` / 25 条决策台账 / 分工与推进顺序 |
| [docs/双端样式设计_vivoS7与Y900.pdf](docs/双端样式设计_vivoS7与Y900.pdf) | **设备适配真源 · 11 页 A4**（第一版）：断点与导航 / 手机端规格 / Pad 端规格 / A 通道分屏三形态 / 8 屏双端对照 / 分工矩阵 |
| [docs/双端样式对照稿.html](docs/双端样式对照稿.html) | **可视化稿**：手机 360dp 与 Y900 横屏双栏并排，含分屏三形态与色板 |
| [docs/给千问_页面设计交接简报.pdf](docs/给千问_页面设计交接简报.pdf) | 8 页 A4 · 自包含，曾作为设计输入转发给千问 |
| [design/千问_页面结构与画风设计方案.pdf](design/千问_页面结构与画风设计方案.pdf) | **视觉真源**（千问定稿，3 页 / 8 个高保真原型）：tokens / 信息架构 / 组件规范 |
| **[docs/测试报告.pdf](docs/测试报告.pdf)** | 第一版测试报告 · 7 页 A4（v0.1.0）：F0–F14 逐功能结果 / 436 用例汇总 / 渲染校验 / 修复记录 |
| **[docs/交互验收报告.pdf](docs/交互验收报告.pdf)** | **v2.0.0 · 5 页 A4**：真实点击 / 上传验收 42 条断言逐项结果 / 去硬编码 / 多模型 Key 隔离 / 知识库收纳 / AI 失败不伪造 / 双视口 / 如实标注的能力边界 |
| [docs/交互验收报告.html](docs/交互验收报告.html) | 交互验收报告网页版 |
| `docs/*.md` | 各文档源文件（改后跑构建脚本重出 PDF/HTML） |

> **改文档后**：`python3.11 tools/build_docs.py` 一键重出全部 PDF 与网页版；也可只传文件名（如 `python3.11 tools/build_docs.py 交互验收报告.md`）单独构建，避免触碰已定稿 PDF。中文用 Noto CJK 嵌入，PDF 可复制可搜索。

## 代码结构

```
lib/     Dart 领域内核 —— 业务规则唯一真源（零第三方依赖，兼容 Dart 2.17）
         F0 core / F1 models / F2 studypack / F3 storage / F4 preferences
         F5 tasks / F6 slotpool / F7 plans / F8 session / F9 weakpoint
         F10 variants / F11 notes / F12 resources / F13 ai / F14 ui + viewer
         + knowledge_base.dart（F16 收纳式知识库）/ providers.dart（F17 多模型注册表）
test/    每功能测试 tFxx_*.dart（18 个）+ framework.dart + run_all.dart 全量回归
         tF15_interaction.dart 把真实点击验收纳入门禁
         tF16_kb.dart（知识库 26 用例）/ tF17_providers.dart（多模型 13 用例）
web/     index.html —— 交付给用户的【可交互 App】独立真源（2.x，48K，5 导航 tab）
         spec.html  —— F14 静态规格基准页（保留供契约断言，不交付用户）
tools/   build_docs.py / gen_viewer.dart（生成 spec.html）/ browser_check.mjs（渲染校验）
         interaction_check.mjs（CDP 真实点击 / 输入 / 上传 / AI 失败链路验收，42 断言）
android/ Android WebView 容器工程：MainActivity + AiBridge.java（原生 AI 请求桥接）
         把 web/index.html 打进 assets；仅申请 INTERNET 用于用户主动发起的 AI 请求
         versionName 2.0.0 / versionCode 2
.github/ workflow：push 到 main 时由 GitHub Actions 云端编译出 APK
```

**运行与验收**

```bash
dart test/run_all.dart                    # 全量回归，18 文件 / 494 用例（含交互门禁）
dart tools/gen_viewer.dart                # 只生成 web/spec.html，不覆盖交付界面
node tools/browser_check.mjs              # CDP 强制 360/720/1280 真实视口校验并截图
node tools/interaction_check.mjs          # 真实点击 42 条断言，输出 docs/交互验收报告.md
python3.11 tools/build_docs.py 产品需求文档_PRD.md 交互验收报告.md   # 可单独重出指定文档 PDF/HTML
```

## Android 安装包与 AI 设置

**交付件**：`学习助手App_v2.0.0_安装包.apk`（对话交付区）／ Release 附件 `StudyAgent_v2.0.0_debug.apk`。由 `.github/workflows/build-apk.yml` 在 GitHub Actions 云端编译（JDK 17 + AGP 8.1.4 + Gradle 8.0），本地亦可用 Android SDK 编译验证。

- `minSdk 23` / `targetSdk 34`，覆盖 vivo S7 与 Lenovo Y900；debug 签名，可直接安装。
- **首次使用 AI**：打开 App → 「我的」→ 选一个 Provider（DeepSeek / GPT / Claude / Qwen / Kimi / 豆包 / GLM / Gemini / Ollama，共 9 个）→ 编辑 Base URL / Model ID → 填 API Key（每个模型单独存）→「测试连接」。
- Key 只存本机 WebView `localStorage`（键 `studyagent.v2.key.<模型>`），**不进包、不进 state、不进 `.studypack` 导出、不上传**；导出时明确剔除。
- 学情基线在「我的 → 学情基线」填写，或套用 3 个可选预设（深中 / 北京四中 / 空白）；**默认全空，不含任何硬编码场景**。
- APK 内由 `AiBridge` 用 `HttpURLConnection` 真实 POST 再回调 JS，绕开 `file://` 页面的跨域限制；未填 Key / 不可达时**如实报错，绝不伪造 AI 回复**。
- 除 AI 请求外不联网、不上报数据；不申请定位 / 通讯录 / 存储 / 短信权限。
- 原生桌面 Widget 常驻、系统分屏 / Notein 跳转、精确闹钟、原生 Flutter 客户端仍属后续版本。

## 分工

| 环节 | 负责 | 状态 |
|---|---|---|
| 需求与框架定稿 | 本助手 | ✅ v1.0（第一版地基，保留） |
| **页面结构 + 整体画风** | **千问** | ✅ 定稿 |
| **设备适配层（双端样式）** | 本助手 | ✅ v1.0 |
| **PRD 建设蓝图** | 本助手 | ✅ **v2.0**（§14 2.x 增量） |
| 编码实现（第一版 v0.1.0） | 本助手 | ✅ 已完成 · 436 用例全绿（静态界面，已被取代） |
| 可交互界面 + AI 通道（v0.2.0） | 本助手 | ✅ 已完成 · 458 用例全绿 · 39 条真实点击断言全绿 |
| **2.x 去硬编码 / 知识库 / 多模型 / 双形态布局（v2.0.0）** | 本助手 | ✅ 已完成 · **494 用例全绿 · 42 条真实点击断言全绿** |

需求归框架文档，画风归千问定稿，适配归双端样式；**开发与修改统一以 PRD 建设蓝图（v2.0 §14）为准**。

## Git 约定

- **代码**：做成**第一版后 git**（首次提交 + 标记 `v0.1.0`）；**此后每次修改都 `add → commit → push origin main`**，不积压。开发期每个功能测试通过即提交一次，比约定更严格。
- **文档 / PRD / 设计产物**：**只上传最终版**，不做中间提交。PRD 终版已单独上传。
- **凭证不入库**：API key / token 只存本地（Android Keystore 或本地 600 权限文件），既不写进代码，也不写进 `.studypack` 导出包。`.gitignore` 已做兜底。
- 提交信息用简短中文，说明改了什么。

## 质量门禁（不得放宽）

- **每写一个功能，立即测试；全部通过才进入下一个功能**。不删断言、不放宽断言、不跳过失败用例。
- 所有功能完成后跑**全量回归**，`run_all.dart` 全绿之后才交付。
- 界面另做无头浏览器渲染校验（无溢出 / 错位 / 中文方块）。
- **v0.2.0 起新增、v2.0.0 强化**：真实交互验收 `tools/interaction_check.mjs` 由 `test/tF15_interaction.dart` 调用，纳入 `run_all.dart` 门禁——验证每个操作都有可见反馈、去硬编码基线、9 Provider 多模型切换与 Key 隔离、知识库上传 / 截图、日历自定义空闲时段、AI 失败如实报错、Key 不进导出包、14 实体 `.studypack`、APK 内置界面与交付界面逐字节一致。
- 测试留痕于 **[docs/测试报告.pdf](docs/测试报告.pdf)**（v0.1.0，15 文件 / 436 用例）与 **[docs/交互验收报告.pdf](docs/交互验收报告.pdf)**（v2.0.0，42 条真实点击 / 上传断言）。当前全量结论：**18 个功能测试文件 / 494 用例 / 通过 494 / 失败 0 / `ALL_GREEN`**；交互验收 **42 断言 / 0 失败 / `ALL_GREEN`**。

## 关键约束速览

- 数据本地存储，**纯开放不加密**的 `.studypack`（14 实体）保证「所有数据能带走」；`api_key` 排除在包外。
- AI 层可插拔（能力接口固定 + **9 个 Provider 预设**：DeepSeek / GPT / Claude / Qwen / Kimi / 豆包 / GLM / Gemini / Ollama），**Key 按模型单独存本机**；无网无 key 优雅降级，**失败绝不伪造回复**。
- **学情基线用户可配置**（地区 / 学校 / 卷别 / 考试模式 / 教材 / 知识点树，默认空、可选 3 预设）；资料对齐的是**用户设定的基线**而非写死「新高考 I 卷 / 人教 A 版」：来源可追溯、带考纲标签，AI 只做检索匹配 + 讲解 + 基于母题的变式，不凭空造题。
- 「绿色空闲时段」是多来源的 `SlotPool`；**绿色是可学习时段专色，不得挪作「达标/完成」**（与千问 tokens 冲突，PRD 默认按方案 A，待拍板）。教学区域禁用电子设备，速查卡需**屏幕态 + 黑白可打印态**同源双渲染。
- 内置笔记区可显示/不显示；已购 Notein 走分屏 / PDF 桥接，不做内嵌。AI 笔记与我的笔记**分开存**、`anchorId` 本地索引双向关联，默认不交给 AI 处理。
- **75% 是双层**（会话通过线 / 规划目标线）；未达标走「归因 → 继续费曼 → 再测一遍」。复习固定模式 2、不可配。
- **vivo S7 = 碎片端（闭环①）**，**Y900 = 整块端（闭环② + A 通道分屏主战场）**；断点按窗口宽度判断，分屏导致宽度骤降时自动降级。
