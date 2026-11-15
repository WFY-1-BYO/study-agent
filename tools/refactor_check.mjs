// 2.x 重构验收 · 逐功能真实浏览器（CDP）点击 / 输入 / 重启 / 视口切换断言。
// 用法：
//   node tools/refactor_check.mjs                     # 全部功能组
//   node tools/refactor_check.mjs --group=P0A        # 只跑某一功能组（开发期门禁）
// 每组启动独立浏览器与独立用户数据目录，互不污染；ALL_GREEN 才算通过。
import { spawn } from 'node:child_process';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const URL_APP = 'file://' + join(ROOT, 'web', 'index.html').replace(/\\/g, '/');
const BROWSER = process.env.SA_BROWSER || 'chromium';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok: !!ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ' :: ' + detail : ''}`);
}

class Session {
  constructor(port, profile) {
    this.port = port;
    this.profile = profile;
    this.chrome = null;
    this.ws = null;
    this.seq = 0;
    this.pending = new Map();
  }
  async start() {
    this.chrome = spawn(BROWSER, [
      '--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars',
      '--no-first-run', '--no-default-browser-check',
      `--remote-debugging-port=${this.port}`, `--user-data-dir=${this.profile}`, 'about:blank',
    ], { stdio: 'ignore' });
    for (let i = 0; i < 60; i++) {
      try { const r = await fetch(`http://127.0.0.1:${this.port}/json/version`); if (r.ok) break; }
      catch (_) { /* 未就绪 */ }
      await sleep(200);
    }
    const targets = await (await fetch(`http://127.0.0.1:${this.port}/json/list`)).json();
    const page = targets.find((t) => t.type === 'page');
    this.ws = new WebSocket(page.webSocketDebuggerUrl);
    await new Promise((res, rej) => { this.ws.onopen = res; this.ws.onerror = rej; });
    this.ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id && this.pending.has(m.id)) { this.pending.get(m.id)(m); this.pending.delete(m.id); }
    };
    this.send('Page.enable'); this.send('Runtime.enable'); this.send('DOM.enable');
    await this.send('Page.enable'); await this.send('Runtime.enable'); await this.send('DOM.enable');
    await this.send('Page.navigate', { url: URL_APP });
    await sleep(1000);
    // 让 prompt 不阻塞真实流程（与冻结验收一致）
    await this.js(`window.prompt=function(m){m=m||'';
      if(m.indexOf('提醒语')>=0)return '一正二定三相等，先问等号取不取得到';
      if(m.indexOf('考点')>=0)return '基本不等式';
      if(m.indexOf('知识点')>=0)return '基本不等式';
      if(m.indexOf('题干')>=0||m.indexOf('公式')>=0)return '测试母题题干';
      return '测试';};`);
    return this;
  }
  send(method, params = {}) {
    return new Promise((resolve) => {
      const id = ++this.seq; this.pending.set(id, resolve);
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async js(expr) {
    const r = await this.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.result?.exceptionDetails) {
      throw new Error('JS 异常: ' + (r.result.exceptionDetails.text || '') + ' '
        + (r.result.exceptionDetails.exception?.description || ''));
    }
    return r.result?.result?.value;
  }
  async click(sel) {
    return this.js(`(()=>{const e=document.querySelector(${JSON.stringify(sel)});if(!e)return 'NO_EL';e.click();return 'OK';})()`);
  }
  async clickByOnclick(sub) {
    return this.js(`(()=>{const bs=document.querySelectorAll('button');for(const b of bs){const o=b.getAttribute('onclick')||'';if(o.includes(${JSON.stringify(sub)})){b.click();return 'OK';}}return 'NO_BTN';})()`);
  }
  async setVal(sel, val, evt = 'input') {
    return this.js(`(()=>{const e=document.querySelector(${JSON.stringify(sel)});if(!e)return 'NO_EL';`
      + `e.value=${JSON.stringify(val)};e.dispatchEvent(new Event(${JSON.stringify(evt)},{bubbles:true}));return 'OK';})()`);
  }
  async viewport(w, h) {
    await this.send('Emulation.setDeviceMetricsOverride',
      { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    await sleep(220);
  }
  async reload() {
    await this.send('Page.navigate', { url: URL_APP });
    await sleep(1000);
  }
  async setFileInput(sel, filePath) {
    const domDoc = await this.send('DOM.getDocument', { depth: -1 });
    const node = await this.send('DOM.querySelector', { nodeId: domDoc.result.root.nodeId, selector: sel });
    if (!node.result || node.result.nodeId == null) return 'NO_EL';
    await this.send('DOM.setFileInputFiles', { nodeId: node.result.nodeId, files: [filePath] });
    return this.js(`(()=>{const e=document.querySelector(${JSON.stringify(sel)});if(!e)return 'NO_EL';e.dispatchEvent(new Event('change',{bubbles:true}));return 'OK';})()`);
  }
  stop() {
    try { this.ws && this.ws.close(); } catch (_) { /* ignore */ }
    try { this.chrome && this.chrome.kill(); } catch (_) { /* ignore */ }
  }
}

async function freshSession(tag) {
  const profile = mkdtempSync(join(tmpdir(), 'sa-refactor-' + tag + '-'));
  const port = 9400 + Math.floor(Math.random() * 400);
  const s = new Session(port, profile);
  await s.start();
  return { s, profile };
}
async function endSession(h) {
  h.s.stop();
  await sleep(250);
  try { rmSync(h.profile, { recursive: true, force: true, maxRetries: 3 }); } catch (_) { /* ignore */ }
}

/* ============================== 各功能组 ============================== */
const GROUPS = {};

// P0-A · IndexedDB 持久化 / 即时自动保存 / 杀进程重开
GROUPS.P0A = async () => {
  const h = await freshSession('p0a');
  const s = h.s;
  const st = (e) => s.js(`(()=>{try{return (${e});}catch(err){return null;}})()`);
  check('P0A① 环境支持 IndexedDB（状态真源 studyagent.db / state/main）',
    await st(`typeof indexedDB!=='undefined'`) === true, '环境支持 IndexedDB');
  // 逐次增删改都应立即触发落盘
  await s.click('#nav-plan'); await s.click('#btn-new-plan');
  await s.setVal('#pGoal', '重启后仍在的规划', 'input');
  await s.click('#btn-save-plan'); await sleep(200);
  const c1 = await st(`window.__saSaveCount||0`);
  await s.click('#nav-kb'); await s.click('#btn-new-notebook');
  await s.setVal('#nbTitle', '数学');
  await s.click('#btn-save-notebook'); await sleep(200);
  const c2 = await st(`window.__saSaveCount||0`);
  await s.click('#nav-calendar'); await s.click('#btn-add-slot');
  await s.click('#btn-save-slot'); await sleep(200);
  const c3 = await st(`window.__saSaveCount||0`);
  check('P0A② 每次增删改立即触发自动保存（保存次数递增）',
    c3 > c2 && c2 > c1, `counts=${c1},${c2},${c3}`);
  check('P0A③ 三类数据均写入当前状态',
    await st(`S.plans.length`) === 1 && await st(`S.knowledgeBase.notebooks.length`) === 1
      && await st(`S.slots.length`) === 1,
    `plans=${await st('S.plans.length')} nb=${await st('S.knowledgeBase.notebooks.length')} slots=${await st('S.slots.length')}`);
  const idbHas = await s.js(`(async()=>{const d=await new Promise((res,rej)=>{const r=indexedDB.open('studyagent.db',1);r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error);});return await new Promise(res=>{const q=d.transaction('state','readonly').objectStore('state').get('main');q.onsuccess=()=>res(!!q.result);q.onerror=()=>res(false);});})()`);
  check('P0A④ IDB 的 state/main 确实有快照', idbHas === true, `idbHas=${idbHas}`);
  check('P0A④b 落盘通道标记为 indexeddb（不是内存 / 临时缓存）',
    await s.js(`document.documentElement.getAttribute('data-store')`) === 'indexeddb',
    `store=${await s.js(`document.documentElement.getAttribute('data-store')`)}`);
  check('P0A⑤ 不再把整份状态明文塞进 localStorage',
    await s.js(`localStorage.getItem('studyagent.v2.state')`) === null,
    'localStorage 无 state 明文');
  // 真·杀进程重开：关闭浏览器，用同一 user-data-dir 重新拉起
  s.stop(); await sleep(600);
  const s2 = new Session(h.s.port, h.profile);
  await s2.start();
  await sleep(400);
  const st2 = (e) => s2.js(`(()=>{try{return (${e});}catch(err){return null;}})()`);
  check('P0A⑥ 杀掉 App 重开：规划 / 笔记本 / 时段完整无丢失',
    await st2('S.plans.length') === 1 &&
    await st2('S.knowledgeBase.notebooks.length') === 1 &&
    await st2('S.slots.length') === 1 &&
    await st2('S.plans[0].goal') === '重启后仍在的规划',
    `plans=${await st2('S.plans.length')} nb=${await st2('S.knowledgeBase.notebooks.length')} slots=${await st2('S.slots.length')}`);
  // Key：本机加密 + 不进 state / 导出
  await s2.click('#nav-mine');
  await s2.clickByOnclick("editProvider('deepseek')");
  await s2.setVal('#pvKey', 'sk-REFACTOR-P0A-KEY');
  await s2.click('#btn-save-provider'); await sleep(300);
  const enc = await s2.js(`(async()=>{try{return await idbGet('secrets','deepseek');}catch(e){return 'ERR:'+e.message;}})()`);
  check('P0A⑦ API Key 在本机密钥区以密文保存（非明文）',
    typeof enc === 'string' && enc.length > 20 && !enc.includes('sk-REFACTOR-P0A-KEY'),
    `cipherLen=${typeof enc === 'string' ? enc.length : 0}`);
  check('P0A⑧ Key 不进入业务状态 S',
    !(await s2.js(`JSON.stringify(S)`)).includes('sk-REFACTOR-P0A-KEY'), 'S 无 Key');
  check('P0A⑨ 读取接口仍可取到明文 Key 供 AI 使用',
    await s2.js(`hasKey()`) === true && await s2.js(`aiCfg().key`) === 'sk-REFACTOR-P0A-KEY',
    'aiCfg 可用');
  s2.stop(); await sleep(250);
  try { rmSync(h.profile, { recursive: true, force: true, maxRetries: 3 }); } catch (_) { /* ignore */ }
};

// P0-B · 弹层层级 / 新建表单页跳转 / 不卡死
GROUPS.P0B = async () => {
  const h = await freshSession('p0b'); const s = h.s;
  const layer = () => s.js(`(()=>{const m=document.getElementById('saMask'),d=document.querySelector('.nav-bottom');
    if(!m||!d)return null;const r=m.getBoundingClientRect();
    const at=document.elementFromPoint(Math.min(innerWidth-2,r.left+r.width/2),Math.min(innerHeight-2,r.top+r.height/2));
    return {maskZ:parseInt(getComputedStyle(m).zIndex||'0'),dockZ:parseInt(getComputedStyle(d).zIndex||'0'),
      hitInMask:!!(at&&at.closest&&at.closest('#saMask')),maskFixed:getComputedStyle(m).position};})()`);
  for (const [name, nav, btn, field] of [
    ['新建学习规划', '#nav-plan', '#btn-new-plan', '#pGoal'],
    ['新建笔记本', '#nav-kb', '#btn-new-notebook', '#nbTitle'],
    ['自定义添加空闲时段', '#nav-calendar', '#btn-add-slot', '#sStart'],
  ]) {
    await s.click(nav); await s.click(btn); await sleep(160);
    const L = await layer();
    check(`P0B① ${name}：弹层 z-index 高于底部 Dock 且置顶不被遮挡`,
      !!L && L.maskZ >= 9999 && L.maskZ > L.dockZ && L.hitInMask && L.maskFixed === 'fixed',
      JSON.stringify(L));
    check(`P0B② ${name}：正常进入对应创建表单页`,
      await s.js(`!!document.getElementById(${JSON.stringify(field.slice(1))})`) === true,
      `field=${field}`);
    const t0 = Date.now();
    const alive = await s.js('1+1');
    check(`P0B③ ${name}：页面未卡死（JS 立即响应）`,
      alive === 2 && Date.now() - t0 < 2000, `alive=${alive} ms=${Date.now() - t0}`);
    await s.click('.form-head .btn'); await sleep(120);
    check(`P0B④ ${name}：返回后弹层关闭、页面可继续操作`,
      await s.js(`!document.getElementById('saMask')`) === true, 'closed');
  }
  await endSession(h);
};

// P0-C · 全局禁用网页默认交互
GROUPS.P0C = async () => {
  const h = await freshSession('p0c'); const s = h.s;
  const css = await s.js(`(()=>{const b=getComputedStyle(document.body);
    const card=document.querySelector('.card')||document.body;
    return {sel:b.userSelect||b.webkitUserSelect,callout:b.webkitTouchCallout,
      cardSel:getComputedStyle(card).userSelect||getComputedStyle(card).webkitUserSelect};})()`);
  check('P0C① 全局 user-select:none（body 与卡片均不可选中）',
    String(css.sel).includes('none') && String(css.cardSel).includes('none'), JSON.stringify(css));
  // 桌面 Chromium 会丢弃不认识的 -webkit-touch-callout，故直接校验交付样式源码（真机 WebView 会生效）
  const cssText = await s.js(`document.querySelector('style').textContent`);
  const starRule = /\*[^{]*\{[^}]*\-webkit\-touch\-callout\s*:\s*none[^}]*\}/.test(cssText);
  const textRule = /input[^{]*\{[^}]*\-webkit\-touch\-callout\s*:\s*default[^}]*\}/.test(cssText);
  check('P0C② 全局 -webkit-touch-callout:none，且输入框例外为 default',
    starRule && textRule, `star=${starRule} input=${textRule}`);
  await s.click('#nav-plan'); await s.click('#btn-new-plan'); await sleep(150);
  const inp = await s.js(`(()=>{const i=document.getElementById('pGoal');
    return i?{sel:getComputedStyle(i).userSelect||getComputedStyle(i).webkitUserSelect,callout:getComputedStyle(i).webkitTouchCallout}:null;})()`);
  check('P0C③ 文本输入框例外：允许选择与光标',
    !!inp && (String(inp.sel).includes('text') || String(inp.sel).includes('auto')), JSON.stringify(inp));
  const ctx = await s.js(`(()=>{
    const card=document.querySelector('.wsec')||document.body;
    const ev1=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});card.dispatchEvent(ev1);
    const i=document.getElementById('pGoal');
    const ev2=new MouseEvent('contextmenu',{bubbles:true,cancelable:true});i.dispatchEvent(ev2);
    const ev3=new Event('selectstart',{bubbles:true,cancelable:true});card.dispatchEvent(ev3);
    return {cardCtx:ev1.defaultPrevented,inputCtx:ev2.defaultPrevented,cardSel:ev3.defaultPrevented};})()`);
  check('P0C④ 长按非输入区：contextmenu / selectstart 均被拦截',
    ctx.cardCtx === true && ctx.cardSel === true, JSON.stringify(ctx));
  check('P0C⑤ 输入框内 contextmenu 不被拦截（可复制粘贴）',
    ctx.inputCtx === false, JSON.stringify(ctx));
  await endSession(h);
};

// P1 · 单包双端全屏自适应
GROUPS.P1 = async () => {
  const h = await freshSession('p1'); const s = h.s;
  const shell = await s.js(`(()=>({stage:!!document.getElementById('stage'),
    deviceClass:document.getElementById('device').className,
    w:document.getElementById('device').getBoundingClientRect().width,iw:innerWidth,
    h:document.getElementById('device').getBoundingClientRect().height,ih:innerHeight}))()`);
  check('P1① 彻底移除手机外框套壳，根容器全屏铺满',
    !shell.stage && !/device (phone|pad)/.test(shell.deviceClass) &&
    Math.abs(shell.w - shell.iw) <= 1 && Math.abs(shell.h - shell.ih) <= 1,
    JSON.stringify(shell));
  const layout = (w, hh) => s.viewport(w, hh).then(() => s.js(`(()=>{
    const t=document.querySelector('.nav-top'),b=document.querySelector('.nav-bottom'),
      side=document.querySelector('.pane-side'),rail=document.querySelector('.pane-rail'),
      p=document.getElementById('page'),de=document.documentElement;
    return {top:getComputedStyle(t).display,bottom:getComputedStyle(b).display,
      side:getComputedStyle(side).display,rail:getComputedStyle(rail).display,
      force:document.documentElement.getAttribute('data-force'),
      noOverflow:p.scrollWidth<=p.clientWidth+1&&de.scrollWidth<=de.clientWidth+1,
      cols:getComputedStyle(p).gridTemplateColumns};})()`));
  const compact = await layout(390, 780);
  check('P1② Compact(<600dp)：底部 5 Tab、单栏、无横向溢出',
    compact.bottom === 'flex' && compact.top === 'none' && compact.side === 'none'
      && compact.noOverflow && !compact.force, JSON.stringify(compact));
  const medium = await layout(760, 900);
  check('P1③ Medium(600–839dp)：顶部导航、双栏、无横向溢出',
    medium.top === 'flex' && medium.bottom === 'none' && medium.side === 'block'
      && medium.noOverflow, JSON.stringify(medium));
  const expanded = await layout(1400, 900);
  check('P1④ Expanded(≥840dp)：顶部导航 + 三栏（左侧列表 / 主内容 / 详情）',
    expanded.top === 'flex' && expanded.bottom === 'none' && expanded.side === 'block'
      && expanded.rail === 'block' && expanded.cols.split(' ').length >= 3 && expanded.noOverflow,
    JSON.stringify(expanded));
  const rotated = await layout(600, 1000);
  check('P1⑤ 横竖屏 / 分屏切换自动重排，无横向溢出',
    rotated.noOverflow && rotated.top === 'flex', JSON.stringify(rotated));
  await s.viewport(390, 780);
  const navCount = await s.js(`document.querySelectorAll('.nav-bottom button').length`);
  check('P1⑥ 手机端底部导航为 5 个 Tab',
    navCount === 5, `count=${navCount}`);
  await endSession(h);
};

// P2-A · AI 模型设置子页 / Key 隔离
GROUPS.P2A = async () => {
  const h = await freshSession('p2a'); const s = h.s;
  await s.click('#nav-mine');
  check('P2A① 「我的」页有 AI 模型设置子页入口',
    await s.js(`!!document.getElementById('btn-open-ai-settings')`) === true, 'entry');
  await s.click('#btn-open-ai-settings'); await sleep(180);
  check('P2A② 进入 AI 模型设置子页（模型下拉 + Key 输入框）',
    await s.js(`currentPage`) === 'aiSettings' &&
    await s.js(`!!document.getElementById('aiProvSel')`) === true &&
    await s.js(`!!document.getElementById('pvKey')`) === true,
    `page=${await s.js('currentPage')}`);
  const n = await s.js(`document.querySelectorAll('#aiProvSel option').length`);
  check('P2A③ 9 个大模型商可选', n === 9, `count=${n}`);
  await s.setVal('#pvKey', 'sk-REFACTOR-P2A');
  await s.click('#btn-save-provider'); await sleep(300);
  check('P2A④ 保存 Key 后可正常使用',
    await s.js(`hasKey()`) === true && await s.js(`aiCfg().key`) === 'sk-REFACTOR-P2A', 'aiCfg 可用');
  check('P2A⑤ Key 不进入业务 state',
    !(await s.js(`JSON.stringify(S)`)).includes('sk-REFACTOR-P2A'), 'S 无 Key');
  await s.js(`(()=>{window.__exportText=null;const OB=window.Blob;
    window.Blob=function(parts,opts){try{window.__exportText=String(parts[0]);}catch(e){}return new OB(parts,opts);};
    URL.createObjectURL=function(){return 'blob:fake';};HTMLAnchorElement.prototype.click=function(){};})()`);
  await s.click('#nav-mine'); await s.click('#btn-export'); await sleep(200);
  const pack = await s.js(`window.__exportText||''`);
  check('P2A⑥ 导出包内不含 Key', !pack.includes('sk-REFACTOR-P2A') && pack.length > 100,
    `len=${pack.length}`);
  await endSession(h);
};

// P2-B · 首启学情基线引导
GROUPS.P2B = async () => {
  const h = await freshSession('p2b'); const s = h.s;
  const ob = await s.js(`(()=>{const m=document.getElementById('onboardMask');
    return m?{visible:getComputedStyle(m).display!=='none',
      fields:['obRegion','obSchool','obPaper','obBook','obMode'].filter(id=>!!document.getElementById(id)).length,
      skip:!!document.getElementById('btn-onboard-skip'),
      save:!!document.getElementById('btn-onboard-save')}:null;})()`);
  check('P2B① 首启（无本地数据）弹出学情基线引导页',
    !!ob && ob.visible && ob.fields === 5 && ob.skip && ob.save, JSON.stringify(ob));
  await s.setVal('#obRegion', '广东深圳'); await s.setVal('#obSchool', '某中学');
  await s.setVal('#obPaper', '新高考 I 卷'); await s.setVal('#obBook', '人教 A 版 2019');
  await s.setVal('#obMode', '3+1+2');
  await s.click('#btn-onboard-save'); await sleep(250);
  check('P2B② 填写并保存 → 基线落盘且引导关闭',
    await s.js(`S.profile.region`) === '广东深圳' &&
    await s.js(`S.profile.textbook`) === '人教 A 版 2019' &&
    await s.js(`!document.getElementById('onboardMask')`) === true,
    JSON.stringify(await s.js(`S.profile`)));
  await s.reload();
  check('P2B③ 重开不再重复弹引导，数据仍在',
    await s.js(`!document.getElementById('onboardMask')`) === true &&
    await s.js(`S.profile.region`) === '广东深圳',
    `region=${await s.js('S.profile.region')}`);
  await s.click('#nav-mine');
  check('P2B④ 「我的」仍保留学情基线入口（稍后可补填）',
    await s.js(`!!Array.from(document.querySelectorAll('button')).find(b=>(b.getAttribute('onclick')||'').includes('openProfile()'))`) === true,
    'entry');
  await endSession(h);
  // 跳过路径：全新安装后可直接跳过
  const h2 = await freshSession('p2bskip'); const s2 = h2.s;
  await s2.click('#btn-onboard-skip'); await sleep(200);
  check('P2B⑤ 「跳过 / 稍后」可用且保留后续入口',
    await s2.js(`!document.getElementById('onboardMask')`) === true &&
    await s2.js(`S.onboarded`) === true &&
    await s2.js(`S.profile.region`) === '', 'skipped');
  await endSession(h2);
};

// P3 · .studypack 导出导入 / WebDAV 预留
GROUPS.P3 = async () => {
  const h = await freshSession('p3'); const s = h.s;
  await s.click('#nav-plan'); await s.click('#btn-new-plan');
  await s.setVal('#pGoal', '导出导入闭环规划'); await s.click('#btn-save-plan'); await sleep(180);
  await s.js(`(()=>{window.__exportText=null;const OB=window.Blob;
    window.Blob=function(parts,opts){try{window.__exportText=String(parts[0]);}catch(e){}return new OB(parts,opts);};
    URL.createObjectURL=function(){return 'blob:fake';};HTMLAnchorElement.prototype.click=function(){};})()`);
  await s.click('#nav-mine'); await s.click('#btn-export'); await sleep(200);
  const pack = await s.js(`window.__exportText||''`);
  let parsed = null; try { parsed = JSON.parse(pack); } catch (_) { /* ignore */ }
  check('P3① 导出 14 类实体 + manifest 校验和',
    !!parsed && Object.keys(parsed.entities).length === 14 &&
    !!parsed.manifest.checksum && parsed.manifest.format === 'studypack-open-v1',
    `entities=${parsed ? Object.keys(parsed.entities).length : 0}`);
  check('P3② 导出包含新增 knowledge_base.json',
    !!parsed && !!parsed.entities['knowledge_base.json'], 'kb');
  // 导入：制造一个改动过的包
  const imp = JSON.parse(pack); imp.entities['plans.json'][0].goal = '导入恢复的规划';
  imp.manifest.checksum = await s.js(`checksum(${JSON.stringify(imp.entities)})`);
  const tmp = join(h.profile, 'restore.studypack.json');
  writeFileSync(tmp, JSON.stringify(imp));
  await s.js(`S.plans[0].goal='临时覆盖';`);
  await s.setFileInput('#impIn', tmp); await sleep(300);
  check('P3③ 导入 .studypack 可完整恢复数据',
    await s.js(`S.plans[0].goal`) === '导入恢复的规划',
    `goal=${await s.js('S.plans[0].goal')}`);
  const bad = JSON.parse(pack); bad.entities['api_key.json'] = [{ api_key: 'sk-SHOULD-REFUSE' }];
  const tmp2 = join(h.profile, 'bad.studypack.json');
  writeFileSync(tmp2, JSON.stringify(bad));
  await s.setFileInput('#impIn', tmp2); await sleep(250);
  check('P3④ 含凭证字段的包被明确拒绝',
    (await s.js(`document.getElementById('feedback').textContent`)).includes('凭证') ||
    (await s.js(`document.getElementById('feedback').textContent`)).includes('拒绝'),
    `fb=${await s.js(`document.getElementById('feedback').textContent`)}`);
  await s.click('#btn-open-data'); await sleep(180);
  check('P3⑤ WebDAV 同步子页（地址 / 账号 / 应用密码 / 上传 / 下载）齐备',
    await s.js(`['davUrl','davUser','davPass','btn-dav-upload','btn-dav-download'].every(id=>!!document.getElementById(id))`) === true,
    'ui');
  check('P3⑥ WebDAV 配置与密码不进业务 state（不进导出包）',
    !(await s.js(`JSON.stringify(S)`)).includes('dav.jianguoyun.com') &&
    !pack.includes('davPass'), 'isolated');
  await s.click('#btn-dav-upload'); await sleep(180);
  check('P3⑦ 未启用同步时如实反馈，不假装成功',
    (await s.js(`document.getElementById('davOut').textContent`)).includes('未启用'),
    `out=${await s.js(`document.getElementById('davOut').textContent`)}`);
  await endSession(h);
};

// P4-A · 新建规划完整向导（含日历式选时段 / 自定义时段 / 薄弱点 / 学情基线）
GROUPS.P4A = async () => {
  const h = await freshSession('p4a'); const s = h.s;
  await s.click('#nav-plan'); await s.click('#btn-new-plan'); await sleep(180);
  check('P4A① 向导 5 步齐全（目标·基线 / 指标·时限 / 选时段 / 薄弱点·开始 / 确认）',
    await s.js(`document.querySelectorAll('.wsteps button').length`) === 5 &&
    await s.js(`document.querySelectorAll('.wsec').length`) === 5,
    `steps=${await s.js(`document.querySelectorAll('.wsteps button').length`)}`);
  check('P4A② 向导内含学情基线（地区 / 学校 / 卷别 / 教材 / 考试模式）',
    await s.js(`['pRegion','pSchool','pPaper','pBook','pMode'].every(id=>!!document.getElementById(id))`) === true,
    'baseline fields');
  await s.click('#btn-save-plan'); await sleep(160);
  check('P4A③ 空目标 → 页面内红字提示，不创建、不卡死',
    await s.js(`document.getElementById('err-pGoal').classList.contains('show')`) === true &&
    (await s.js(`document.getElementById('feedback').textContent`)).includes('目标') &&
    await s.js(`S.plans.length`) === 0,
    `err=${await s.js(`document.getElementById('err-pGoal').textContent`)}`);
  await s.setVal('#pGoal', '两周内掌握某考点');
  await s.setVal('#pQuant', '0'); await s.click('#btn-save-plan'); await sleep(150);
  check('P4A④ 指标非法 → 页内红字校验',
    await s.js(`document.getElementById('err-pQuant').classList.contains('show')`) === true &&
    await s.js(`S.plans.length`) === 0, 'quant err');
  await s.setVal('#pQuant', '75');
  const days = await s.js(`document.querySelectorAll('#wizardCal .mc').length`);
  check('P4A⑤ 时段选择为日历式（月历格可点）', days >= 28, `cells=${days}`);
  check('P4A⑥ 提供自定义添加空闲时段（日期 / 起止 / 备注）',
    await s.js(`['csDate','csStart','csEnd','csNote','btn-save-custom-slot'].every(id=>!!document.getElementById(id))`) === true,
    'custom slot');
  await s.setVal('#csStart', '19:30'); await s.setVal('#csEnd', '20:30');
  await s.click('#btn-save-custom-slot'); await sleep(220);
  check('P4A⑦ 自定义时段落盘并出现在日历式选择器中',
    await s.js(`S.slots.length`) === 1 &&
    await s.js(`S.slots[0].startMin`) === 19 * 60 + 30 &&
    await s.js(`document.querySelectorAll('#wizardSlots .slot-opt').length`) >= 1,
    `slots=${await s.js('S.slots.length')}`);
  await s.setVal('#wpNewKp', '某考点'); await s.setVal('#wpNewLine', '先确认条件，再代入验证');
  await s.clickByOnclick('addWizardWeak()'); await sleep(180);
  check('P4A⑧ 向导内可新增薄弱点并关联本规划',
    await s.js(`S.weakPoints.length`) === 1 && await s.js(`wizardWeak.length`) === 1,
    `weak=${await s.js('S.weakPoints.length')}`);
  await s.setVal('#pRegion', '广东深圳'); await s.setVal('#pBook', '人教 A 版 2019');
  await s.click('#btn-save-plan'); await sleep(250);
  const p = await s.js(`S.plans[0]||null`);
  check('P4A⑨ 完整保存：目标 / 75% / 时限 / 时段 / 开始方式 / 基线全部落盘',
    !!p && p.goal === '两周内掌握某考点' && p.quantTarget === 0.75 && p.deadlineDays === 15 &&
    p.slotIds.length === 1 && !!p.startMode && p.weakPointIds.length === 1 &&
    await s.js(`S.profile.region`) === '广东深圳' && await s.js(`S.profile.textbook`) === '人教 A 版 2019',
    JSON.stringify(p));
  check('P4A⑩ 保存后回到规划列表且无卡死',
    await s.js(`currentPage`) === 'plan' && await s.js(`!!document.getElementById('planList')`) === true &&
    await s.js(`1+1`) === 2, 'ok');
  await endSession(h);
};

// P4-B · 薄弱点 / 速查卡 / 会话配置收进规划详情弹层
GROUPS.P4B = async () => {
  const h = await freshSession('p4b'); const s = h.s;
  await s.click('#nav-plan'); await s.click('#btn-new-plan');
  await s.setVal('#pGoal', '规划详情收纳验收'); await s.click('#btn-save-plan'); await sleep(200);
  const id = await s.js(`S.plans[0].id`);
  await s.click('#plan-' + id); await sleep(180);
  const html = await s.js(`document.getElementById('modalHost').innerHTML`);
  check('P4B① 规划详情弹层内同时有薄弱点 / 速查卡 / AI 陪练 / 会话配置',
    html.includes('btn-add-weakpoint') && html.includes('btn-add-quickcard') &&
    html.includes('btn-ai-question') && html.includes('btn-edit-cfg') && html.includes('会话配置'),
    'four sections');
  check('P4B② 导航只有 5 个 Tab，薄弱点/速查卡/会话配置不单列页',
    await s.js(`NAV.length`) === 5 &&
    await s.js(`NAV.every(n=>['today','plan','calendar','kb','mine'].includes(n.id))`) === true &&
    await s.js(`document.querySelectorAll('.nav-bottom button').length`) === 5,
    `nav=${await s.js(`NAV.map(n=>n.id).join(',')`)}`);
  await s.click('#btn-edit-cfg'); await sleep(150);
  check('P4B③ 会话配置可在详情弹层内编辑',
    await s.js(`!!document.getElementById('btn-save-cfg')`) === true &&
    await s.js(`!!document.getElementById('cfgDiff')`) === true, 'editor');
  await s.setVal('#cfgDiff', 'hard', 'change');
  await s.click('#btn-save-cfg'); await sleep(180);
  check('P4B④ 会话配置保存后写回该规划',
    await s.js(`S.plans[0].difficulty`) === 'hard' &&
    (await s.js(`document.getElementById('modalHost').innerHTML`)).includes('压轴'),
    `diff=${await s.js('S.plans[0].difficulty')}`);
  await endSession(h);
};

/* ============================== 执行 ============================== */
async function main() {
  const arg = process.argv.find((a) => a.startsWith('--group='));
  const wanted = arg ? arg.split('=')[1].split(',') : Object.keys(GROUPS);
  for (const name of wanted) {
    if (!GROUPS[name]) { console.log(`未知功能组 ${name}`); process.exit(1); }
  }
  for (const name of wanted) {
    console.log(`\n===== 功能组 ${name} =====`);
    await GROUPS[name]();
  }
  const pass = results.filter((r) => r.ok).length;
  const fail = results.filter((r) => !r.ok).length;
  console.log(`\n断言通过 ${pass} / 失败 ${fail}`);
  console.log(fail === 0 ? '结论: ALL_GREEN 重构验收通过' : '结论: FAILED 存在未通过断言');
  process.exit(fail === 0 ? 0 : 1);
}
main().catch((e) => { console.error('验收脚本异常:', e); process.exit(1); });
