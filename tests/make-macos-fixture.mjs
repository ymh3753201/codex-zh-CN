#!/usr/bin/env node
import fs from "node:fs";
import crypto from "node:crypto";

const [outputPath, mode = "complete", marker = "v1"] = process.argv.slice(2);
if (!outputPath) throw new Error("missing output path");
const sha = data => crypto.createHash("sha256").update(data).digest("hex");
const tree = { files: {} }, content = [];
let offset = 0;
function add(path, text) {
  const data = Buffer.from(text);
  let parent = tree;
  const parts = path.split("/");
  const name = parts.pop();
  for (const part of parts) parent = (parent.files[part] ??= { files: {} });
  parent.files[name] = { size: data.length, offset: String(offset), integrity: {
    algorithm: "SHA256", hash: sha(data), blockSize: 4194304, blocks: [sha(data)],
  }};
  content.push(data); offset += data.length;
}
add(".vite/build/main-test.js", `localeOverride nativeIntl fixture ${marker}`);
add("webview/assets/app-initial-test.js", mode === "gated"
  ? 'function provider(e){let {localeOverride:r}=e;let s=layer(`72216192`);let c=s?.get(`enable_i18n`,!1);return c?loadMessages(r):null;}'
  : mode === "unknown-gate"
    ? 'function provider(e){return newLanguageGate("enable_i18n", e.localeOverride);}'
    : 'function provider(e){return loadMessages(e.localeOverride);}' );
add("webview/assets/general-settings-test.js", mode === "gated"
  ? 'function settings(e){let c=layer(`72216192`)?.get(`enable_i18n`,!0);return c?e.localeOverride:null;}'
  : 'function settings(e){return e.localeOverride;}');
if (mode !== "missing-zh") {
  add("native-menu-locales/zh-CN.json", '{"newTask":"新任务"}');
  add("webview/assets/zh-CN-test.js", 'export default {newTask:"新任务"};');
}
const json = Buffer.from(JSON.stringify(tree));
const prefix = Buffer.alloc(16);
prefix.writeUInt32LE(4, 0);
prefix.writeUInt32LE(8 + json.length, 4);
prefix.writeUInt32LE(json.length + 4, 8);
prefix.writeUInt32LE(json.length, 12);
const payload = Buffer.concat(content);
if (mode === "corrupt-zh") payload[payload.length - 2] ^= 1;
fs.writeFileSync(outputPath, Buffer.concat([prefix, json, payload]));
