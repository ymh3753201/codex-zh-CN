# Codex Desktop 简体中文一键启用器 v0.2.0

## 适配版本

- 已在 Windows Codex Desktop 26.908.9136.0 上完成检查和隔离测试。

## 主要变化

- 改用新版 Codex 自带的 zh-CN 语言资源。
- 不再复制整套 Codex 应用。
- 不再修改 app.asar、Codex.exe 或 WindowsApps 权限。
- 不再要求用户安装 Node.js。
- 不再要求管理员权限。
- 支持完全离线运行。
- 新增新版插件中文名称和说明。
- 新增一键安装、恢复英文、检查状态三个入口。
- 旧文件 uninstall-codex.bat 现在只恢复英文，不会卸载 Codex。

## 验证结果

- 当前 Codex 安装包内含 64 组原生菜单语言资源。
- 当前 Codex 安装包内含 webview/assets/zh-CN-*.js。
- 当前主菜单使用新版多语言机制。
- 安装、状态检测、插件备份、恢复英文均通过临时目录隔离测试。

## 升级方法

删除旧工具文件夹，解压 v0.2.0，然后双击“一键汉化.bat”。不需要先卸载 Codex。
