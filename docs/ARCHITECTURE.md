# 架构

## 场景与状态所有权

`GitHubReadyApp` 创建一个 `MenuBarExtra` 和一个按需打开的详情窗口。应用使用 accessory activation policy，`Info.plist` 同时设置 `LSUIElement=true`。`AppStore` 是 `@MainActor` 的单一 UI 状态所有者；`HealthCheckService` 是 actor，负责异步健康检查和用户明确触发的操作。

应用代理在 `applicationDidFinishLaunching` 中只调用 `AppStore.refresh()`。启动路径没有登录、repair、Git 写入、Keychain 写入或 Login Item 写入。

## 分层

- `App/`：应用入口和启动生命周期。
- `Views/`：菜单栏弹出面板、状态行和详情窗口。
- `Models/`：命令结果、认证状态、协议、HTTPS helper、SSH route/agent/auth、菜单状态和操作结果。
- `Stores/`：主线程 UI 状态和用户操作编排。
- `Services/`：命令执行、认证解析、helper 解析、健康检查、日志、诊断和 Launch at Login。
- `Support/`：网络错误分类、状态分类、脱敏和稳定路径策略。

## CommandRunner

所有外部命令都使用 `Process.executableURL`、绝对路径和分离参数数组。runner 要求 executable 位于 allowlist，使用有限环境变量，排除 `GH_TOKEN` 等凭据覆盖变量，并设置输出总上限与超时。超时后依次发送 terminate、interrupt，最后才使用 `SIGKILL`。stdout/stderr 在进入模型前经过脱敏。

## 认证解析

主信号为：

```text
gh auth status --hostname github.com --json hosts
```

解析器不使用 JSON 命令的 exit code 判断认证有效性，而是校验 `github.com`、账户数组、唯一 active 账户、`state`、`login` 与 `gitProtocol`。如果状态不明确，会补充运行非 JSON `gh auth status`，仅用其脱敏错误区分明确凭据拒绝与 DNS/TLS/网络/超时。

没有明确拒绝信号时，网络或不确定失败保持橙色，不会显示红色。

## HTTPS helper 解析

应用分别读取 system/global unscoped helper，以及 `github.com`、`gist.github.com` 的 global URL-scoped helper。解析器保留空行，因为空 helper 是 Git 配置的继承 reset。有效配置允许 system `osxkeychain` 与 GitHub-scoped `gh auth git-credential` 共存，并验证 helper 中的 `gh` 路径等于当前 allowlist 解析出的可执行路径。

## 协议与 SSH 服务

活动协议只以 `gh config get git_protocol --host github.com` 为准，不从仓库 remote 推断。`SSHStatusService` 使用 `/usr/bin/ssh -G github.com` 解析有效 host、port、user、identity、`IdentitiesOnly`、`AddKeysToAgent` 和可用时的 `UseKeychain`，再用 `/usr/bin/ssh-add -l` 取得不含 fingerprint 的 agent 高层状态。

SSH 连接检查使用 `BatchMode=yes`、10 秒连接超时、一次尝试和 `StrictHostKeyChecking=yes`。`SSHConnectionParser` 识别 GitHub 成功文本；退出码 1 加成功文本是成功，不会把“does not provide shell access”误判为错误。已知账户存在时还会核对响应账户。

## 状态模型

- Green：活动 HTTPS 的认证/helper 正常，或活动 SSH 的 GitHub CLI 账户、443 route 和 GitHub SSH 认证均正常。
- Blue：检查中。
- Yellow：本地集成不完整，但认证没有确认失效。
- Orange：网络、DNS、TLS、VPN 或认证暂时无法确认。
- Red：无账户、无 active 账户或凭据明确被拒绝。
- Gray：GitHub CLI 缺失。

## 手动连接测试

活动 HTTPS 的手动测试运行：

```text
gh api --method GET user --silent
```

响应正文被抑制，只记录成功/失败、耗时和分类。

活动 SSH 的手动测试运行固定的 `/usr/bin/ssh -T` 参数数组。常规健康检查也执行只读 SSH 验证，从而让非活动 SSH fallback 在详情页保持可见；非活动协议的失败不会降低主状态。

## 协议切换与修复

菜单根据活动协议显示 `Use SSH` 或 `Use HTTPS`。确认对话框明确说明只改变 GitHub CLI 的未来 clone/push 首选项，不改写现有 remote。确认后才通过绝对 `gh` 路径和分离参数执行 `gh config set`，完成后重跑完整健康检查。启动与自动验证均不进入该写路径。

SSH 修复会先重检 route 与认证；健康状态直接返回 `No SSH repair required`。只有用户确认、route 正确、认证失败且 agent 为空、预期 key 文件存在时，才尝试 `/usr/bin/ssh-add --apple-use-keychain`。它不改 SSH config、known_hosts 或 Keychain 内容。

## Launch at Login

`LaunchAtLoginService` 映射 `SMAppService.mainApp.status`。稳定路径策略只允许 `~/Applications/GitHub Ready.app` 启用 toggle；`dist`、`.build` 和其他路径均禁用。register/unregister 仅从用户直接操作进入。
