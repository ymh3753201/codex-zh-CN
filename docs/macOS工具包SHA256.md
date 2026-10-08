# macOS 工具包 SHA-256

预览工具包：`codex-zh-CN-macOS-v0.2.0-preview.2.zip`

```text
96baccb9a4d94d8f6585ce48bc1583942cc4acffb666c9a93ac29fb689f8973e  codex-zh-CN-macOS-v0.2.0-preview.2.zip
```

该 ZIP 由 `scripts/package-macos.sh` 以固定时间戳和排序生成。Git 仓库不提交 ZIP；GitHub Actions 会重新生成 ZIP 和同名 `.sha256` 文件并作为 `codex-zh-CN-macOS-preview-arm64` / `codex-zh-CN-macOS-preview-x86_64` 构建产物上传。两种环境应生成同一工具包。

这是独立 macOS 工具包的哈希，**不能用来校验 GitHub 源码 ZIP**。

校验命令：

```bash
shasum -a 256 -c codex-zh-CN-macOS-v0.2.0-preview.2.sha256
```
