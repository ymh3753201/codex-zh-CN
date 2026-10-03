# Codex Desktop 中文兼容工具 v0.3.5

用于 Windows 10 / Windows 11 的非官方离线汉化工具，使用 Codex 自带的中文资源。

**v0.3.5 当前为待验收版本，尚未正式发布。** Windows 10 / Windows 11 的真实安装、界面中文和恢复验收尚未完成。

v0.3.5 改善新版语言开关识别、商店查找兜底、磁盘空间提示和英文系统上的中文快捷方式。完整解压新版到新文件夹后运行，不要只替换 BAT 文件。

双击“一键安装”完全没反应时，尝试同目录的 `install-fallback.vbs`。它绕过 BAT 入口直接启动安装器；如果系统禁用了脚本，这个入口也可能无法执行。

未自动找到自定义安装位置时，先打开该 Codex 再运行工具；也可以把 Codex 的实际 `Codex.exe`、`ChatGPT.exe` 或安装文件夹拖到 `install-windows.bat` 上。商店安装在其他磁盘时仍通过系统注册信息查找。

## 怎么使用

**安装在“准备中文程序”阶段报路径错误？** 请完整解压维护者提供的新版工具，重新运行 **一键安装.bat**。本版修复复制后的深层目录处理问题，无需修改注册表或安装 PowerShell 7。如果仍失败，请保留 `diagnostics` 中的新报告及报告指向的复制日志。

**已经汉化成功，但每次启动都提示“官方 Codex 或旧中文副本仍在运行”？** 双击 **修复启动.bat**，看到“启动器和中文快捷方式已修复”后，使用桌面或开始菜单的“Codex 中文版”打开。此入口只修复启动，不修复尚未完成的安装。

1. 安装 Codex，并至少打开一次。
2. 解压本工具，双击 **一键安装.bat** 或 **一键汉化.bat**。使用平时运行 Codex 的 Windows 账号，不需要管理员权限。
3. 安装全程自动进行，无需按空格或回车。窗口显示 5 个阶段；完成后提示“汉化完成，已启动 Codex 中文版”，8 秒后自动关闭。
4. **以后请从桌面或开始菜单的“Codex 中文版”打开。** 原来的官方图标仍启动官方程序，可能继续显示英文。

第一次运行需要额外空间存放一份 Codex 程序，通常为数 GB；复制速度取决于电脑和磁盘。工具自身不下载任何内容，不要求安装 Node.js、Python 或 PowerShell 7。Codex 在线服务仍需要它自身的网络和登录条件。

中文文件名不能运行时，双击英文入口 `install-windows.bat`，效果相同。

### 安装时为什么以前需要按空格

旧版入口末尾有隐藏的按键等待；Windows 10 传统终端的“快速编辑”还可能在选中文字时暂停输出。v0.3.1 取消安装入口的按键等待，并在安装期间关闭本窗口的快速编辑，结束后恢复。不修改系统注册表或其他终端的设置。

通过 BAT 入口安装失败时，会保留错误窗口等待确认，不会立即消失。启动日志位于工具的 `diagnostics` 文件夹；该目录无法写入时，改存 `%TEMP%\codex-zh-diagnostics`。PowerShell 本身启动失败的信息另存 `%TEMP%\codex-zh-startup-*.log`。日志包含安装路径和用户名。

v0.3.3 在复制时直接处理只读属性，避免 Windows PowerShell 对很深的依赖目录再次遍历。每次新建副本都有独立复制日志；若失败后的临时副本无法清理，会明确提示保留位置，原始失败原因仍然保留，不会启用未完成的副本。

## 为什么 v0.2.1 显示成功，界面却没有变

v0.2.1 只在配置中写入“使用中文”。实际检查发现，当前 Codex 主界面还受一个独立的翻译加载开关控制：开关关闭时，即使语言配置为中文，也不会加载中文词条。

v0.3.0 自动识别这段逻辑，在用户目录的程序副本中启用翻译加载，并使用独立的界面缓存避免启动被官方窗口接管。官方安装目录保持不变。

另外，“关于”中的 `26.908.70816` 与 Store 安装包的 `26.908.9136.0` 是当前同一个应用的两套编号，不能据此判断装错版本。

## 检查、更新与恢复

| 入口 | 用途 |
| --- | --- |
| 一键安装.bat / 一键汉化.bat / install-windows.bat | 自动准备并启动中文兼容版，全程无需按键 |
| 修复启动.bat | 更新已安装的启动器和中文快捷方式，修复启动误报；全程无需按键 |
| 检查状态.bat / check-status.bat | 显示版本、配置路径、加载开关和副本位置；保存诊断报告 |
| 恢复英文.bat / uninstall-codex.bat | 语言恢复英文，恢复匹配的插件原文，移除本工具的中文快捷方式 |

**官方 Codex 更新后，请重新运行一键汉化。** 中文副本不会自动变成新版。重复运行同一版本会核对文件并复用有效副本。

恢复英文不会卸载 Codex，也不会删除对话。程序副本和备份会保留，便于排错；多个不同版本的副本会占用额外磁盘空间。

如果仍未显示中文，双击“检查状态.bat”，将工具文件夹 `diagnostics` 中最新的 JSON 报告提供给维护者。报告包含版本、路径和语言状态，不包含账号密钥、完整配置或对话内容；路径包含 Windows 用户名。

### 重复打开时的行为

中文版已打开时，启动器会尝试恢复并切换到已有窗口；在托盘中时，会向同一个程序发送打开请求。官方后台进程不会直接拦截中文启动。如果旧中文副本仍在使用同一份界面缓存，会先复用它，保留正在进行的任务；退出后再打开，才使用新副本。只有程序丢失或启动检查失败等实际错误才弹窗。

启动结果保存在数据目录下的 `zh-cn-tool\last-launch.json`，并包含在“检查状态”报告中。

## 修改哪些文件

默认数据目录是 `%USERPROFILE%\.codex`；设置过 `CODEX_HOME` 的用户会使用对应目录。

- `config.toml`：只修改 `[desktop]` 下的 `localeOverride`，修改前保存备份。
- `zh-cn-tool\copies`：官方程序的独立副本，仅修改翻译加载开关，并同步资源完整性信息。
- `zh-cn-tool\user-data`：中文副本的独立界面缓存。首次打开可能需要重新确认部分界面设置或登录状态。
- `zh-cn-tool\launcher`：持久启动器，移动或删除下载的工具文件夹不会使快捷方式失效。
- 插件缓存中的少量名称和说明：只有原文匹配已审查版本时才应用翻译，并保留原文件备份。

不会改动 `WindowsApps`、获取系统目录所有权或关闭其他目录中的 ChatGPT / Codex 命令行程序。官方程序与中文副本共用 Codex 数据目录，建议一次只运行其中一个。

## 兼容性与测试范围

- 安装器使用 Windows 10 / 11 自带的 **Windows PowerShell 5.1**。
- 本次检查版本：Store `26.908.9136.0`，应用 `26.908.70816`。
- v0.3.5 新增离线审计：Store `26.917.9434.0`，应用 `26.917.71314`。翻译开关识别不再依赖层编号；Windows 实机复测待完成。
- v0.3.4 新增验证：Store `26.911.7940.0`，应用 `26.911.61220`。已用真实资源验证翻译开关修复、文件完整性，以及隔离副本启动和重复启动；不是对所有页面的视觉验收。
- 已在本机 Windows 11 执行真实界面逻辑测试、程序副本启动测试、配置和恢复测试。
- **用户已确认 v0.3.0 在原 Windows 10 电脑上汉化通过。** v0.3.3 已在本机 Windows PowerShell 5.1 的旧式路径限制测试环境中验证复制流程；仍需在报错电脑确认实际表现。截图中的 Codex `26.901.6511.0` 尚未进行完整运行验证，不能据此承诺所有版本均兼容。
- 当前官方安装清单最低要求为 Windows 构建 `19041`。截图中的 Windows 10 22H2 不能仅因系统名称就被判为不支持。
- 程序结构无法识别时会停止。官方尚未翻译的词条、在线内容及模型回答不属于本工具保证范围。

## 如何看 AI 的安装报告

`ready: true` 是早期保留字段，只表示发现了官方中文资源，**不能证明安装完成或界面已经中文**。新版状态报告同时提供：

- `toolVersion`：当前检查工具的版本；`compatibleCopyToolVersion`：制作现有中文副本时使用的工具版本。
- `resourcesReady`：中文资源是否齐备，与旧 `ready` 含义相同。
- `localizationReady`：语言配置、当前副本和启动器是否准备就绪。
- `uiLanguageVerified: false` / `uiVerificationStatus: pending-user-check`：本工具没有检查窗口语言，需用户打开中文版确认；这本身不是安装失败。
- `nextAction`：下一步。`open-chinese-shortcut-and-check-ui` 表示打开中文版检查界面；`repair-launcher` 表示修复启动入口；`reinstall-compatible-copy` 表示副本过期或损坏，需重新安装。

安装包版本、可执行文件元数据版本和“关于”版本可能采用不同编号。反馈问题时一并提供这些编号，不要仅因编号不同就判断装错版本。

**让当前 Codex 中的 AI 帮忙安装时，使用 `-NoRestart`。** 先保留正在执行的任务，安装结束后保存任务并手动退出官方 Codex，再从“Codex 中文版”打开。没有打开界面前，应报告“安装准备完成，界面待确认”。

“修复启动”只修复启动器和快捷方式，不会重新复制或修补程序，不能解决所有仍显示英文的问题。副本过期或损坏时，新版会拒绝此操作并提示重新安装。如果副本检查正常但界面仍是英文，请提供状态报告和截图给助教，不要反复重装。官方更新不会自动更新中文副本，旧副本可能继续显示中文但仍是旧版本；应重新汉化后再验收。

2026-10-03 收到的学员报告说明 v0.3.4 在 Windows 10 构建 19045、Store `26.928.1915.0` 上完成了安装准备。尚未取得原始诊断文件、中文版启动和界面验收证据，不能据此宣布该版本全面兼容。分析见 [学员报告审查](docs/student-report-review-2026-10-03.md)。

## 高级选项

普通用户不需要运行以下命令。

```powershell
# 手动指定便携版目录；也可以指定 Store 包根目录
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_windows.ps1 -CodexPath "D:\Codex"

# 只修改语言配置，不制作兼容副本（受官方翻译开关影响）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_windows.ps1 -Mode builtin -NoRestart

# 当前 Codex 中的 AI 执行安装：保留正在运行的窗口
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_windows.ps1 -NoRestart

# 输出机器可读状态
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_windows.ps1 -Action status -Json
```

支持 `-CodexHome`、`CODEX_HOME`、`CODEX_DESKTOP_PATH`、`CODEX_ZH_CN_PATH`。复杂的内联或点分 desktop 配置会被明确拒绝，以免写入无效或重复设置。

## 开发验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-regressions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-workflow.ps1 -LegacyLongPaths
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-unattended.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-console-mode.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-installer.ps1
python tests\test-locale-gate.py "C:\path\to\app.asar"
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package-release.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test-release.ps1
```

开发测试中的 Python / Node.js 不是用户安装时的依赖。真实安装包测试需要本机已安装所审查的 Codex 版本。证据和边界见 [排查报告](docs/diagnosis-v0.3.0.md)。

推送主分支或 `codex/` 分支后，GitHub Actions 会自动运行以下用例：配置回归、启动器、无按键入口、Bootstrap、隐藏控制台、复制失败、安装位置识别和发布包打包，并对生成的 ZIP 再运行安装回归和源码哈希校验，见 `.github/workflows/ci.yml`。

中文快捷方式使用 Windows 的 Unicode 接口，`test-workflow.ps1` 和发布 ZIP 的回归检查现在也在英文系统运行。CI 使用 `test-release.ps1 -HeadlessRunner -SkipInstalledAppTests`：只跳过需要真实 Codex 安装的隔离用例，并把失败窗口的人工按键等待留给实机检查；不会跳过副本、长路径或快捷方式测试。

`test-installer.ps1`、`test-runtime.ps1`、`test-student-matrix.ps1` 和 `test-locale-gate.py` 的完整验证仍需要所审查的真实 Codex 安装包或 Windows 环境。真实端到端工作流还需提供 `CODEX_MSIX_URL`；当前未提供地址，也没有该工作流的成功记录。GitHub Windows Server 运行器不等于 Windows 10/11 实机。

自动安装改进见 [v0.3.1 更新说明](RELEASE_NOTES_v0.3.1.md)。

启动误报修复见 [v0.3.2 更新说明](RELEASE_NOTES_v0.3.2.md)。

复制与长路径修复见 [v0.3.3 更新说明](RELEASE_NOTES_v0.3.3.md)。

本项目基于 [xqnode/codex-zh-CN](https://github.com/xqnode/codex-zh-CN) 的 MIT 许可版本重新设计，与 OpenAI 无关。发布 ZIP 不包含 Codex 官方程序。
