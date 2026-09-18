#!/usr/bin/env node
import fs from "node:fs";

function readAsarHeader(data, asarPath) {
  if (data.length < 16 || data.readUInt32LE(0) !== 4) {
    throw new Error(`不支持的 app.asar 格式: ${asarPath}`);
  }
  const headerSize = data.readUInt32LE(4);
  const pickle = data.subarray(8, 8 + headerSize);
  const stringSize = pickle.readInt32LE(4);
  return {
    headerSize,
    header: JSON.parse(pickle.subarray(8, 8 + stringSize).toString("utf8")),
  };
}

function walk(node, prefix = "", results = []) {
  if (node.files) {
    for (const [name, child] of Object.entries(node.files)) {
      walk(child, prefix ? `${prefix}/${name}` : name, results);
    }
  } else if (node.offset !== undefined) {
    results.push([prefix, node]);
  }
  return results;
}

function getEntry(header, filePath) {
  let node = header;
  for (const part of filePath.split("/")) node = node.files?.[part];
  if (!node || node.offset === undefined) {
    throw new Error(`app.asar 中没有文件: ${filePath}`);
  }
  return node;
}

function readEntry(data, parsed, filePath) {
  const entry = getEntry(parsed.header, filePath);
  const offset = 8 + parsed.headerSize + Number(entry.offset);
  return data.subarray(offset, offset + Number(entry.size));
}

const asarPath = process.argv[2];
if (!asarPath) {
  console.error("用法: node scripts/analyze-codex-asar.mjs <app.asar 路径>");
  process.exit(2);
}

const data = fs.readFileSync(asarPath);
const parsed = readAsarHeader(data, asarPath);
const files = walk(parsed.header);
const fileNames = files.map(([name]) => name);

const nativeLocaleFiles = fileNames
  .filter((name) => name.startsWith("native-menu-locales/") && name.endsWith(".json"))
  .sort();
const webviewZhFiles = fileNames.filter(
  (name) => name.includes("webview/assets/zh-CN-") && name.endsWith(".js"),
);
const webviewLocaleFiles = fileNames.filter(
  (name) =>
    name.includes("webview/assets/") &&
    /\/[a-z]{2}(?:-[A-Z][A-Za-z]{1,3})?-[^/]+\.js$/.test(name),
);
const mainBundle = fileNames.find(
  (name) => name.includes(".vite/build/main-") && name.endsWith(".js"),
);

const zhNativePath = nativeLocaleFiles.find((name) => name.endsWith("/zh-CN.json"));
const zhNative = zhNativePath
  ? JSON.parse(readEntry(data, parsed, zhNativePath).toString("utf8"))
  : {};
const nativeLocales = nativeLocaleFiles.map((filePath) => ({
  filePath,
  messages: JSON.parse(readEntry(data, parsed, filePath).toString("utf8")),
}));
const largestNative = [...nativeLocales].sort(
  (a, b) => Object.keys(b.messages).length - Object.keys(a.messages).length,
)[0];
const missingNativeKeys = largestNative
  ? Object.keys(largestNative.messages).filter((key) => !(key in zhNative))
  : [];
const englishLikeNativeValues = Object.entries(zhNative)
  .filter(([, value]) => typeof value === "string" && /^[\x00-\x7f]+$/.test(value))
  .map(([key, value]) => ({ key, value }));

const mainText = mainBundle
  ? readEntry(data, parsed, mainBundle).toString("utf8")
  : "";
const localeOverrideContexts = [];
let localeIndex = 0;
while ((localeIndex = mainText.indexOf("localeOverride", localeIndex)) >= 0) {
  localeOverrideContexts.push(
    mainText.slice(Math.max(0, localeIndex - 100), localeIndex + 180),
  );
  localeIndex += "localeOverride".length;
}

function extractMessageKeys(content) {
  return new Set([...content.matchAll(/"([a-zA-Z0-9_.-]+)":`/g)].map((match) => match[1]));
}

const webviewLocales = webviewLocaleFiles.map((filePath) => {
  const content = readEntry(data, parsed, filePath).toString("utf8");
  return { filePath, bytes: Buffer.byteLength(content), keys: extractMessageKeys(content) };
});
const zhWebview = webviewLocales.find(({ filePath }) => filePath.includes("/zh-CN-"));
const largestWebview = [...webviewLocales].sort((a, b) => b.keys.size - a.keys.size)[0];
const missingZhWebviewKeys =
  zhWebview && largestWebview
    ? [...largestWebview.keys].filter((key) => !zhWebview.keys.has(key))
    : [];
const report = {
  asarPath,
  asarBytes: data.length,
  totalFiles: files.length,
  mainBundle,
  mainUsesNativeIntl: mainText.includes("nativeIntl"),
  mainLocaleOverrideOccurrences: localeOverrideContexts.length,
  localeOverrideContexts,
  nativeLocaleCount: nativeLocaleFiles.length,
  hasNativeZhCn: Boolean(zhNativePath),
  nativeZhCnKeys: Object.keys(zhNative).length,
  largestNativeLocale: largestNative?.filePath ?? null,
  largestNativeLocaleKeys: largestNative ? Object.keys(largestNative.messages).length : 0,
  missingNativeKeys,
  englishLikeNativeValues,
  webviewZhFiles,
  webviewLocaleCount: webviewLocales.length,
  webviewZhCnKeys: zhWebview?.keys.size ?? 0,
  largestWebviewLocale: largestWebview?.filePath ?? null,
  largestWebviewLocaleKeys: largestWebview?.keys.size ?? 0,
  missingZhWebviewKeys,
};

console.log(JSON.stringify(report, null, 2));
