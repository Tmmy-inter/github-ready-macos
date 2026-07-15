# GitHub Ready

GitHub Ready 是一个仅驻留在 macOS 菜单栏的本地 SwiftUI 工具，用于检查 GitHub CLI、Git、HTTPS 和 GitHub SSH-over-443 是否就绪。它不会在每次登录 macOS 时重新执行登录或修复：应用启动时只做静默、只读检查。

## 主要功能

- 绿色、蓝色、黄色、橙色、红色和灰色状态分类。
- 显示活动 GitHub 账户、由 `gh config get` 读取的首选协议、Git/`gh` 版本及双协议状态。
- 区分 DNS、TLS、网络/VPN、超时与明确的凭据拒绝。
- 检查 `ssh -G github.com` 的有效路由、`ssh-add -l` 的 agent 高层状态，并用严格 host-key 检查验证 GitHub SSH。
- 手动 `Check Again` 和活动协议感知的只读 `Test Connection`。
- 仅经用户点击和确认，在 HTTPS 与 SSH 间切换 GitHub CLI 的未来 clone/push 首选协议。
- 提供协议专用修复：HTTPS helper 修复；SSH 仅在必要时尝试用系统 `ssh-add` 重新加载 `id_ed25519`。
- 仅在用户点击并确认后启动 GitHub 浏览器登录。
- 隐私安全的有限本地日志与可复制诊断。
- 使用 `SMAppService.mainApp` 管理 Launch at Login；开发 bundle 中禁用该开关。

现有仓库 remote 与 GitHub CLI 首选协议是不同概念。协议切换不会改写任何现有 remote；本版本不提供账户切换、remote 迁移或 GitHub Enterprise 修复。

## 系统要求

- macOS 13 或更高版本。
- Swift 6 工具链。
- GitHub CLI 和 Git 建议通过 Homebrew 安装。
- 不需要管理员权限。

## 构建

```bash
cd ~/Projects/AI/Git_connection
./script/build_and_run.sh build
```

输出：

```text
dist/GitHub Ready.app
```

构建脚本会生成 `Info.plist`、执行 `plutil -lint` 并对开发 bundle 应用本地 ad-hoc 签名。

## 测试与验证

```bash
/usr/bin/xcrun swift test
/usr/bin/xcrun swift build
./script/build_and_run.sh verify
```

当前机器的 Command Line Tools 不完整地暴露了 XCTest/Swift Testing 运行时，因此 `Tests/GitHubReadyTests` 包含一个无第三方依赖的自包含测试 harness。它由 `swift test` 加载 test bundle 时执行，失败会使命令返回非零；命令输出会明确报告执行数量和失败数量。

## 运行

```bash
./script/build_and_run.sh run
```

应用同时提供主窗口与原生菜单栏入口。双击 Finder、Desktop 或 Dock 图标会打开主窗口；点击顶部 GitHub Ready 状态图标会在图标正下方弹出状态与操作面板，点击其他位置自动收起。正常启动不会打开 Terminal、浏览器或运行修复命令。

## 本地 MVP 直接启动

完成稳定安装后，可以直接双击桌面上的：

```text
~/Desktop/GitHub Ready
```

该入口是指向 `~/Applications/GitHub Ready.app` 的 macOS 原生 Alias，不会打开 Terminal，也不会复制第二份应用。它可像标准应用一样拖入 Dock；应用启动后，Dock 与顶部菜单栏都会显示 GitHub Ready 品牌图标。

菜单的主要操作区固定为每行三个等宽、等高的胶囊按钮，便于快速点击和扫描。

## 后续安装

本阶段不会自动安装。未来经过单独授权后，稳定位置为：

```text
~/Applications/GitHub Ready.app
```

只有从该路径运行时，Launch at Login 开关才可用。用户点击开关后，应用才调用 `SMAppService.mainApp.register()` 或 `unregister()`；启动过程只读取注册状态。

## 禁用 Launch at Login

从稳定安装位置启动应用，关闭菜单中的 `Launch at Login`。如果 macOS 显示需要审批，可在“系统设置 → 通用 → 登录项”中检查状态。

## 卸载

在确认 Launch at Login 已关闭后，退出应用并删除：

```text
~/Applications/GitHub Ready.app
```

如需删除应用生成的日志，可删除：

```text
~/Library/Logs/GitHubReady/
```

删除应用不会删除 GitHub CLI 登录、Git 配置或 macOS Keychain 凭据。

## 已知限制

- 仅支持 `github.com`，SSH Ready 路由要求 `ssh.github.com:443`、用户 `git` 和可用的 `id_ed25519`。
- 切换只影响 GitHub CLI 未来工作流的首选协议，不迁移现有仓库 remote。
- 不修复 GitHub Enterprise host。
- 不修改 `~/.ssh/config`、`known_hosts`、SSH key 或 Keychain；无交互加载失败时需要用户在应用外处理 key。
- 浏览器登录由 `gh auth login --web` 驱动；如果当前 GitHub CLI 版本要求终端式交互，应用会安全失败并显示脱敏错误，不会回退到 shell 或读取 PAT。
- 开发 bundle 不能作为永久 Login Item。
- 顶部状态项是固定的 GitHub Ready 品牌标记；具体健康状态在点击后打开的状态与操作面板中显示。

## 品牌图标与状态动效

项目内置用户提供的 `Sources/GitHubReady/Resources/GitHubReadyIcon.svg`。构建时会生成应用包使用的 `GitHubReadyIcon.icns`，因此 Finder、桌面启动链接和 `~/Applications` 中显示相同图标。

Finder 的 `.icns` 图标是静态资源。顶部状态项使用项目根目录中用户提供的 `GitHub-Ready-Icon-white.svg`：构建时转为应用包内的 `GitHubReadyStatusIcon.png`，以透明背景、白色分支和白色节点显示；它不使用黑色方形底或绿色。应用正在运行且状态为 Ready 时，主窗口顶部仍会为完整品牌图标的绿色节点显示柔和的呼吸灯动效。非 Ready 状态不会播放该动效。

如果把应用固定到 Dock，Force Quit 后图标会保留、运行指示点会消失，这是 macOS 的标准行为；未固定时，Dock 中的运行图标和顶部状态项都会随进程退出而消失。
