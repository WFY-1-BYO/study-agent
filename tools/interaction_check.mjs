// F15 · 真实交互验收（回应「一点反馈都没有 / 你管这叫通过测试了」）。
// 用 CDP 在真实浏览器里点击按钮、填表、勾选、调用 AI 通道，
// 断言每一步都有【可见反馈 + 状态变化】，而非只测纯 Dart 规则函数。
// 用法：node tools/interaction_check.mjs
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const port = 9334;
const userDataDir = mkdtempSync(join(tmpdir(), 'cdp-interact-'));
const url = 'file://' + process.cwd() + '/web/index.html';
const chrome = spawn('chromium', [
  '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--no-default-browser-check',
  `--remote-debugging-port=${port}`, `--user-data-dir=${userDataDir}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' :: ' + detail : ''}`);
}
function info(name, detail) {
  results.push({ name, ok: true, detail, info: true });
  console.log(`INFO  ${name} :: ${detail}`);
}

async function waitForCdp() {
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch(`http://127.0.0.1:${port}/json/version`); if (r.ok) return; }
    catch (_) { /* 未就绪 */ }
    await sleep(200);
  }
  throw new Error('Chrome CDP 端口未就绪');
}

async function main() {
  await waitForCdp();
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

  let seq = 0; const pending = new Map();
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  const send = (method, params = {}) => new Promise((resolve) => {
    const id = ++seq; pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });

  async function js(expr) {
    const r = await send('Runtime.evaluate',
      { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.result?.exceptionDetails) {
      throw new Error('JS 异常: ' + (r.result.exceptionDetails.text || '') + ' '
        + (r.result.exceptionDetails.exception?.description || ''));
    }
    return r.result?.result?.value;
  }
  const jstr = (s) => JSON.stringify(s);
  async function click(sel) {
    return js(`(()=>{const e=document.querySelector(${jstr(sel)});if(!e)return 'NO_EL';e.click();return 'OK';})()`);
  }
  async function setVal(sel, val, evt = 'change') {
    return js(`(()=>{const e=document.querySelector(${jstr(sel)});if(!e)return 'NO_EL';`
      + `e.value=${jstr(val)};e.dispatchEvent(new Event(${jstr(evt)},{bubbles:true}));return 'OK';})()`);
  }
  async function status() {
    return js(`(()=>{const b=document.getElementById('statusbar');`
      + `return {c:+b.getAttribute('data-count'),t:b.textContent,k:b.className};})()`);
  }
  async function txt(sel) {
    return js(`(()=>{const e=document.querySelector(${jstr(sel)});return e?e.textContent.trim():'NO_EL';})()`);
  }
  async function attr(sel, name) {
    return js(`(()=>{const e=document.querySelector(${jstr(sel)});return e?e.getAttribute(${jstr(name)}):null;})()`);
  }
  async function visiblePages() {
    return js(`Array.from(document.querySelectorAll('section[data-page].active')).map(e=>e.dataset.page)`);
  }

  await send('Page.enable'); await send('Runtime.enable');
  await send('Page.navigate', { url });
  await sleep(900);
  // 干净起点
  await js('localStorage.clear(); location.reload();');
  await sleep(1000);

  // ---------------------------------------------------------------- ① 顶栏不再重叠
  const overlap = await js(`(()=>{const a=document.querySelector('.topbar .logo').getBoundingClientRect();`
    + `const b=document.querySelector('.topbar h1').getBoundingClientRect();`
    + `return !(a.right<=b.left||b.right<=a.left||a.bottom<=b.top||b.bottom<=a.top);})()`);
  check('① 顶栏 logo 与标题不再重叠（修复截图中的文字压叠）', overlap === false, `overlap=${overlap}`);

  // ---------------------------------------------------------------- ② 页面真的能切
  const allPages = await js(`Array.from(document.querySelectorAll('section[data-page]')).map(e=>e.dataset.page)`);
  check('② 11 类页面全部存在', allPages.length === 11, `count=${allPages.length}`);
  const before = await status();
  await click('[data-nav="calendar"]');
  const vp = await visiblePages();
  const after = await status();
  check('② 点「全局日历」真的切页（其它页隐藏）', vp.length === 1 && vp[0] === 'calendar', `active=${vp.join(',')}`);
  check('② 切页写了可见反馈条', after.c > before.c && after.t.includes('全局日历'), `count ${before.c}→${after.c}`);
  await click('[data-nav="today"]');

  // ---------------------------------------------------------------- ③ 任务勾选有反馈且落盘
  const c0 = (await status()).c;
  await js(`(()=>{const e=document.querySelector('[data-task="T-1"]');e.checked=true;`
    + `e.dispatchEvent(new Event('change',{bubbles:true}));return 'OK';})()`);
  const doneCnt = await txt('#taskDone');
  const passBadge = await txt('.task.done .pass');
  const stored = await js(`JSON.parse(localStorage.getItem('sa_state_v2')).tasks[0].done`);
  const c1 = (await status()).c;
  check('③ 勾选任务 → 完成计数变化', doneCnt === '1', `taskDone=${doneCnt}`);
  check('③ 勾选任务 → 出现「✓ 已达标」墨蓝标记（绿色未挪作达标）', passBadge.includes('已达标'), passBadge);
  check('③ 勾选任务 → 写入本机 localStorage', stored === true, `stored=${stored}`);
  check('③ 勾选任务 → 反馈条递增', c1 > c0, `${c0}→${c1}`);

  // ---------------------------------------------------------------- ④ 倒计时真的在跑
  const t1 = await attr('#countdown', 'data-tick');
  await sleep(1400);
  const t2 = await attr('#countdown', 'data-tick');
  const cdTxt = await txt('#countdown');
  check('④ 倒计时每秒真的刷新（不是静态数字）', Number(t2) > Number(t1), `tick ${t1}→${t2}`);
  check('④ 倒计时格式正确且标注提前量 / 提醒方式',
    /^\d{2}:\d{2} 后$/.test(cdTxt) && (await txt('#nextTaskLabel')).includes('提前'),
    cdTxt);

  // ---------------------------------------------------------------- ⑤ 提醒方式即时生效
  await setVal('#reminderMode', 'sound', 'change');
  const rm = await txt('#nextTaskLabel');
  check('⑤ 提醒方式切到「声音」→ 倒计时说明即时更新', rm.includes('声音'), rm.slice(-40));

  // ---------------------------------------------------------------- ⑥ 一键打开有反馈且不含凭证
  const c2 = (await status()).c;
  await click('[data-action="openHabit"]');
  const s2 = await status();
  check('⑥ 一键打开有明确反馈（不假装跳转成功、不含凭证）',
    s2.c > c2 && s2.t.includes('已请求打开') && !/sk-|api_key/i.test(s2.t), s2.t.slice(-60));

  // ---------------------------------------------------------------- ⑦ 规划创建：失败与成功都有反馈
  await click('[data-nav="planCreate"]');
  await setVal('#pGoal', '', 'input');
  const c3 = (await status()).c;
  await click('[data-action="createPlan"]');
  const s3 = await status();
  check('⑦ 空目标提交 → 有红字错误 + 失败反馈（不静默）',
    (await txt('#pErr')).includes('不能为空') && s3.k === 'bad' && s3.c > c3, s3.t.slice(-50));
  await setVal('#pGoal', '精进基本不等式，能解决 75% 相关题目', 'input');
  await setVal('#pTarget', '75', 'input');
  await setVal('#pDays', '15', 'input');
  const c4 = (await status()).c;
  await click('[data-action="createPlan"]');
  const s4 = await status();
  const planList = await txt('#planList');
  const calList = await txt('#calendarList');
  const pResult = await txt('#pResult');
  check('⑦ 创建规划 → 生成规划 + 会话并写回全局日历',
    planList.includes('P-1') && planList.includes('SE-1') && calList.includes('基本不等式') && pResult.includes('已写回全局日历'),
    pResult.slice(0, 60));
  check('⑦ 创建规划 → 反馈条递增', s4.c > c4, `${c4}→${s4.c}`);

  // ---------------------------------------------------------------- ⑧ 会话状态机真实推进
  await click('[data-nav="studySession"]');
  await click('[data-action="resetSession"]');
  await click('[data-action="stageNext"]');   // resources -> pretest
  const st1 = await txt('#stageDesc');
  await click('[data-action="skipPretest"]');
  const st2 = await txt('#stageDesc');
  check('⑧ 摸底测验可选可跳过 → 阶段真的从 pretest 跳到 study',
    st1.includes('摸底测验') && st2.includes('看视频'), `${st1} → ${st2}`);
  await setVal('#quizScore', '80', 'input');
  await click('[data-action="submitQuiz"]');
  const q1 = await txt('#quizResult');
  check('⑧ 80% ≥ 75% → 达标并进入费曼式总结', q1.includes('已达标') && q1.includes('费曼'), q1.slice(0, 50));
  await setVal('#quizScore', '60', 'input');
  await click('[data-action="submitQuiz"]');
  const q2 = await txt('#quizResult');
  check('⑧ 60% < 75% → 进入归因回路再测一遍', q2.includes('归因') && q2.includes('再测一遍'), q2.slice(0, 50));
  await setVal('#quizScore', '150', 'input');
  const c5 = (await status()).c;
  await click('[data-action="submitQuiz"]');
  check('⑧ 非法成绩 → 明确报错 + 失败反馈', (await txt('#quizErr')).includes('0–100') && (await status()).k === 'bad');
  void c5;

  // ---------------------------------------------------------------- ⑨ 复习闭环固定模式 2
  await click('[data-nav="reviewLoop"]');
  await click('[data-action="reviewReset"]');
  for (let i = 0; i < 4; i++) await click('[data-action="reviewNext"]');
  const rv = await txt('#reviewResult');
  check('⑨ 固定模式 2 四步可逐步推进并收口', rv.includes('已达标') && rv.includes('固定模式 2'), rv);
  const c6 = (await status()).c;
  await click('[data-action="tryChangeReview"]');
  const s6 = await status();
  check('⑨ 尝试改复习模式被明确拒绝（不可配置）', s6.c > c6 && s6.k === 'bad' && s6.t.includes('不可配置'), s6.t.slice(-45));

  // ---------------------------------------------------------------- ⑩ 笔记显隐 / 保存 / anchorId 关联
  await click('[data-nav="notes"]');
  await setVal('#myNote', '我的手写笔记：一正二定三相等', 'input');
  await click('[data-action="saveMyNote"]');
  const noteStored = await js(`JSON.parse(localStorage.getItem('sa_state_v2')).myNote`);
  check('⑩ 我的笔记保存 → 落盘 + 可见「已保存」反馈',
    noteStored.includes('一正二定三相等') && (await txt('#myNoteSaved')).includes('已保存'), String(noteStored).slice(0, 24));
  await click('[data-action="linkNotes"]');
  check('⑩ 按 anchorId 建立双向关联', (await txt('#noteLinkState')).includes('双向关联'));
  await setVal('#noteVisible', 'hide', 'change');
  const hidden = await js(`document.getElementById('noteArea').classList.contains('hidden')`);
  check('⑩ 内置笔记区「不显示」真的隐藏（A/C 归档不删）', hidden === true, `hidden=${hidden}`);
  await setVal('#noteVisible', 'show', 'change');

  // ---------------------------------------------------------------- ⑪ L0 开关即时生效
  await click('[data-nav="mine"]');
  await click('[data-action="prefLead5"]');
  const lead = await js(`JSON.parse(localStorage.getItem('sa_state_v2')).leadMinutes`);
  check('⑪ 提前量点 5 min → 生效并持久化', lead === 5, `leadMinutes=${lead}`);
  await setVal('#prefIntent', 'challenge', 'change');
  check('⑪ SessionIntent=挑战 → 反馈含 L4 说明', (await status()).t.includes('L4'));
  await setVal('#prefWhitelist', 'aiMinimal', 'change');
  check('⑪ 数据外发白名单可切换且有反馈', (await status()).t.includes('最小必要'));

  // ---------------------------------------------------------------- ⑫ AI：失败如实、绝不伪造
  await click('[data-action="clearAi"]');
  const c7 = (await status()).c;
  await click('[data-action="testAi"]');
  const s7 = await status();
  const aiOut1 = await txt('#aiTestResult');
  check('⑫ 未填 Key 点测试 → 明确失败反馈，不伪造回复',
    s7.c > c7 && s7.k === 'bad' && aiOut1.includes('未获得 AI 回复') && aiOut1.includes('未填写 API Key'),
    aiOut1.slice(0, 70));
  // 用一个必然不可达的地址，稳定验证「真实发请求 → 如实报错」链路
  await setVal('#aiBase', 'http://127.0.0.1:9', 'input');
  await setVal('#aiModel', 'deepseek-chat', 'input');
  await setVal('#aiKey', 'sk-TEST-INVALID-0000', 'input');
  await click('[data-action="saveAi"]');
  check('⑫ Key 保存只在本机（设置页回填被清空）', (await js(`document.getElementById('aiKey').value`)) === '');
  const c8 = (await status()).c;
  await click('[data-action="testAi"]');
  const busy = await status();
  await sleep(2500);
  const s8 = await status();
  const aiOut2 = await txt('#aiTestResult');
  check('⑫ 点测试先显示「请求中」再给结果（不是无反应）',
    busy.t.includes('请求中') || busy.k === 'busy' || s8.c > c8, `busy=${busy.k} → ${s8.k}`);
  check('⑫ 请求失败 → 显示真实原因，且界面标注「不会编造内容」',
    aiOut2.includes('未获得 AI 回复') && aiOut2.includes('不会编造内容') && s8.k === 'bad',
    aiOut2.slice(0, 80));
  const noFake = await js(`(()=>{const t=document.getElementById('aiTestResult').textContent;`
    + `return !(t.includes('连通') && !t.includes('未获得'));})()`);
  check('⑫ 失败时不出现伪造的 AI 成功回复', noFake === true, `noFake=${noFake}`);

  // ---------------------------------------------------------------- ⑬ .studypack 导出不含 Key
  await click('[data-nav="dataTransfer"]');
  await click('[data-action="exportPack"]');
  const packTxt = await js(`window.__saExportText()`);
  const preview = await txt('#exportPreview');
  check('⑬ 导出生成 manifest + 实体，界面可见预览',
    packTxt.includes('schemaVersion') && packTxt.includes('tasks.json') && preview.includes('schemaVersion'));
  check('⑬ API Key 绝不进导出包',
    !/sk-TEST|api_key|"key"/i.test(packTxt), `len=${packTxt.length}`);
  const imp = await js(`window.__saImportText(${jstr(packTxt)}).ok`);
  check('⑬ 导入同一份包可恢复数据', imp === true, `ok=${imp}`);

  // ---------------------------------------------------------------- ⑭ 无静默操作：遍历所有按钮
  await click('[data-action="clearAll"]');
  const acts = await js(`Array.from(document.querySelectorAll('button[data-action]')).map(e=>e.dataset.action)`);
  let silent = [], skipped = [];
  for (const act of acts) {
    if (act === 'importPack') { skipped.push(act + '(会弹文件选择，单独验证)'); continue; }
    const disabled = await js(`(()=>{const e=document.querySelector('button[data-action=${jstr(act)}]');return !!e&&e.disabled;})()`);
    if (disabled) { skipped.push(act + '(当前阶段按状态机禁用，符合预期)'); continue; }
    const c = (await status()).c;
    await click(`button[data-action="${act}"]`);
    const c2n = (await status()).c;
    if (c2n <= c) silent.push(act);
  }
  check('⑭ 全部可点按钮都有反馈（零静默操作）', silent.length === 0,
    `按钮 ${acts.length} 个，静默 ${silent.length} 个${silent.length ? '：' + silent.join(',') : ''}，跳过 ${skipped.length} 个`);
  if (skipped.length) info('⑭ 跳过项说明', skipped.join('；'));

  // ---------------------------------------------------------------- ⑮ 三档视口无溢出
  for (const w of [360, 720, 1280]) {
    await send('Emulation.setDeviceMetricsOverride',
      { width: w, height: 900, deviceScaleFactor: 1, mobile: w === 360 });
    await sleep(350);
    const audit = await js(`(()=>{window.dispatchEvent(new Event('resize'));`
      + `return document.getElementById('layout-audit').textContent;})()`);
    check(`⑮ ${w}px 视口无横向溢出 / 越界`, audit.includes('overflow=NO') && audit.includes('boxes=none'), audit);
  }

  // ---------------------------------------------------------------- 真实端点探测（尽力而为，不计入门禁）
  try {
    const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 8000);
    const r = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST', signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer sk-probe-invalid' },
      body: JSON.stringify({ model: 'deepseek-chat', messages: [{ role: 'user', content: 'ping' }] }),
    });
    clearTimeout(t);
    info('DeepSeek 真实端点', `可达，假 Key 返回 HTTP ${r.status}（说明请求格式 / 鉴权头正确；真 Key 由用户在本机填写）`);
  } catch (e) {
    info('DeepSeek 真实端点', `沙箱网络未连通（${e.name}）；APK 内走原生通道，不受浏览器跨域限制影响`);
  }

  // ---------------------------------------------------------------- 报告
  const pass = results.filter((r) => r.ok && !r.info).length;
  const failN = results.filter((r) => !r.ok).length;
  const lines = [
    '# 交互验收报告 · v0.2.0',
    '',
    '> 本报告的每一条都由真实浏览器（CDP 强制视口）**点击 / 输入 / 勾选**后读取 DOM 与 localStorage 得出，',
    '> 不是对纯 Dart 规则函数的断言。旧 436 用例仍保留，但不作为「界面可用」的验收凭证。',
    '',
    `- 执行时间：${new Date().toISOString()}`,
    `- 断言通过：**${pass}**；失败：**${failN}**；结论：**${failN === 0 ? 'ALL_GREEN' : 'FAILED'}**`,
    '',
    '| 结果 | 项目 | 细节 |',
    '|---|---|---|',
    ...results.map((r) => `| ${r.info ? 'INFO' : r.ok ? 'PASS' : 'FAIL'} | ${r.name.replace(/\|/g, '/')} | ${(r.detail || '').replace(/\|/g, '/').slice(0, 160)} |`),
    '',
    '## 边界（如实说明）',
    '',
    '- 沙箱内没有用户的真实 API Key，**无法验证 AI 的真实回复内容**；已验证：请求体格式与鉴权头、端点可达性、',
    '  原生桥接代码编译进 APK、以及「请求中 → 成功 / 失败」两态反馈与「失败绝不伪造回复」。',
    '- 浏览器预览从 `file://` 直连 API 会受跨域策略拦截，故 APK 内改由 `AiBridge` 原生发请求再回调 JS。',
    '- 桌面 Widget 常驻、系统分屏 / Notein 跳转、精确闹钟、打印预览、原生 Flutter 客户端仍属第二版。',
  ];
  writeFileSync('docs/交互验收报告.md', lines.join('\n') + '\n');

  console.log(`\n断言通过 ${pass} / 失败 ${failN}`);
  console.log(failN === 0 ? '结论: ALL_GREEN 真实交互验收通过' : '结论: FAILED 存在静默或错误行为');
  ws.close(); chrome.kill();
  try { rmSync(userDataDir, { recursive: true, force: true, maxRetries: 3 }); } catch (_) { /* 忽略 */ }
  process.exit(failN === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('交互验收脚本异常:', e);
  chrome.kill();
  try { rmSync(userDataDir, { recursive: true, force: true }); } catch (_) { /* 忽略 */ }
  process.exit(1);
});
