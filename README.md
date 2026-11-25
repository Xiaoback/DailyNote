# 今日便笺 · DailyNote

本机保存的 macOS 便笺。将鼠标移到屏幕右上角，停留约 0.4 秒，即可展开右侧编辑面板。鼠标移入便笺时保持显示，移出后自动保存并收起。

## 下载与安装

在本仓库的 Releases 中下载 `DailyNote-0.1.0-beta.1-universal.dmg`。打开磁盘映像，将 DailyNote 拖到 Applications，再从“应用程序”启动。

支持 macOS 14 或更新版本，安装包同时包含 Apple Silicon 与 Intel 架构。目前已在 Apple Silicon Mac 上测试。Intel 架构已编译，实机兼容性需要进一步验证。

这是未经 Apple 公证、采用临时签名的测试版。首次打开可能被 macOS 阻止。如果你确认下载来源可信，可按照苹果说明，在“系统设置 → 隐私与安全性”中为此应用选择“仍要打开”。部分受管理的电脑可能限制安装。

苹果说明 https://support.apple.com/zh-cn/102445

下载后可执行 `shasum -a 256`，与 Release 中的 `SHA256SUMS.txt` 比对。

## 使用

- 启动后可直接编辑右侧面板，支持霞鹜文楷、加粗、斜体、高亮及文字大小调整。
- 待办支持未完成、完成和取消。Tab 增加缩进，Shift+Tab 减少缩进。前一项目需具备可承接的父层级。
- 孙项目及更深层级使用方形标记，各层级支持折叠。子待办全部完成后，父待办自动完成。
- 在层级菜单的“管理每日模板…”中创建、编辑模板，也可从当前便笺生成模板。
- 日期按钮可以查看历史便笺，或为未来日期创建计划。
- 应用运行期间，右上角触发可用。应用菜单中的“右上角触发便笺”可以关闭或开启。
- 退出应用使用 ⌘Q。再次使用时从 Applications 启动。

此公开版使用应用内触发角，未注册系统设置中的“触发角”动作。便笺面板支持直接编辑。

## 数据

便笺、模板、外观和自动备份保存在本机 `~/Library/Application Support/DailyNote/`。请在删除此目录前导出或备份数据。

右上角“…”菜单提供便笺导出和备份导入功能。此版本通过手动导入备份迁移旧版内容。便笺数据仅保存在本机。

## 从源码构建

需要完整 Xcode 和命令行工具。首次构建会从霞鹜文楷的官方固定版本下载字体并校验 SHA-256，需要联网。此构建路径使用临时签名。

```bash
bash Scripts/build-standalone.sh
open build/standalone/DailyNote.app
```

输出为通用架构应用，最低目标系统为 macOS 14。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/check.sh
```

检查在临时目录中运行。界面测试会暂时显示示例窗口。

## 许可与反馈

应用源码和项目图标采用 MIT 许可证，见 LICENSE。内置霞鹜文楷使用 SIL Open Font License 1.1，字体许可及来源见 `Resources/Fonts/`。

请在 GitHub Issues 中提供系统版本、Mac 芯片类型及复现步骤。
