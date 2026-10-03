# macOS 工具包 SHA-256

预览工具包：`codex-zh-CN-macOS-v0.1.0-preview.1.zip`

```text
77fc980241fbcf38af99fdad9c177d18ba3ce73ec52c926037e333a1939021de  codex-zh-CN-macOS-v0.1.0-preview.1.zip
```

该 ZIP 由 `scripts/package-macos.sh` 以固定时间戳和排序生成。Git 仓库不提交 ZIP；GitHub Actions 会重新生成 ZIP 和同名 `.sha256` 文件并作为 `codex-zh-CN-macOS-preview` 构建产物上传。

校验命令：

```bash
shasum -a 256 -c codex-zh-CN-macOS-v0.1.0-preview.1.sha256
```
