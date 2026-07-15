# 测试计划

## 自动化单元测试

`swift test` 加载 `GitHubReadyTests` test bundle。由于当前 Command Line Tools 缺少可正常发现测试的 XCTest/Swift Testing 运行时，测试目录提供一个无第三方依赖的自包含 harness；bundle 初始化时执行全部测试，失败会输出测试名并以非零状态终止。

覆盖范围：

- 命令成功、timeout、可执行文件缺失、allowlist、输出上限。
- 有效/无效认证 JSON、缺 host、多账户、无 active、缺字段、畸形 JSON、fatal error 和网络失败。
- system/global/scoped helper、空 reset、`osxkeychain` 共存、重复、缺失、畸形和 Homebrew 路径移动。
- DNS、TLS/网络、VPN、timeout 与认证拒绝分类。
- 所有菜单状态分类。
- token、header、URL credentials、密码、cookie、私钥 block 和混合输出脱敏。
- 安全诊断二次脱敏。
- `dist`、`.build`、稳定安装路径、未知路径和空格路径。
- Launch at Login 状态映射。
- HTTPS/SSH/unknown 协议解析、确认门和精确切换参数。
- 活动协议主状态与非活动协议不降级规则。
- `ssh -G` host/443/user/identity 解析及缺失 identity。
- SSH agent loaded/empty/unavailable。
- GitHub SSH 退出码 1 成功、账户不匹配、publickey 拒绝、DNS、timeout、refused、VPN/proxy、host-key 和交互需求。
- SSH 输出上限、fingerprint 脱敏和安全诊断。

所有凭据 fixture 均为虚构值；自动化测试不访问 GitHub，不修改协议、Git、SSH、Keychain、Login Item 或 remote。

## 构建和 bundle 集成验证

```bash
/usr/bin/xcrun swift build
./script/build_and_run.sh build
/usr/bin/plutil -lint "dist/GitHub Ready.app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "dist/GitHub Ready.app"
```

## 手动烟测

- 从 `dist` 启动一次。
- 确认进程和菜单栏项目出现。
- 确认无 Dock 图标、Terminal 或 browser login。
- 确认当前活动协议被判为 Ready，另一协议在详情中独立显示。
- 确认协议切换按钮可见，但自动化不点击。
- 确认开发路径禁用 Launch at Login。
- 确认应用可响应并正常退出。

## 明确不运行

以下路径会修改机器配置，本阶段只检查代码和 UI guard，不实际运行：

- `gh auth setup-git`
- `gh auth login`
- `gh config set git_protocol ...`
- `/usr/bin/ssh-add --apple-use-keychain ...`
- `SMAppService.register()` / `unregister()`
- 安装到 `~/Applications`
- Git/SSH/Keychain/remote 写入
