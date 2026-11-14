# study-agent

一款**辅助学习 App** 的项目仓库：提醒日常任务、呈现日程，并在发现知识薄弱点后用 AI 陪跑「学习 → 测验 → 费曼复述 → 个性化笔记 → 复习」的完整闭环。以 Android 为主，数据本地存储、可全量导入导出。

当前阶段：**`v0.2.0` 可交互版已交付**。

> **v0.1.0 的问题已修正**：那一版界面是 11 张静态卡片（`web/index.html` 仅 5 行脚本），点了没有任何反馈；AI 只停在 Dart 内核，APK 连联网权限都没申请，用户 key 建好了也无处可用。436 个用例测的是纯 Dart 规则函数，**一条都没验证「点一下有没有反应」**，因此不构成产品验收。v0.2.0 把交付界面重写为可交互 App，并把「真实点击验收」纳入全量门禁。

- **全量回归**：16 个功能测试文件、**458 用例全绿**（含 tF15 交互门禁）。
- **真实交互验收**：`tools/interaction_check.mjs` 用 CDP 在浏览器里真实点击 / 输入 / 勾选，**39 条断言全绿、零静默操作**。详见 [docs/交互验收报告.pdf](docs/交互验收报告.pdf)。
- **正式发布页**：[GitHub Release `v0.2.0`](https://github.com/WFY-1-BYO/study-agent/releases/tag/v0.2.0)。[`v0.1.0`](https://github.com/WFY-1-BYO/study-agent/releases/tag/v0.1.0) 保留为历史版本。

主用设备：**vivo S7**（6.44" / 2400×1080 / 20:9 / 408ppi / 60Hz / Android 10）＋ **联想拯救者 Y900 13 英寸**（TB522FU / 约 3840×2560 / 144Hz / Android 16）。

## 文档（**PDF 为主交付格式**，用户端打不开 md）

| 文件 | 内容 |
|---|---|
| **[docs/产品需求文档_PRD.pdf](docs/产品需求文档_PRD.pdf)** | **建设蓝图 · 主交付 · 19 页 A4**：需求基线 / 总览 / **F1–F14 功能规格与逐条验收标准** / 界面与双端规范 / `.studypack` 契约 / 质量门禁 / Git 约定 / 追溯矩阵 / 修改流程。后续开发与修改以它为准 |
| [docs/产品需求文档_PRD.html](docs/产品需求文档_PRD.html) | PRD 网页版，带侧栏目录、深浅色自适应 |
| [docs/学习助手App_软件框架.pdf](docs/学习助手App_软件框架.pdf) | **需求真源 · 19 页 A4**：完整回顾与自查 / 领域模型 / 11 个子系统 / 平台选型 / `.studypack` / 25 条决策台账 / 分工与推进顺序 |
| [docs/双端样式设计_vivoS7与Y900.pdf](docs/双端样式设计_vivoS7与Y900.pdf) | **设备适配真源 · 11 页 A4**：断点与导航 / 手机端规格 / Pad 端规格 / A 通道分屏三形态 / 8 屏双端对照 / 分工矩阵 |
| [docs/双端样式对照稿.html](docs/双端样式对照稿.html) | **可视化稿**：手机 360dp 与 Y900 横屏双栏并排，含分屏三形态与色板 |
| [docs/给千问_页面设计交接简报.pdf](docs/给千问_页面设计交接简报.pdf) | 8 页 A4 · 自包含，曾作为设计输入转发给千问 |
| [design/千问_页面结构与画风设计方案.pdf](design/千问_页面结构与画风设计方案.pdf) | **视觉真源**（千问定稿，3 页 / 8 个高保真原型）：tokens / 信息架构 / 组件规范 |
| **[docs/测试报告.pdf](docs/测试报告.pdf)** | 第一版测试报告 · 7 页 A4：F0–F14 逐功能结果 / 436 用例汇总 / 渲染校验 / 修复记录 |
| **[docs/交互验收报告.pdf](docs/交互验收报告.pdf)** | **v0.2.0 · 5 页 A4**：真实点击验收 39 条断言逐项结果 / 零静默操作 / AI 失败不伪造 / 三档视口 / 如实标注的能力边界 |
| [docs/交互验收报告.html](docs/交互验收报告.html) | 交互验收报告网页版 |
| `docs/*.md` | 各文档源文件（改后跑构建脚本重出 PDF/HTML） |

> **改文档后**：`python3.11 tools/build_docs.py` 一键重出全部 PDF 与网页版；也可只传文件名（如 `python3.11 tools/build_docs.py 交互验收报告.md`）单独构建，避免触碰已定稿 PDF。中文用 Noto CJK 嵌入，PDF 可复制可搜索。

## 代码结构

```
lib/     Dart 领域内核 —— 业务规则唯一真源（零第三方依赖，兼容 Dart 2.17）
         F0 core / F1 models / F2 studypack / F3 storage / F4 preferences
         F5 tasks / F6 slotpool / F7 plans / F8 session / F9 weakpoint
         F10 variants / F11 notes / F12 resources / F13 ai / F14 ui + viewer
test/    每功能测试 tFxx_*.dart（16 个）+ framework.dart + run_all.dart 全量回归
         tF15_interaction.dart 把真实点击验收纳入门禁
web/     index.html —— 交付给用户的【可交互 App】独立真源（54K，29 个动作按钮）
         spec.html  —— F14 静态规格基准页（保留供契约断言，不交付用户）
         shot_phone/medium/pad.png —— 三档浏览器渲染留痕
tools/   build_docs.py / gen_viewer.dart（生成 spec.html）/ browser_check.mjs（渲染校验）
         interaction_check.mjs（CDP 真实点击 / 输入 / AI 失败链路验收）
android/ Android WebView 容器工程：MainActivity + AiBridge.java（原生 AI 请求桥接）
         把 web/index.html 打进 assets；仅申请 INTERNET 用于用户主动发起的 AI 请求
.github/ workflow：push 到 main 时由 GitHub Actions 云端编译出 APK
```

**运行与验收**

```bash
dart test/run_all.dart                    # 全量回归，16 文件 / 458 用例（含交互门禁）
dart tools/gen_viewer.dart                # 只生成 web/spec.html，不覆盖交付界面
node tools/browser_check.mjs              # CDP 强制 360/720/1280 真实视口校验并截图
node tools/interaction_check.mjs          # 真实点击 39 条断言，输出 docs/交互验收报告.md
```

## Android 安装包与 AI 设置

**交付件**：`学习助手App_v0.2.0_安装包.apk`（对话交付区）／ Release 附件 `StudyAgent_v0.2.0_debug.apk`。由 `.github/workflows/build-apk.yml` 在 GitHub Actions 云端编译（JDK 17 + AGP 8.1.4 + Gradle 8.0），不依赖本地 Android SDK。

- `minSdk 23` / `targetSdk 34`，覆盖 vivo S7 与 Lenovo Y900；debug 签名，可直接安装。
- **首次使用 AI**：打开 App → 「我的（L0 / AI）」→ 填 Base URL（默认 `https://api.deepseek.com`）、Model ID（默认 `deepseek-chat`，按你控制台显示的型号改）、API Key → 「保存设置」→「测试连接」。
- Key 只存本机 WebView `localStorage`，**不进包、不进 `.studypack` 导出、不上传**；界面数据导出时明确剔除。
- APK 内由 `AiBridge` 用 `HttpURLConnection` 真实 POST 再回调 JS，绕开 `file://` 页面的跨域限制；浏览器预览直连若被跨域拦截会**如实报错，绝不伪造 AI 回复**。
- 除 AI 请求外不联网、不上报数据；不申请定位 / 通讯录 / 存储 / 短信权限。
- 原生桌面 Widget 常驻、系统分屏 / Notein 跳转、精确闹钟、打印预览、原生 Flutter 客户端仍属第二版。

## 分工

| 环节 | 负责 | 状态 |
|---|---|---|
| 需求与框架定稿 | 本助手 | ✅ v1.0 |
| **页面结构 + 整体画风** | **千问** | ✅ 定稿 |
| **设备适配层（双端样式）** | 本助手 | ✅ v1.0 |
| **PRD 建设蓝图** | 本助手 | ✅ v1.0 终版 |
| 编码实现（第一版 v0.1.0） | 本助手 | ✅ 已完成 · 436 用例全绿（静态界面，已被 v0.2.0 取代） |
| **可交互界面 + AI 通道（v0.2.0）** | 本助手 | ✅ 已完成 · 458 用例全绿 · 39 条真实点击断言全绿 |

需求归框架文档，画风归千问定稿，适配归双端样式；**开发与修改统一以 PRD 建设蓝图为准**。

## Git 约定

- **代码**：做成**第一版后 git**（首次提交 + 标记 `v0.1.0`）；**此后每次修改都 `add → commit → push origin main`**，不积压。开发期每个功能测试通过即提交一次，比约定更严格。
- **文档 / PRD / 设计产物**：**只上传最终版**，不做中间提交。PRD 终版已单独上传。
- **凭证不入库**：API key / token 只存本地（Android Keystore 或本地 600 权限文件），既不写进代码，也不写进 `.studypack` 导出包。`.gitignore` 已做兜底。
- 提交信息用简短中文，说明改了什么。

## 质量门禁（不得放宽）

- **每写一个功能，立即测试；全部通过才进入下一个功能**。不删断言、不放宽断言、不跳过失败用例。
- 所有功能完成后跑**全量回归**，`run_all.dart` 全绿之后才交付。
- 界面另做无头浏览器渲染校验（无溢出 / 错位 / 中文方块）。
- **v0.2.0 起新增**：真实交互验收 `tools/interaction_check.mjs` 由 `test/tF15_interaction.dart` 调用，纳入 `run_all.dart` 门禁——验证每个按钮都有可见反馈、AI 失败如实报错、Key 不进导出包、APK 内置界面与交付界面逐字节一致。
- 测试留痕于 **[docs/测试报告.pdf](docs/测试报告.pdf)**（v0.1.0，15 文件 / 436 用例）与 **[docs/交互验收报告.pdf](docs/交互验收报告.pdf)**（v0.2.0，39 条真实点击断言）。当前全量结论：16 个功能测试文件 / 458 用例 / 通过 458 / 失败 0 / `ALL_GREEN`。

## 关键约束速览

- 数据本地存储，**纯开放不加密**的 `.studypack` 保证「所有数据能带走」；`api_key` 排除在包外。
- AI 层可插拔（能力接口固定 + Provider 适配器可换），默认 `https://api.deepseek.com` + `deepseek-chat`（Model ID 可在设置页改）；无网无 key 优雅降级，**失败绝不伪造回复**。
- 资料必须贴切高考（新高考 I 卷 / 人教 A 版）：来源可追溯、带考纲标签，AI 只做检索匹配 + 讲解 + 基于母题的变式，不凭空造题。
- 「绿色空闲时段」是多来源的 `SlotPool`；**绿色是可学习时段专色，不得挪作「达标/完成」**（与千问 tokens 冲突，PRD 默认按方案 A，待拍板）。教学区域禁用电子设备，速查卡需**屏幕态 + 黑白可打印态**同源双渲染。
- 内置笔记区可显示/不显示；已购 Notein 走分屏 / PDF 桥接，不做内嵌。AI 笔记与我的笔记**分开存**、`anchorId` 本地索引双向关联，默认不交给 AI 处理。
- **75% 是双层**（会话通过线 / 规划目标线）；未达标走「归因 → 继续费曼 → 再测一遍」。复习固定模式 2、不可配。
- **vivo S7 = 碎片端（闭环①）**，**Y900 = 整块端（闭环② + A 通道分屏主战场）**；断点按窗口宽度判断，分屏导致宽度骤降时自动降级。
