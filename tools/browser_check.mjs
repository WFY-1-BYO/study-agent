// F14 验收⑥ · 浏览器真实渲染校验。
// 用 Chrome DevTools Protocol 强制真实视口（headless 默认最小 500px 会失真），
// 检查：横向溢出 / 元素越界 / 中文渲染 / 双端截图。
// 用法：node tools/browser_check.mjs
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const port = 9333;
const userDataDir = mkdtempSync(join(tmpdir(), 'cdp-study-'));
const url = 'file://' + process.cwd() + '/web/index.html';

const chrome = spawn('chromium', [
  '--headless=new',
  '--no-sandbox',
  '--disable-gpu',
  '--hide-scrollbars',
  '--no-first-run',
  '--no-default-browser-check',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${userDataDir}`,
  'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForCdp() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (r.ok) return;
    } catch (_) { /* 端口未就绪 */ }
    await sleep(200);
  }
  throw new Error('Chrome CDP 端口未就绪');
}

async function main() {
  await waitForCdp();
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find((t) => t.type === 'page');
  if (!page) throw new Error('未找到 page target');

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = rej;
  });

  let seq = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };
  const send = (method, params = {}) =>
    new Promise((resolve) => {
      const id = ++seq;
      pending.set(id, resolve);
      ws.send(JSON.stringify({ id, method, params }));
    });

  const viewports = [
    { name: 'phone', width: 360, height: 780, mobile: true },
    { name: 'pad', width: 1280, height: 900, mobile: false },
    { name: 'medium', width: 720, height: 900, mobile: false },
  ];

  let failed = false;
  await send('Page.enable');
  await send('Runtime.enable');

  for (const v of viewports) {
    await send('Emulation.setDeviceMetricsOverride', {
      width: v.width,
      height: v.height,
      deviceScaleFactor: 1,
      mobile: v.mobile,
    });
    await send('Page.navigate', { url });
    await sleep(900);

    const auditRes = await send('Runtime.evaluate', {
      expression:
        "(() => { const d=document.getElementById('layout-audit');" +
        " return d ? d.textContent : 'NO_AUDIT'; })()",
      returnByValue: true,
    });
    const audit = auditRes.result?.result?.value ?? 'NO_AUDIT';

    const boundsRes = await send('Runtime.evaluate', {
      expression:
        "(() => { const win=window.innerWidth; const bad=[];" +
        " document.querySelectorAll('.card,.block,.hero,.widget,.device,.topbar,.tabbar,.stat').forEach(el=>{" +
        " const r=el.getBoundingClientRect();" +
        " if(r.right>win+1||r.left<-1) bad.push((el.id||el.className)+'@'+Math.round(r.left)+'-'+Math.round(r.right)); });" +
        " return 'win='+win+' bad='+(bad.length?bad.slice(0,6).join('|'):'none'); })()",
      returnByValue: true,
    });
    const bounds = boundsRes.result?.result?.value ?? 'NO_BOUNDS';

    const cjkRes = await send('Runtime.evaluate', {
      expression:
        "(() => { const el=document.querySelector('.hero h2');" +
        " if(!el) return 'NO_CJK';" +
        " const r=el.getBoundingClientRect();" +
        " return 'cjk='+el.textContent.trim()+' width='+Math.round(r.width)+' font='+getComputedStyle(el).fontFamily; })()",
      returnByValue: true,
    });
    const cjk = cjkRes.result?.result?.value ?? 'NO_CJK';

    const shot = await send('Page.captureScreenshot', {
      format: 'png',
      captureBeyondViewport: false,
    });
    writeFileSync(`web/shot_${v.name}.png`, Buffer.from(shot.result.data, 'base64'));

    const overflow = audit.includes('overflow=YES') || audit === 'NO_AUDIT';
    const outOfBounds = !bounds.includes('bad=none');
    if (overflow || outOfBounds) failed = true;

    console.log(`[${v.name} ${v.width}x${v.height}]`);
    console.log(`  ${audit}`);
    console.log(`  ${bounds}`);
    console.log(`  ${cjk}`);
    console.log(`  screenshot -> web/shot_${v.name}.png`);
    console.log(`  ${overflow || outOfBounds ? 'RED 存在溢出/越界' : 'GREEN 无溢出/越界'}`);
  }

  ws.close();
  chrome.kill();
  // Chrome 退出时可能仍在写 profile 文件，清理失败不应影响渲染结论。
  try {
    rmSync(userDataDir, { recursive: true, force: true, maxRetries: 3 });
  } catch (_) { /* 临时目录残留无关紧要 */ }
  console.log(failed ? '\n结论: FAILED 存在溢出/越界' : '\n结论: ALL_GREEN 三档视口渲染校验通过');
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.error('浏览器校验失败:', e);
  chrome.kill();
  try {
    rmSync(userDataDir, { recursive: true, force: true });
  } catch (_) { /* ignore */ }
  process.exit(1);
});
