# LeoMac监控器

LeoMac监控器是 Leo Yuan 面向 Apple Silicon Mac 打造的中文实时系统与 AI 工作负载监控工具。

## 当前版本

- 产品版本：1.0.0
- 应用名称：LeoMac监控器
- Bundle ID：`com.leoyuan.LeoMacMonitor`
- Widget ID：`com.leoyuan.LeoMacMonitor.Widget`
- 开发者与签名：Leo Yuan
- 系统要求：macOS 14 或更高版本

## 下载与安装

从 [GitHub Releases](https://github.com/leoyb1010/LeoMacMonitor/releases/latest) 下载最新的
`LeoMacMonitor-*.dmg`，打开后将“LeoMac监控器”拖入“应用程序”文件夹。

当前 1.0.0 构建使用 Leo Yuan 的 Apple Development 证书签名。由于尚未使用 Developer ID
完成 Apple 公证，首次在其他 Mac 打开时可能需要在 Finder 中右键应用并选择“打开”。

## 核心能力

- CPU、GPU、内存、内存带宽实时监控
- AI 工作负载、神经网络引擎与媒体引擎状态
- CPU、GPU、内存温度及风扇转速
- 网络与磁盘实时速率和历史曲线
- 本地 AI 运行时识别与进程监控
- 适配小尺寸副屏的 90%–250% 界面缩放
- 跟随系统的深色、浅色外观
- 独立字号的菜单栏监控面板
- macOS WidgetKit 桌面组件

## 本机构建

```bash
swift test
SIGN_ID="Apple Development: leo yuan (54UB8X9C5F)" scripts/build-app.sh 1.0.0
```

构建产物使用 `LeoMacMonitor` 可执行文件名和 `LeoMac监控器.app` 应用名称。

生成带“应用程序”快捷方式和 SHA-256 校验文件的 DMG：

```bash
SIGN_ID="Apple Development: leo yuan (54UB8X9C5F)" scripts/build-dmg.sh 1.0.0
```

## 许可证

本项目包含基于 MIT 许可证使用和修改的代码。依法需要保留的版权与许可内容见 [LICENSE](LICENSE)。
