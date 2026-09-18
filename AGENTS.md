# AGENTS.md

本文件是本项目后续开发和审查时的默认规则。项目面向普通 Windows 用户，所有改动都必须优先保证“能看懂、能失败、能恢复”。

## 项目目标

- 让 Windows 10 和 Windows 11 用户在离线安装 Codex Desktop 后，能够安全准备中文兼容副本。
- 不修改 `WindowsApps` 中的官方安装文件，不覆盖用户对话数据，不要求安装 Node.js、Python 或 PowerShell 7。
- 安装失败时必须留下清晰提示和诊断日志，不能静默退出。

## 修改规则

- 先阅读当前脚本、测试和诊断文档，再做最小范围修改。
- 不把“发现安装目录”“复制文件”“修改语言开关”“启动中文副本”混成一个无法定位的步骤；每个阶段都要有明确错误信息。
- Windows PowerShell 5.1 读取中文脚本时依赖 UTF-8 BOM。新增或修改含中文的 `.ps1` 文件必须保留 UTF-8 BOM，并在发布测试中检查编码。
- 批处理文件必须支持带空格、中文、括号和 `&` 的路径。所有外部路径都要加引号，优先使用 `-LiteralPath`。
- 旧版本残留只能被识别、隔离或安全忽略；删除旧副本、备份或用户数据前必须有明确授权。损坏的状态文件不能阻塞重新安装。
- 复制到兼容副本后必须校验文件完整性；未完成的副本不得写入 `active-copy.json`，也不得成为启动目标。
- 不要把 Windows CI 的通过结果描述成所有真实机器和所有 Codex 版本都已验证。必须分别说明自动化测试、真实 Windows 10/11、实际 Codex 版本和人工界面验收的边界。
- 不得提交账号、令牌、Cookie、用户配置、完整对话、远程支持凭据或真实诊断中的敏感信息。

## 测试要求

提交前至少执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-regressions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-unattended.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-bootstrap.ps1 -HeadlessRunner
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-copy-failures.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-discovery.ps1
```

涉及发布包、长路径或启动器时，还要运行 `tests\test-release.ps1` 或对应的专项测试。修改安装流程后必须在 GitHub Actions 的 Windows Runner 上重新跑 CI；CI 通过后仍要把真实 Windows 10 和 Windows 11 机器测试列为人工验收项。

## 报告格式

给维护者的报告使用简单中文，按“问题原因、修改内容、测试结果、仍未验证的范围”说明。不要只写“已修复”或“测试通过”，要给出可以复现和检查的文件、测试命令或 GitHub 运行链接。

## Git 工作流

- 新功能或修复使用 `codex/` 前缀分支。
- 提交前运行 `git diff --check`，确认没有意外文件、临时日志或发布包。
- 不要擅自合并、发布或删除远程分支；需要合并或发布时由维护者确认。
