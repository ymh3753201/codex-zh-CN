// Developer-only: execute the installed, unmodified production locale component
// in a controlled hook harness. This proves the loading mechanism, not UI acceptance.
import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const path = process.argv[2];
const patched = process.argv.includes("--expect-local-copy");
if (!path) throw Error("usage: node tests/test-macos-renderer-gate.mjs /path/to/app.asar");
const fd = fs.openSync(path, "r");
const read = (offset, size) => {
  const data = Buffer.alloc(size);
  assert.equal(fs.readSync(fd, data, 0, size, offset), size);
  return data;
};
try {
  const prefix = read(0, 16), base = 8 + prefix.readUInt32LE(4);
  const header = JSON.parse(read(16, prefix.readUInt32LE(12)));
  const assets = header.files.webview.files.assets.files;
  const candidates = Object.entries(assets).filter(([name]) => /^(app-initial|index)-.*\.js$/.test(name));
  const components = candidates.map(([name, entry]) => ({name, source: read(base + Number(entry.offset), entry.size).toString()}))
    .filter(item => item.source.includes(patched ? "true/*zh-cn*/" : "enable_i18n"));
  assert.equal(components.length, 1, "renderer layout changed; review before continuing");
  const { name: asset, source } = components[0];
  const gate = source.indexOf(patched ? "true/*zh-cn*/" : "enable_i18n"), start = source.lastIndexOf("function ", gate), end = source.indexOf("function ", gate);
  assert(start >= 0 && end > start);
  const component = source.slice(start, end);
  const name = /^function ([\w$]+)/.exec(component)[1];
  function role(pattern) {
    const match = pattern.exec(component);
    assert(match, `renderer shape changed: ${pattern}`);
    return match[1];
  }
  const override = role(/localeOverride:([\w$]+)/);
  const roles = {
    cache: role(/\(0,([\w$]+)\.c\)/), react: role(/\(0,([\w$]+)\.useState\)/),
    jsx: role(/\(0,([\w$]+)\.jsx\)/), flag: role(/([\w$]+)\(`\d{4,}`\)/),
    data: role(/\{data:[\w$]+\}=([\w$]+)\(/),
    isDefault: role(new RegExp("[\\w$]+=([\\w$]+)\\(" + override.replace(/\$/g, "\\$") + "\\)")),
    resolve: role(/try\{let e;[^;{}]*?e=([\w$]+)\(/), load: role(/await ([\w$]+)\(/),
  };
  async function check(enabled) {
    let current = null, effects = [], loads = 0;
    const stub = new Proxy(x => x, {get: () => stub});
    const bindings = {
      [roles.cache]: {c: n => Array(n).fill(Symbol("empty"))},
      [roles.react]: {useState: () => [current, v => {current = v;}], useEffect: f => effects.push(f)},
      [roles.jsx]: {jsx: (_type, props) => props},
      [roles.flag]: () => ({get: (key, fallback) => key === "enable_i18n" ? enabled : fallback}),
      [roles.data]: () => ({data: {ideLocale: "en-US", systemLocale: "en-US"}}),
      [roles.isDefault]: x => !x || x === "en-US", [roles.resolve]: x => ({locale: x}),
      [roles.load]: async () => {loads++; return {testMessage: "中文加载探针"};},
      document: {documentElement: {}},
    };
    const scope = new Proxy(bindings, {
      has: (_target, key) => typeof key === "string" && key !== "component" && key !== "Symbol",
      get: (target, key) => key === Symbol.unscopables ? undefined : key in target ? target[key] : stub,
    });
    const render = vm.runInNewContext(`with(scope) { (function(){ ${component}; return ${name}; })(); }`, {scope}, {timeout:5000});
    render({localeOverride:"zh-CN", children:"test"});
    for (const effect of effects) effect();
    await new Promise(resolve => setImmediate(resolve));
    effects = [];
    const result = render({localeOverride:"zh-CN", children:"test"});
    assert.equal(result.locale, "zh-CN");
    assert.equal(loads, patched || enabled ? 1 : 0);
    assert.equal(result.messages?.testMessage === "中文加载探针", patched || enabled);
    console.log(`[PASS] ${asset}: locale=zh-CN, remote enable_i18n=${enabled}, local-copy=${patched}, messages loaded=${patched || enabled}`);
  }
  await check(false);
  await check(true);
} finally { fs.closeSync(fd); }
