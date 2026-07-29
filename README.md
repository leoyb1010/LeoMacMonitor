# LeoMac监控器

LeoMac监控器是 Leo Yuan 面向 Apple Silicon Mac 打造的中文实时系统与 AI 工作负载监控工具。

## 当前版本

- 产品版本：2.0.0
- 应用名称：LeoMac监控器
- Bundle ID：`com.leoyuan.LeoMacMonitor`
- Widget ID：`com.leoyuan.LeoMacMonitor.Widget`
- 开发者与签名：Leo Yuan
- 系统要求：macOS 14 或更高版本

## 下载与安装

从 [GitHub Releases](https://github.com/leoyb1010/LeoMacMonitor/releases/latest) 下载最新的
`LeoMacMonitor-*.dmg`，打开后将“LeoMac监控器”拖入“应用程序”文件夹。

当前 2.0.0 构建使用 Leo Yuan 的 Apple Development 证书签名。由于尚未使用 Developer ID
完成 Apple 公证，首次在其他 Mac 打开时可能需要在 Finder 中右键应用并选择“打开”。

## 核心能力

- CPU、GPU、内存、内存带宽实时监控
- AI 工作负载、神经网络引擎与媒体引擎状态
- CPU、GPU、内存温度及风扇转速
- 网络与磁盘实时速率和历史曲线
- 进程级磁盘读写排行、内置/外置物理磁盘拆分
- SMART/NVMe 温度、寿命、累计写入与介质错误健康信息
- 本地 AI 运行时识别与进程监控
- 适配小尺寸副屏的 90%–250% 界面缩放
- 跟随系统的深色、浅色外观
- 独立大字号、长面板和二级折叠详情的菜单栏监控中心
- 八模块双面仪表卡：数据面保持高密度读数，动效面显示数据驱动的大型实时图形
- CPU 核心反应堆、GPU 粒子星云、内存液位、带宽数据通道、AI 引擎星图、热力等高线、网络双向波与磁盘 I/O 涡轮八种独立视觉
- 支持单卡翻转，以及数据、动效、混合三种全局查看模式；翻转不改变 4×2 网格尺寸
- 数值、条形、状态切换和录制回放采用统一的低延迟动效规范
- 支持“减少动态效果”，窗口失焦时暂停持续动效
- macOS WidgetKit 桌面组件

## 本机构建

```bash
swift test
SIGN_ID="1082E6E97B4ADD052348041B0E960C25B7E0C370" scripts/build-app.sh 2.0.0
```

构建产物使用 `LeoMacMonitor` 可执行文件名和 `LeoMac监控器.app` 应用名称。
为避免 Documents/iCloud/FileProvider 在构建后给 Widget 添加 FinderInfo 并破坏签名，单独构建的
应用默认写入 `~/Library/Caches/LeoMacMonitor/dist`；DMG 仍输出到仓库的 `dist` 目录。

生成带“应用程序”快捷方式和 SHA-256 校验文件的 DMG：

```bash
SIGN_ID="1082E6E97B4ADD052348041B0E960C25B7E0C370" scripts/build-dmg.sh 2.0.0
```

## 许可证

本项目包含基于 MIT 许可证使用和修改的代码。依法需要保留的版权与许可内容见 [LICENSE](LICENSE)。
