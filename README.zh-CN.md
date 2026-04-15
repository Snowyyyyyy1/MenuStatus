<p align="center">
  <img src="Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" width="128" alt="MenuStatus app icon">
</p>

# MenuStatus

<p align="center">
  <a href="./README.md">English</a> · <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/Snowyyyyyy1/MenuStatus/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/Snowyyyyyy1/MenuStatus?display_name=tag"></a>
  <a href="./LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg"></a>
  <img alt="Platform macOS 14+" src="https://img.shields.io/badge/platform-macOS%2014%2B-black">
</p>

一个原生的 macOS 菜单栏应用，用来查看两类受支持的公开状态页，以及内置的 AI 基准快照视图。

MenuStatus 主要有两个视图：

- **状态页视图**：解析基于 **[Atlassian Statuspage](https://www.atlassian.com/software/statuspage)** 和 **[incident.io](https://incident.io/status-pages)** 的公开状态页
- **[AI Stupid Level](https://www.aistupidlevel.info/) 视图**：查看 global index、模型排行、厂商对比、recommendations、alerts 和 degradations

<p align="center">
  <a href="https://github.com/Snowyyyyyy1/MenuStatus/releases/latest">下载最新 DMG</a> ·
  <a href="https://github.com/Snowyyyyyy1/MenuStatus/releases">版本说明</a> ·
  <a href="#从源码构建">从源码构建</a>
</p>

## 截图

<p align="center">
  <img src="docs/assets/readme/gallery/01-status-1password.png" width="32%" alt="1Password 状态页总览">
  <img src="docs/assets/readme/gallery/02-status-1password-hover.png" width="32%" alt="1Password 状态页 hover 详情">
  <img src="docs/assets/readme/gallery/03-status-claude.png" width="32%" alt="Claude 状态页总览">
</p>

<p align="center">
  <img src="docs/assets/readme/gallery/04-benchmark-ranking.png" width="32%" alt="AI Stupid Level 排行总览">
  <img src="docs/assets/readme/gallery/05-benchmark-panels.png" width="32%" alt="AI Stupid Level 厂商对比与推荐面板">
  <img src="docs/assets/readme/gallery/06-benchmark-hover.png" width="32%" alt="AI Stupid Level hover 详情卡片">
</p>

## 它能做什么

### 状态页视图

MenuStatus 不是一个可以解析任意网站的通用状态监控器。目前只支持两种状态页平台：

- **[Atlassian Statuspage](https://www.atlassian.com/software/statuspage)**
- **[incident.io](https://incident.io/status-pages)**

内置 provider 包括 **OpenAI** 和 **Anthropic**。你也可以添加其他兼容的状态页 URL，例如 GitHub、Cloudflare、1Password、Proton 等，只要它们使用的是这两种格式。

在菜单栏中你可以：

- 快速切换不同 provider
- 查看分组组件和 uptime bar
- 查看当前 incident 和近期历史
- 一键打开官方状态页查看更多上下文

### AI Stupid Level 视图

MenuStatus 也内置了一个 **[AI Stupid Level](https://www.aistupidlevel.info/)** 视图，用于查看来自 [`aistupidlevel.info`](https://www.aistupidlevel.info/) 的 AI 基准快照。

它会展示：

- global index 与趋势
- 模型排行
- 厂商对比
- recommendations
- alerts
- degradations

也就是说，这个应用除了服务状态页之外，还多了一条工作流：快速判断模型质量和稳定性是不是在下滑。

## 支持范围

| 类别 | 支持内容 |
| --- | --- |
| 状态页 | Atlassian Statuspage、incident.io |
| 内置 provider | OpenAI、Anthropic |
| 自定义 provider | 使用上述两种格式的兼容 URL |
| AI 基准视图 | AI Stupid Level |

## 兼容性

### 支持

- Atlassian Statuspage 页面
- incident.io 页面
- 内置 OpenAI 和 Anthropic provider
- 使用相同两种格式的兼容自定义 URL

### 不支持

- 这两种格式之外的任意自定义状态网站
- 没有兼容 Atlassian Statuspage / incident.io 结构的完全自定义状态页

## 下载

- 最新版本发布在 [GitHub Releases](https://github.com/Snowyyyyyy1/MenuStatus/releases/latest)
- 需要 **macOS 14.0+**
- 仓库内置了 GitHub Actions 发布流，可以自动构建 Release `.app`、打包 `.dmg` 并上传到 Releases
- 当签名和公证配置完成后，也可以配合 Sparkle 和 GitHub Pages appcast 做应用内更新

如果 Apple 签名 / 公证 secrets 还没配好，workflow 仍然可以先发布未签名的 `.dmg`，这样发布链路仍然能先跑通。

## 隐私

MenuStatus 只读取公开 HTTPS 状态接口和公开 AI 基准数据。不需要 API key、不需要账号，也不做核心功能相关的遥测。

## 从源码构建

### 环境要求

- macOS 14.0+
- Xcode 15+ command line tools
- [Tuist](https://tuist.io)

### 本地运行

```bash
./run-menubar.sh
```

停止运行：

```bash
./stop-menubar.sh
```

### 开发命令

```bash
# 生成 Xcode 项目
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

# 构建
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme MenuStatus -configuration Debug -derivedDataPath .build

# 测试
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

### 发布 DMG

推一个版本 tag，GitHub Actions 就会自动构建 Release `.app`、打包 `.dmg` 并上传到 GitHub Releases：

```bash
git tag v0.1.0
git push origin v0.1.0
```

workflow 定义在 `.github/workflows/release.yml`，打包脚本使用 [`package-app.sh`](./package-app.sh)。

默认使用 `hdiutil`，这样在 CI 里更稳定。如果你想在本地生成带 Finder 布局的样式化 DMG，并且已经安装了 [`create-dmg`](https://github.com/create-dmg/create-dmg)，可以运行 `USE_CREATE_DMG=1 ./package-app.sh 0.1.0`。

可选的 GitHub repository secrets（用于签名 / 公证）：

- `APPLE_CERTIFICATE_P12_BASE64`：Base64 编码的 Developer ID Application 证书（`.p12`）
- `APPLE_CERTIFICATE_PASSWORD`：该 `.p12` 的密码
- `APPLE_SIGNING_IDENTITY`：签名身份，例如 `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`：用于公证的 Apple ID 邮箱
- `APPLE_APP_SPECIFIC_PASSWORD`：对应 Apple ID 的 app-specific password
- `APPLE_TEAM_ID`：Apple Developer team ID

## 架构

```text
ProviderConfigStore ──providers──► StatusStore ──@Observable──► SwiftUI Views
                                       │
StatusClient ──fetch & parse───────────┘
                                       │
                                  SettingsStore
                                  (UserDefaults)

AIStupidLevelClient ──fetch──────────► AIStupidLevelStore ──@Observable──► AIStupidLevelPageView
```

| 层 | 职责 |
|-------|----------------|
| **Status Models** (`StatusModels.swift`) | Provider 配置、incident、组件 uptime、展示模型 |
| **Provider Config** (`ProviderConfigStore.swift`) | 运行时 provider 列表、持久化、自动识别 |
| **Status Client** (`StatusClient.swift`) | Atlassian Statuspage / incident.io 的网络请求与 HTML 解析 |
| **Status Store** (`StatusStore.swift`) | 可观察状态、轮询、历史推导、分组 section |
| **AI Stupid Level Client** (`AIStupidLevelClient.swift`) | benchmark、alerts、recommendations、degradations 和模型详情请求 |
| **AI Stupid Level Store** (`AIStupidLevelStore.swift`) | benchmark 可观察状态、缓存、轮询和 hover 预取 |
| **Views** | MenuBarExtra、provider tabs、uptime rows、benchmark 面板、设置页 |

生成的 `.xcodeproj` / `.xcworkspace` 和构建产物（`.build/`、`Derived/`）都已在 gitignore 中忽略。

## 许可证

本项目使用 [AGPL-3.0](./LICENSE) 许可证。
