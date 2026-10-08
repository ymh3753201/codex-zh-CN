# Codex 汉化 AI 提示词

复制下面全部内容，直接发给本机 AI：

```text
请你直接在我的电脑上完成 Codex Desktop 汉化，不要只给我教程或命令，请使用本机终端实际执行。

非官方汉化工具仓库：https://github.com/ymh3753201/codex-zh-CN
只下载这个完整工具 ZIP：https://codeload.github.com/ymh3753201/codex-zh-CN/zip/03057f757d9722ff0228d4b73493bf0723110912
固定提交：03057f757d9722ff0228d4b73493bf0723110912
该 ZIP 的 SHA-256：71492691fcba778fdcd2d28ad474ccbe3dbbe81fcedd2252c38a4dfa2ca90c78
其中 Windows 工具版本为 0.3.5，macOS 工具版本为 0.2.0-preview.2。

请完成以下任务：

1. 自动识别 Windows 或 macOS，从上面的固定 ZIP 地址下载到新的独立目录，核对 SHA-256、完整解压并检查入口。不要改用 main、latest 或旧版 v0.3.4；旧包没有 macOS 入口。哈希不符或入口缺失时，先报告“工具下载版本或完整性检查失败”，只允许重新下载一次；仍失败就停止，不修改配置，不用手动设置中文冒充工具安装。不要让我另外安装 Git、Node.js、Python、Homebrew 或 PowerShell 7。若使用助教网盘包，请核对它对应的校验值，不能套用另一个 ZIP 的哈希。

macOS 在终端解压时使用系统自带 `/usr/bin/ditto -x -k "<下载的ZIP>" "<新的解压目录>"`，避免旧版 unzip 造成中文文件名乱码；不要通过改名或拼凑脚本绕过完整性检查。

2. 使用与系统对应的工具自带入口安装，默认不关闭或重启当前 Codex：
   - macOS 先做工具包预检：`/bin/bash "<工具目录>/scripts/check-macos-package.sh"`。预检通过才安装；工具未安装时应如实报告，不能仅凭中文配置声称完成。
   - Windows：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<工具目录>\scripts\install_windows.ps1" -NoRestart`
   - Windows 状态检查：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<工具目录>\scripts\install_windows.ps1" -Action status -Json`
   - macOS：`/bin/bash "<工具目录>/scripts/install_macos.sh" --action install --no-restart`
   - macOS 状态检查：`/bin/bash "<工具目录>/scripts/install_macos.sh" --action status --json`

3. 如果遇到下载失败、文件缺失、权限、空间不足、Codex 升级或状态损坏等问题，请先查看工具日志和诊断报告，找到原因后做可恢复的修复，然后最多重试一次。不要关闭系统安全保护，不要修改官方 Codex 程序，不要删除对话、配置、旧备份或失败副本。如果需要危险操作，或确认是工具本身的问题，请停止继续修改并说明原因。

macOS 首次默认只用官方设置，已正常中文就不创建副本。我确认重启后菜单或主界面仍英文时，请先用 `--action status --ui-result english --json` 记录，再重新执行安装命令，允许工具在独立副本中处理已识别的翻译开关；官方 App 不得改动。本地签名不等于官方签名或 Apple 公证，系统拒绝启动时不要绕过安全保护。报告 `lastResult=partial` 表示仍待界面确认，不要反复安装，也不能认定“工具正常、只怪上游”。

4. 安装完成后，请分别检查并报告：
   - 工具包完整且平台正确（macOS 看 `toolPackageReady`，Windows 检查入口和版本）
   - 中文资源齐备（`resourcesReady`）
   - 安装准备完成（Windows 看 `localizationReady`；macOS 分开看 `settingsPrepared` 和 `installationReady`）
   - 程序是否已启动
   - 界面中文已确认

“程序已启动”不等于“界面中文已确认”。如果需要重新打开 Codex，请先提醒我保存正在进行的任务，等我确认后再操作。界面是否中文必须由我亲眼确认，不能只根据脚本成功、进程存在或截图生成就宣布成功。

macOS 中，兼容副本仍英文时，请运行 `--action status --ui-result english --json` 生成失败报告并停止重装；只有我明确确认菜单和主界面均中文，才用 `--ui-result chinese`。随后给我最终反馈，不要在工具支持范围之外猜测修改程序。

5. 最后请直接给我以下结果：

【汉化结果】
- 系统和芯片：
- Codex 版本：
- 工具提交：
- 下载文件 SHA-256：
- 工具包与平台匹配：是 / 否
- 中文资源齐备：是 / 否 / 未检查
- 安装准备完成：是 / 否
- 程序启动：是 / 否 / 未尝试
- 界面中文已确认：是 / 否 / 待我确认
- 已处理的问题：
- 下一步：

【助教反馈正文】
- 是否疑似工具问题：是 / 否 / 无法判断
- 失败阶段：
- 下载来源与版本：
- 关键错误：
- 已做的排障：
- 诊断报告位置：
- 建议检查内容：

反馈中不要包含密钥、Cookie、完整对话、私人文件或未脱敏的用户路径。无论成功还是失败，都要给我完整结果和可直接复制给助教的反馈。
```
