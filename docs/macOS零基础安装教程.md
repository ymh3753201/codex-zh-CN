# macOS 零基础安装教程（0.2.0-preview.2）

这个非官方工具使用 Codex 自带的中文词条，保留官方程序、对话和其他配置。不需要 Node.js、Python 或 Homebrew，不关闭系统安全保护。

## 三步使用

1. 完整解压 codex-zh-CN-macOS-v0.2.0-preview.2.zip，双击「macOS-一键安装.command」。不要只拖出一个文件。此包必须有五个 macOS `.command` 入口；旧 Windows v0.3.4 包没有这些入口，不能在 Mac 上安装。
2. 工具先使用官方中文设置，不创建副本，默认不重启。保存正在运行的任务，手动退出 Codex，再双击「macOS-打开中文版.command」。
3. 亲眼检查菜单和主界面。两处都中文就完成，不必再安装。若仍英文，才双击「macOS-兼容汉化.command」，准备独立副本，再保存任务、退出并用「打开中文版」验收。使用副本时，原来的官方图标仍打开官方版本。

另有「macOS-检查状态.command」和「macOS-恢复英文.command」。恢复英文后，保存任务并退出中文版，再从原来的官方图标打开；副本、旧备份和对话都不会删除。

官方程序和兼容副本使用同一份对话目录，不应同时运行。官方仍在运行时，工具会暂停副本启动，提醒你保存任务并手动退出，不会替你关闭正在执行的任务。

## 为什么需要独立副本

部分账号/版本即使选择简体中文，主界面仍不加载中文词条。发现翻译开关不代表你的账号一定有问题。只有明确选择「兼容汉化」，或记录本版本官方界面仍英文后再次安装，才准备独立副本。只处理已识别的翻译逻辑并更新资源校验值，不改官方 App。

副本采用「本地签名」（保证本机副本完整性），**不是 OpenAI 官方签名，也没有新的 Apple 公证**。必要的应用内加载权限仅限此副本，系统保护保持开启。副本不冒用 OpenAI 的推送、共享钥匙串或应用组权限。登录、通知及电脑控制功能仍需单独验收，可能需要重新登录或重新授予正常系统权限。

macOS 如果拒绝启动，请保留报告交给助教；不要删除隔离属性、关闭 Gatekeeper/SIP 或强行直接运行可执行文件。脚本入口被拦截时，只按系统正常的「打开」提示处理，不绕过警告。需要公司管理员批准的机器应交给管理员。

如果官方 Codex 本来就已正常中文，**不需要创建副本**。首次默认安装就只用官方设置。AI 也可选择 --mode native 强制只用官方设置。我们不会把「未发现翻译开关」当作中文已验收。

## 让本机 AI 执行

在解压目录执行（路径含空格、中文也支持）：

~~~bash
/bin/bash "scripts/install_macos.sh" --action install --no-restart
/bin/bash "scripts/install_macos.sh" --action status --json
~~~

保存任务后打开：

~~~bash
/bin/bash "scripts/install_macos.sh" --action open
~~~

本版本官方菜单或主界面仍英文时，记录失败，再安装兼容副本：

~~~bash
/bin/bash "scripts/install_macos.sh" --action status --ui-result english --json
/bin/bash "scripts/install_macos.sh" --action install --no-restart
~~~

只有你明确确认两处都中文，才记录成功：

~~~bash
/bin/bash "scripts/install_macos.sh" --action status --ui-result chinese --json
~~~

不修改程序的官方设置模式：在安装命令加 --mode native。明确选择兼容副本：--mode copy。恢复英文：--action restore --no-restart。--restart 会退出相应目标；恢复时先退出受管副本，再重启官方 Codex，仅在保存所有任务并明确同意后使用。

## 报告怎么看

安装器先检查工具包文件与版本。文件缺失或混用版本时，在修改用户配置前停止，失败阶段为 `tool-package-check`，问题报告保存在显示出的临时目录。`toolPackageReady` 只表示下载文件齐全，不等于中文资源、安装或界面已通过。

报告默认位于 ~/.codex/zh-cn-tool/macos/diagnostics/，对应日志在 logs/，配置备份在 backups/，副本在 copies/。使用自定义 CODEX_HOME 时跟随该目录。

- resourcesReady：官方中文资源的实际字节和完整性记录通过。
- settingsPrepared：语言设置和当前版本状态通过检查。
- nativeUiEnglishConfirmed：本版本官方界面曾由你确认仍英文；普通后续检查也会保留兼容汉化建议。官方升级后不沿用该反馈。
- installationReady：兼容副本已完整准备且签名通过；**不等于已启动或界面已中文**。仅官方设置模式需要本次明确中文确认才能为真。
- copyActivated：该副本曾通过启动检查。失败或中断的复制不会激活。
- copySignatureKind / copyNotarizationAccepted：如实区分本地签名和公证，不能把官方公证当成副本公证。
- programRunning：中文目标的进程存在，不会把官方 App 冒充中文副本。
- uiLanguageVerified：默认为 false，只记录本次你明确确认的结果。
- lastResult=partial：尚待界面确认；不是「工具完全正常、只怪上游」。
- failureStage / failureMessage / nextAction：失败步骤、原因及下一步。

只向助教提供报告；日志可能有系统路径，请先脱敏。不要附密钥、账号、Cookie、完整配置、对话或私人截图。

## 升级与故障

官方升级后重新运行安装，先检查新版官方签名和资源，再优先尝试新版官方设置。旧的英文反馈不代表新版也失败；若新版仍英文，再选择兼容汉化。旧副本和备份保留，不会自动删除。重复安装同一版本会复核并复用完整副本。

空间不足、复制失败、资源损坏、签名失败或未知翻译逻辑，工具会停止并保留报告。未知版本不会猜测修改。系统拒绝副本启动时不会改系统保护；请把报告交给助教。

当前实测和仍待验收范围见 [兼容副本实测记录](macOS兼容副本实测-2026-10-06.md)。这是预览版，不代表所有 Mac、登录与全部任务功能已验收。
