#!/usr/bin/env node
import fs from "node:fs";

const [outputPath, mode = "complete", marker = "v1"] = process.argv.slice(2);
if (!outputPath) {
  console.error("usage: make-macos-fixture.mjs <output> [complete|missing-zh] [marker]");
  process.exit(2);
}

const files = {
  "native-menu-locales": {
    files: mode === "missing-zh" ? { "en.json": { size: 2, offset: "0" } } : {
      "en.json": { size: 2, offset: "0" },
      "zh-CN.json": { size: 2, offset: "2" },
    },
  },
  webview: {
    files: {
      assets: {
        files: mode === "missing-zh" ? { "en-test.js": { size: 2, offset: "4" } } : {
          "en-test.js": { size: 2, offset: "4" },
          "zh-CN-test.js": { size: 2, offset: "6" },
        },
      },
    },
  },
  ".vite": {
    files: {
      build: { files: { "main-test.js": { size: 64, offset: "8" } } },
    },
  },
};
const json = Buffer.from(JSON.stringify({ files }), "utf8");
const headerSize = 8 + json.length;
const prefix = Buffer.alloc(16);
prefix.writeUInt32LE(4, 0);
prefix.writeUInt32LE(headerSize, 4);
prefix.writeUInt32LE(json.length + 4, 8);
prefix.writeUInt32LE(json.length, 12);
const content = Buffer.from(
  mode === "missing-zh"
    ? `fixture ${marker} without language switches`
    : `{}{}{}{} localeOverride nativeIntl fixture ${marker}`,
  "utf8",
);
fs.writeFileSync(outputPath, Buffer.concat([prefix, json, content]));
