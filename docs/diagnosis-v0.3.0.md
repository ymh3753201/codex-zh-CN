# v0.3.0 系统排查记录

## 结论与证据等级

**已经复现的故障机制：** 官方应用 `26.908.70816` 的主界面受 Statsig layer `72216192` 中的 `enable_i18n` 控制。它决定是否读取翻译词条；`localeOverride = "zh-CN"` 只决定语言选择。开关为 false 时，语言已经是 zh-CN，但界面拿不到中文 messages，仍显示默认英文。

证据来自本机官方安装包 `webview/assets/app-initial-bcc2ff475eb6.js` 的 `VJo` 组件。其 effect 在开关为 true 时才调用 `L4a` 读取翻译文件，传入国际化组件的 messages 同样受该开关控制。语言选择器 `general-settings-8c04e051bca2.js` 的显示也受此开关控制。

`tests/test-locale-gate.py` 从实际安装包提取整个组件，在受控的 React hooks 环境中执行，并非重新写一份开关判断进行自证。固定输入为：明确选择 zh-CN、系统及 IDE 为 en-US、远程翻译开关 false。

| 条件 | 实际结果 |
| --- | --- |
| 原始官方组件 | locale = zh-CN，messages 未加载 |
| 经过兼容补丁的同一组件 | locale = zh-CN，messages 加载成功 |

**不能确认的部分：** 未取得失败 Windows 10 设备的运行日志、实际配置目录和开关值。因此不能声称已经在那台设备上证实唯一根因，也不能声称已经完成 Windows 10 实机验证。

## 排除错误推断

同一安装包中同时存在以下版本信息：

- AppxManifest.xml：`26.908.9136.0`；
- app.asar / package.json：`26.908.70816`；
- ChatGPT.exe 外壳文件：`152.0.7977.83`。

所以截图中的两个版本号不是“安装了两个 Codex”的充分证据。当前 Manifest 的最低 Windows 版本为 `10.0.19041.0`；旧代码中“低于 19045 会导致语言设置不稳定”的说明没有相应证据，已移除。

微软文档说明 MSIX 文件虚拟化主要涉及 AppData，不能据此直接推断用户目录下的 `.codex` 一定被重定向。见 [MSIX 运行方式](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)。

## 其他已修复的问题

1. 原安装器忽略 CODEX_HOME，固定写 USERPROFILE 下的 .codex。
2. 原安装器在没有核实目标进程启动时打印“已重新启动”。
3. 原停止逻辑按 ChatGPT/Codex 名称全局关闭进程，可能影响独立 ChatGPT 或命令行任务。
4. 原配置编辑把多行文本中的 [desktop] 当成真正段落，没有正确处理数组段落边界。
5. 插件 supported 计数存在重复累加。
6. 原测试只验证配置文本，没有执行实际界面语言加载逻辑。
7. 实际启动测试发现 OWL 外壳可能先按默认用户目录把启动转交现有实例，仅设置 Electron 环境变量不足。兼容启动同时指定 `--user-data-dir` 与 `CODEX_ELECTRON_USER_DATA_PATH`，避免原窗口接管。

## 修复结构

- 仅修改用户目录中的完整程序副本。
- 两处开关替换为同长度的 true 表达式，不改变文件偏移、资源大小或其他业务开关。
- 更新修改资源的 SHA256 和分块 SHA256；若可执行文件含经典 Electron ASAR 哈希，同步更新。不存在该字段的当前 OWL 构建不修改可执行文件。
- 识别不唯一、资源结构不匹配或完整性不一致时停止，不发布未完成副本。
- 配置仍使用 Codex 官方的 desktop.localeOverride；兼容副本使用独立界面缓存和原 Codex 数据目录。
- 同源同工具版本复用副本前核对 ASAR 和启动程序哈希；官方更新后重新生成副本。

上游 [xqnode/codex-zh-CN](https://github.com/xqnode/codex-zh-CN) 也采用用户目录副本绕开 WindowsApps 原地写入。本次重写为无需 Node.js 的离线实现，不复用旧版本对主程序硬编码文本的宽泛替换。

## 测试及限制

- Windows PowerShell 5.1：配置、备份、重复安装、恢复插件、插件原文变化、拒绝不支持安装包。
- 实际界面组件：远程开关关闭时，修复前失败、修复后加载中文。
- 实际 ASAR：长度及偏移不变；修改资源、分块和模拟可执行文件头校验正确；其他 webview assets 字节不变；官方原 ASAR 哈希不变。
- 进程边界：其他安装目录、同名前缀目录、其他会话不匹配；停止失败及启动无目标进程均不能报成功。
- 实际程序副本：隔离数据目录和界面缓存启动，检查进程持续运行及语言配置不被覆盖。这是启动测试，不等于对全部页面逐项视觉验收。
- 发布 ZIP：从解压后的脚本重复执行配置及恢复测试；检查 PowerShell UTF-8 BOM、发布内容、版本一致性。

不包含 Windows 10 虚拟机或实机、所有便携版本、所有未来 Codex 更新的验证。下一步是在原故障设备解压新包复测，并保留“检查状态”生成的报告。
