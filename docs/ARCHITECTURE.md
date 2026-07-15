# Architecture

## Scenes and state ownership

`GitHubReadyApp` creates a regular `WindowGroup` for the main desktop window and an on-demand details window. `AppDelegate` uses the regular activation policy and bridges a native `NSStatusItem` to an `NSPopover` containing the SwiftUI status/action view. `AppStore` is the single `@MainActor` UI state owner; `HealthCheckService` is an actor responsible for asynchronous health checks and explicitly user-triggered operations.

During `applicationDidFinishLaunching`, the app delegate only starts `AppStore.refresh()`. Startup does not log in, repair, write Git configuration, write Keychain data, or register a Login Item.

## Layers

- `App/`: application entry point and launch lifecycle.
- `Views/`: status-bar popover, status rows, main window, and details window.
- `Models/`: command results, authentication, protocol, HTTPS helper, SSH route/agent/auth, menu state, and action results.
- `Stores/`: main-thread UI state and orchestration of user actions.
- `Services/`: command execution, authentication parsing, helper parsing, health checks, logging, diagnostics, and Launch at Login.
- `Support/`: network error classification, status classification, redaction, and stable-path policy.

## CommandRunner

All external commands use `Process.executableURL`, absolute paths, and separated argument arrays. The runner requires the executable to be in an allowlist, uses a constrained environment, excludes credential override variables such as `GH_TOKEN`, and enforces output and timeout limits. On timeout it sends terminate, interrupt, and finally `SIGKILL` in sequence. stdout/stderr is redacted before it reaches the app state or diagnostics.

## Authentication parsing

The primary signal is:

```text
gh auth status --hostname github.com --json hosts
```

The parser does not use the JSON command's exit code as the authentication decision. It validates `github.com`, the account array, the unique active account, `state`, `login`, and `gitProtocol`. If the state is ambiguous, it runs non-JSON `gh auth status` and uses only redacted errors to distinguish explicit credential rejection from DNS, TLS, network, or timeout failures.

When there is no explicit rejection signal, network or indeterminate failures remain orange rather than being shown as red.

## HTTPS helper parsing

The app reads system/global unscoped helpers and the global URL-scoped helpers for `github.com` and `gist.github.com`. Empty lines are preserved because an empty helper resets inherited Git configuration. Valid configuration allows system `osxkeychain` to coexist with the GitHub-scoped `gh auth git-credential` helper and verifies that the helper's `gh` path matches the executable path resolved by the current allowlist.

## Protocol and SSH services

The active protocol comes only from `gh config get git_protocol --host github.com`; it is not inferred from repository remotes. `SSHStatusService` uses `/usr/bin/ssh -G github.com` to parse the effective host, port, user, identity, `IdentitiesOnly`, `AddKeysToAgent`, and available `UseKeychain` values, then uses `/usr/bin/ssh-add -l` for high-level agent state without exposing fingerprints.

SSH connection checks use `BatchMode=yes`, a 10-second connection timeout, one attempt, and `StrictHostKeyChecking=yes`. `SSHConnectionParser` recognizes GitHub's successful response; exit code 1 with the success text is treated as success, and “does not provide shell access” is not treated as an error. When a known account exists, the response account is also checked.

## Status model

- Green: the active HTTPS authentication/helper is healthy, or the active SSH account, port-443 route, and GitHub SSH authentication are healthy.
- Blue: a check is running.
- Yellow: local integration is incomplete but authentication has not been confirmed invalid.
- Orange: network, DNS, TLS, VPN, or authentication cannot currently be confirmed.
- Red: no account, no active account, or explicit credential rejection.
- Gray: GitHub CLI is missing.

## Manual connection tests

The active HTTPS test runs:

```text
gh api --method GET user --silent
```

The response body is suppressed; only success/failure, duration, and classification are recorded.

The active SSH test uses a fixed `/usr/bin/ssh -T` argument array. Regular health checks also perform read-only SSH verification so that an inactive SSH fallback remains visible in Details; failure of an inactive protocol does not downgrade the primary state.

## Protocol switching and repair

The menu displays `Use SSH` or `Use HTTPS` based on the active protocol. The confirmation dialog explains that the action changes only GitHub CLI's future clone/push preference and does not rewrite existing remotes. Only after confirmation does the app execute `gh config set` through the absolute `gh` path and separated arguments, then rerun the complete health check. Startup and automatic verification never enter this write path.

SSH repair rechecks the route and authentication first; a healthy state returns `No SSH repair required`. Only after user confirmation, with a correct route, failed authentication, an empty agent, and an existing expected key file, does the app attempt `/usr/bin/ssh-add --apple-use-keychain`. It does not modify SSH config, `known_hosts`, or Keychain contents.

## Launch at Login

`LaunchAtLoginService` maps `SMAppService.mainApp.status`. The stable-path policy allows the toggle only for `~/Applications/GitHub Ready.app`; `dist`, `.build`, and other paths disable it. Register/unregister can only be reached through a direct user action.
