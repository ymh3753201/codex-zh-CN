# macOS 工具包 SHA-256

预览工具包：`codex-zh-CN-macOS-v0.1.0-preview.3.zip`

```text
e2227f285f25b78d5b271cf84896b48ef892a9b40ffe708e8d27fb3dcd9e3b65  codex-zh-CN-macOS-v0.1.0-preview.3.zip
```

该 ZIP 由 `scripts/package-macos.sh` 以固定时间戳和排序生成。Git 仓库不提交 ZIP；GitHub Actions 会重新生成 ZIP 和同名 `.sha256` 文件并作为 `codex-zh-CN-macOS-preview` 构建产物上传。

校验命令：

```bash
shasum -a 256 -c codex-zh-CN-macOS-v0.1.0-preview.3.sha256
```
