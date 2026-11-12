# JenkinsMonitor

原生 macOS Jenkins 监控工具（Swift + SwiftUI）。用于连接 Jenkins 实例、浏览任务与构建状态，并在菜单栏快速查看整体健康情况。

- **最低系统版本**：macOS 14.0+
- **Bundle ID**：`com.lieryang.JenkinsMonitor`
- **依赖**：无第三方 Swift 包，仅使用系统框架（SwiftUI / Foundation / Security / AppKit）

## 用 Xcode 打开并运行

1. 在 Mac 上安装 [Xcode 16+](https://developer.apple.com/xcode/)（需包含 macOS SDK）。
2. 打开工程文件：

   ```bash
   open JenkinsMonitor/JenkinsMonitor.xcodeproj
   ```

3. 在 Xcode 顶部选择 Scheme **Jenkins Monitor**，目标设备选择 **My Mac**。
4. 按 `⌘R` 运行。首次运行若提示签名，在 *Signing & Capabilities* 中选择你的 Team 即可（个人免费账号亦可本地运行）。

### 没有真实 Jenkins 时

首次启动会进入「添加实例」引导页。可点击 **先用样例数据体验界面**，应用会使用内置 Mock 数据展示任务列表、构建详情与菜单栏状态，无需网络。

## 创建 Jenkins API Token

1. 登录 Jenkins，点击右上角用户名 → **设置**（Configure）。
2. 找到 **API Token** 区域，点击 **Add new Token**。
3. 为 Token 命名（例如 `Jenkins Monitor`），生成后**立刻复制**（离开页面后无法再查看完整 Token）。
4. 在本应用中填写：
   - **实例地址**：Jenkins 根地址，例如 `https://jenkins.example.com`（不要漏协议）
   - **用户名**：你的 Jenkins 用户名
   - **API Token**：上一步复制的令牌

> API Token 仅保存在 macOS **钥匙串（Keychain）** 中，不会以明文写入 UserDefaults 或本地文件。

## 功能概览（v1）

| 能力 | 说明 |
| --- | --- |
| 实例配置 | 引导页 / 设置中添加实例；支持多台实例切换 |
| 安全存储 | 用户名与地址存 UserDefaults，API Token 存 Keychain |
| Jenkins API | 标准 Remote Access API；Basic Auth；缓存 CSRF Crumb 供后续写操作 |
| 任务监控 | 侧边栏任务列表（含文件夹展开）、状态徽章、最近构建时间 |
| 构建详情 | 状态 / 时间 / 耗时，一键在浏览器打开构建或任务页 |
| 自动刷新 | 默认每 30 秒刷新（设置中可调 10–300 秒）；支持 `⌘R` 手动刷新 |
| 菜单栏 | Menu Bar Extra 显示总体状态与异常任务快捷入口 |

## 工程结构

```
JenkinsMonitor/
├── JenkinsMonitor.xcodeproj          # Xcode 工程
└── JenkinsMonitor/
    ├── JenkinsMonitorApp.swift       # 应用入口（窗口 + 菜单栏）
    ├── Models/                       # 领域模型
    ├── Networking/                   # API 协议、DTO、Live/Mock 客户端
    ├── Persistence/                  # Keychain 与实例配置存储
    ├── Services/                     # 环境注入与监控 ViewModel
    ├── Views/                        # SwiftUI 界面（引导 / 列表 / 详情 / 设置）
    └── PreviewContent/               # 预览与样例数据
```

架构要点：

- `JenkinsAPIClient` 协议隔离网络实现，SwiftUI Preview 与样例模式使用 `MockJenkinsAPIClient`。
- `LiveJenkinsAPIClient` 负责真实请求：实例信息、任务列表（含文件夹）、构建列表与单次构建详情。
- 后续可在此基础上扩展：通知、构建日志流、触发构建（已预留 Crumb 刷新）。

## 权限与网络安全说明

- 启用 App Sandbox，并允许出站网络（`com.apple.security.network.client`）。
- `Info.plist` 中允许任意/本地 HTTP 负载，以便连接内网或自签名场景下的 Jenkins；生产环境建议优先使用 HTTPS。

## 许可证

按个人项目自行使用与修改。

应用图标基于 [Jenkins 官方标识](https://get.jenkins.io/art/jenkins-logo/) 二次创作，遵循 [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) 许可。
