#!/usr/bin/env node
// Connect to a running Codex window over the Chrome DevTools Protocol and
// record what the user would see: <html lang>, visible text and a screenshot.
// Usage: node cdp-check.mjs <port> <outPrefix> <expect: zh|en|any>
import fs from "node:fs";

const [port, outPrefix, expect = "any"] = process.argv.slice(2);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const deadline = Date.now() + 180_000;

async function findPage() {
  while (Date.now() < deadline) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = list.find((t) => t.type === "page" && t.webSocketDebuggerUrl && !t.url.startsWith("devtools:"));
      if (page) return page;
    } catch {}
    await sleep(2000);
  }
  throw new Error(`No debuggable Codex page on port ${port} within 180s`);
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let id = 0;
    const pending = new Map();
    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    };
    ws.onerror = () => reject(new Error("CDP WebSocket failed"));
    ws.onopen = () =>
      resolve({
        send: (method, params = {}) =>
          new Promise((done, fail) => {
            const requestId = ++id;
            const timer = setTimeout(() => {
              pending.delete(requestId);
              fail(new Error(`CDP request timed out: ${method}`));
            }, 15_000);
            pending.set(requestId, (msg) => {
              clearTimeout(timer);
              if (msg.error) fail(new Error(`CDP ${method}: ${msg.error.message}`));
              else done(msg);
            });
            ws.send(JSON.stringify({ id: requestId, method, params }));
          }),
        close: () => ws.close(),
      });
  });
}

const page = await findPage();
const cdp = await connect(page.webSocketDebuggerUrl);
const probe = `(() => ({ lang: document.documentElement.lang, url: location.href,
  text: (document.body && document.body.innerText || '').slice(0, 4000) }))()`;
let state = { lang: "", text: "", url: "" };
while (Date.now() < deadline) {
  const r = await cdp.send("Runtime.evaluate", { expression: probe, returnByValue: true });
  state = r.result?.result?.value ?? state;
  if (state.text.replace(/\s/g, "").length >= 20) break;
  await sleep(2000);
}
await sleep(3000); // let async locale messages arrive
const r2 = await cdp.send("Runtime.evaluate", { expression: probe, returnByValue: true });
state = r2.result?.result?.value ?? state;
const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
if (!shot.result?.data) throw new Error("CDP did not return a screenshot");
if (shot.result?.data) fs.writeFileSync(`${outPrefix}.png`, Buffer.from(shot.result.data, "base64"));
cdp.close();

const cjk = (state.text.match(/[一-鿿]/g) || []).length;
const latinWords = (state.text.match(/[A-Za-z]{3,}/g) || []).length;
const report = { port: Number(port), expect, lang: state.lang, url: state.url, cjkChars: cjk, latinWords, sample: state.text.slice(0, 600) };
fs.writeFileSync(`${outPrefix}.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));

if (!state.lang || state.text.replace(/\s/g, "").length < 20) {
  console.error("FAIL: window has no usable language or visible UI"); process.exit(1);
}
const chinese = state.lang.toLowerCase().startsWith("zh") && cjk >= 10;
if (expect === "zh" && !chinese) { console.error("FAIL: expected a Chinese UI"); process.exit(1); }
if (expect === "en" && chinese) { console.error("FAIL: control window unexpectedly Chinese"); process.exit(1); }
console.log(`PASS: expect=${expect}, lang=${state.lang}, cjk=${cjk}`);
