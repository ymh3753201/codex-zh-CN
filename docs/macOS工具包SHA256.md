# macOS 工具包 SHA-256

预览工具包：`codex-zh-CN-macOS-v0.2.0-preview.1.zip`

```text
e5a909edbe99d47d76323706025788b303cab7aac4054204083952e8c3d0ae34  codex-zh-CN-macOS-v0.2.0-preview.1.zip
```

该 ZIP 由 `scripts/package-macos.sh` 以固定时间戳和排序生成。Git 仓库不提交 ZIP；GitHub Actions 会重新生成 ZIP 和同名 `.sha256` 文件并作为 `codex-zh-CN-macOS-preview` 构建产物上传。

校验命令：

```bash
shasum -a 256 -c codex-zh-CN-macOS-v0.2.0-preview.1.sha256
```
