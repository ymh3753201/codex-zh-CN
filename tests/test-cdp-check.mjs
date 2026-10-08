// Exercise the real checker with a controlled CDP boundary, without launching Codex.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-zh-cdp-'));
const checker = fileURLToPath(new URL('./e2e/cdp-check.mjs', import.meta.url));
const fixture = path.join(root, 'cdp-fixture.mjs');
fs.writeFileSync(fixture, `
const scenario = process.env.CDP_TEST_SCENARIO;
const nativeTimeout = globalThis.setTimeout;
globalThis.setTimeout = (fn, ms, ...args) => nativeTimeout(fn, ms === 3000 ? 1 : ms === 15000 ? 25 : ms, ...args);
globalThis.fetch = async () => ({ json: async () => [{ type: 'page', url: 'file:///codex/index.html', webSocketDebuggerUrl: 'ws://fixture' }] });
globalThis.WebSocket = class {
  constructor() { nativeTimeout(() => this.onopen(), 0); }
  send(request) {
    const { id, method } = JSON.parse(request);
    if (scenario === 'timeout') return;
    let reply;
    if (scenario === 'protocol-error') reply = { id, error: { message: 'fixture protocol failure' } };
    else if (method === 'Page.captureScreenshot') reply = { id, result: scenario === 'missing-shot' ? {} : { data: Buffer.from('fixture screenshot').toString('base64') } };
    else reply = { id, result: { result: { value: {
      lang: scenario === 'blank-language' ? '' : scenario === 'english' ? 'en-US' : 'zh-CN',
      url: 'file:///codex/index.html',
      text: scenario === 'english' ? 'Welcome to Codex Desktop. Start a new task.' : '欢迎使用桌面程序，现在可以开始一个新的任务并查看设置和帮助。'
    } } } };
    // Deterministic async reply: a busy Windows runner can execute an already-due
    // accelerated deadline before a 0ms timer. Do not weaken checker timeouts.
    queueMicrotask(() => this.onmessage({ data: JSON.stringify(reply) }));
  }
  close() {}
};
`);
try {
  for (const [scenario, expect, passes] of [
    ['chinese', 'zh', true], ['english', 'en', true], ['chinese', 'en', false],
    ['blank-language', 'any', false], ['missing-shot', 'any', false],
    ['protocol-error', 'any', false], ['timeout', 'any', false],
  ]) {
    const result = spawnSync(process.execPath, ['--import', pathToFileURL(fixture).href, checker, '9333', path.join(root, scenario), expect], {
      env: { ...process.env, CDP_TEST_SCENARIO: scenario }, encoding: 'utf8', timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.status === 0, passes, `${scenario}: ${result.stdout}\n${result.stderr}`);
    console.log(`PASS: CDP ${scenario}, expect=${expect}, accepted=${passes}`);
  }
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
