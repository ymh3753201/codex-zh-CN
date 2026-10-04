# macOS 零基础安装教程（预览版）

这套工具使用 Codex Desktop 自带的官方简体中文资源。它不会修改 `/Applications` 中的官方程序，不会复制或删除对话，也不会关闭 macOS 的安全保护。

当前 macOS 工具版本是 `0.1.0-preview.3`。官方主界面可能还受远程翻译开关控制：即使设置中已选择简体中文，页面也可能仍为英文。工具会报告这个限制；仅写入中文设置不能算汉化成功。

## 安装前先看

- 支持目标：macOS 13 或更高版本的官方 Codex Desktop。
- 官方应用在部分版本中显示为 `ChatGPT.app`，但内部包标识仍是 `com.openai.codex`，工具会自动识别。
- 不需要安装 Node.js、Python、Homebrew 或 PowerShell。
- 默认不会退出正在运行的 Codex，避免中断当前任务。
- 安装只改 `~/.codex/config.toml` 中 `[desktop]` 下的 `localeOverride`，修改前会保存备份。其他配置原样保留。

## 学员安装步骤

1. 完整解压 `codex-zh-CN-macOS-v0.1.0-preview.3.zip`，不要只拖出一个文件。
2. 双击 `macOS-一键安装.command`。
3. 看到“语言设置准备完成”后，先保存 Codex 中正在执行的任务，再手动退出 Codex。若提示远程翻译开关未验证，这是“部分完成”，请继续查看实际界面。
4. 双击 `macOS-打开中文版.command`。
5. 亲眼检查顶部菜单和主界面。如果两处都是中文，再向助教报告“界面中文已确认”。如果菜单或主界面仍是英文，请把实际现象告诉 AI，并让它生成下文的验收失败报告。不要反复重装、改系统语言或清空对话。

如果 macOS 第一次不允许直接打开脚本，请在访达中按住 Control 点击该文件，选择“打开”。不要关闭“系统完整性保护”，也不要运行来源不明的 `sudo` 命令。

## 四个简单入口

| 文件 | 用途 |
| --- | --- |
| `macOS-一键安装.command` | 检查官方应用、签名、公证、架构和中文资源；备份后写入中文设置；默认不重启 |
| `macOS-检查状态.command` | 生成可交给助教的问题报告 |
| `macOS-打开中文版.command` | 再次校验安装状态后，通过官方包标识打开 Codex |
| `macOS-恢复英文.command` | 备份当前配置并恢复英文；默认不重启，也不删除旧备份 |

## 让本机 Codex 中的 AI 执行

请让 AI 在工具包目录运行：

```bash
/bin/bash "scripts/install_macos.sh" --action install --no-restart
```

安装命令退出码为 0 只代表该操作完成；报告中的 `lastResult=partial` 表示中文尚未验收。AI 不应因此宣布汉化成功。你保存任务并手动退出后，再运行：

```bash
/bin/bash "scripts/install_macos.sh" --action open
```

看到界面后，将实际结果告诉 AI。菜单或主界面仍英文时，运行：

```bash
/bin/bash "scripts/install_macos.sh" --action status --ui-result english --json
```

只有你确认菜单和主界面均为中文，才运行：

```bash
/bin/bash "scripts/install_macos.sh" --action status --ui-result chinese --json
```

这些参数记录的是你本次亲眼看到的结果，不会修改程序、远程开关或系统安全设置，也不会永久代替今后的界面验收。

## 如何看状态报告

报告保存在：

```text
~/.codex/zh-cn-tool/macos/diagnostics/
```

重点字段：

- `resourcesReady`：实际中文文件、主进程语言代码及其完整哈希和分块哈希是否通过校验，不只是发现文件名。
- `settingsPrepared`：签名、公证、架构、语言配置和当前版本状态是否通过。
- `languageGateDetected` / `languageGateStatus`：主界面是否依赖远程开关，或逻辑是否尚无法识别。
- `remoteLanguageGateValue`：固定为 `unknown`。程序代码中的默认值不是该账号实际得到的服务端值。
- `installationReady`：语言设置已准备好，而且本次已由你明确确认中文。仅凭未发现已知开关也不能证明运行时一定启用翻译；未实际确认时为 `false`。
- `launchAttempted`：本次是否发送过启动请求。
- `programRunning`：只说明发现进程，不代表页面已经中文。
- `uiLanguageVerified`：默认 `false`；只在本次提供 `--ui-result chinese` 且安全前提通过时为 `true`。
- `toolIssueSuspected` / `problemClassification`：实际仍英文会报告疑似工具兼容缺口，而不是自动认定“工具正常、只怪上游”。
- `failureStage` / `failureMessage`：失败发生在哪一步及简短原因。
- `nextAction`：建议的下一步操作。

报告只记录版本、阶段、校验结果和经过 `~` 隐去用户名的路径，不会复制配置内容、账号、密钥、Cookie 或对话。

## 官方升级后怎么办

官方升级会改变程序资源。`macOS-检查状态.command` 会把旧状态标为过期，并提示重新运行 `macOS-一键安装.command`。工具会重新检查新版签名和中文资源，不会继续使用未经检查的旧记录。

## 恢复英文

双击 `macOS-恢复英文.command`，然后保存任务并手动退出、重新打开 Codex。恢复操作不会卸载官方程序，不会删除对话，也不会删除历史备份。

## 当前验证边界

- 已在 Apple Silicon（arm64）机器、macOS `26.6.2`、Codex `26.930.31730`（构建 `12947`）检查真实应用：包内中文资源齐备，官方 Developer ID 签名有效，Apple 公证通过，实际主进程存在。
- 已用隔离的临时配置完成安装、状态检查、恢复和失败回滚；没有改动本机正式 `~/.codex/config.toml`。
- Intel（x86_64）架构判断已有自动测试，但尚未在真实 Intel Mac 上启动和查看界面。
- 菜单、主界面中文、登录、已有任务可用和恢复英文后的视觉结果，仍需真实用户界面人工验收。
- 自动测试不等于所有 macOS 和所有 Codex 版本都已验证。

本次问题的审查依据与未解决范围见 [语言开关反馈审查](macOS语言开关反馈审查-2026-10-04.md)。当前版本没有在 macOS 上自动修改 App 副本来强行开启远程开关；这类副本需另行解决签名、公证和真实界面验收问题。
