# 安全模型

## 威胁边界

主要风险是命令注入、凭据输出、无限子进程、恶意或损坏的 CLI 输出、日志泄露、错误地重写健康配置以及把临时 bundle 注册为 Login Item。

## 凭据规则

- 不调用 `gh auth token` 或 `--show-token`。
- 不请求、接收或保存 PAT。
- 不读取 Keychain 内容。
- 不记录登录命令的原始输出。
- 不记录完整环境变量。
- 不把 token 环境变量传给子进程。
- 账户名只在本地 UI 必要位置显示，不进入安全诊断中的完整账户元数据。

## 命令 allowlist

应用只允许以下候选中的可执行文件：

- `/opt/homebrew/bin/gh`
- `/usr/local/bin/gh`
- `/usr/bin/gh`
- `/opt/homebrew/bin/git`
- `/usr/local/bin/git`
- `/usr/bin/git`
- `/usr/bin/ssh`
- `/usr/bin/ssh-add`
- 少量固定的 macOS 系统工具路径

不存在任意命令字符串、`sh -c`、`bash -c`、`zsh -c`、`eval` 或 `sudo`。

## 输出与日志

命令总输出默认限制为 256 KiB。日志限制为 512 KiB，并只保留一个轮转文件。日志只写入高层事件、命令名称、脱敏参数、exit status、耗时、超时状态和错误分类，不写原始 API/登录响应。

脱敏覆盖 GitHub token、Bearer/OAuth、Authorization/Cookie header、URL credentials、密码、passphrase、SSH fingerprint、generic secret、私钥/credential block 和长随机凭据样式字符串。复制诊断前再次执行完整脱敏。

## 超时与响应性

`CommandRunner` 在 detached task 中运行阻塞式 `Process` 管理，SwiftUI 主线程只等待 actor 返回。常规版本和配置查询使用 5 秒超时，认证和 API 使用 20 秒，repair 使用 30 秒，显式 browser login 使用最长 10 分钟。

## 浏览器登录边界

登录命令只在用户点击并确认后运行。有效账户已存在时会额外提示可能增加或替换 GitHub CLI 凭据。自动化验证不调用该路径。

## 只读启动保证

启动只执行版本、认证状态、活动协议、Git helper、SSH effective config/agent/只读连接和 `SMAppService` 状态读取。协议切换、repair、login 和 register/unregister 分别位于独立确认动作中，且开发 bundle 禁用 Launch at Login toggle。

SSH 使用系统二进制和非交互 `BatchMode`，不接收 passphrase，不显示或记录 key 内容、完整 public key、fingerprint 或原始 `ssh-add` 输出。严格 host-key 检查失败只给出可操作提示；应用不自动接受 host key，不修改 `known_hosts`，也不重写 `~/.ssh/config`。
