# macOS 工具包 SHA-256

预览工具包：`codex-zh-CN-macOS-v0.2.0-preview.1.zip`

```text
a1304cf2bea3f0e81726f749f61f93c81897609eff91b2d754e5640e1b3c889e  codex-zh-CN-macOS-v0.2.0-preview.1.zip
```

该 ZIP 由 `scripts/package-macos.sh` 以固定时间戳和排序生成。Git 仓库不提交 ZIP；GitHub Actions 会重新生成 ZIP 和同名 `.sha256` 文件并作为 `codex-zh-CN-macOS-preview` 构建产物上传。

校验命令：

```bash
shasum -a 256 -c codex-zh-CN-macOS-v0.2.0-preview.1.sha256
```
