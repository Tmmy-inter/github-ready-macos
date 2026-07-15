# Test Plan

## Automated unit tests

`swift test` loads the `GitHubReadyTests` test bundle. Because the current Command Line Tools do not expose a test-discovery runtime reliably, the test directory provides a self-contained harness with no third-party dependencies. The bundle runs the complete suite during initialization, prints the test name on failure, and exits non-zero.

Coverage includes:

- Command success, timeout, missing executable, allowlist, and output limits.
- Valid/invalid authentication JSON, missing host, multiple accounts, no active account, missing fields, malformed JSON, fatal errors, and network failures.
- System/global/scoped helpers, empty resets, `osxkeychain` coexistence, duplicates, missing and malformed helpers, and Homebrew path moves.
- DNS, TLS/network, VPN, timeout, and credential-rejection classification.
- Every menu-state classification.
- Redaction of tokens, headers, URL credentials, passwords, cookies, private-key blocks, and mixed output.
- A second redaction pass for security diagnostics.
- `dist`, `.build`, stable installation, unknown paths, and paths containing spaces.
- Launch at Login status mapping.
- HTTPS/SSH/unknown protocol parsing, confirmation gates, and exact switch arguments.
- Active-protocol primary state and the rule that an inactive protocol cannot downgrade it.
- `ssh -G` host/443/user/identity parsing and missing identities.
- SSH agent loaded/empty/unavailable states.
- GitHub SSH exit-code-1 success, account mismatch, publickey rejection, DNS, timeout, refused, VPN/proxy, host-key, and interaction-required cases.
- SSH output limits, fingerprint redaction, and security diagnostics.

All credential fixtures are fictional. Automated tests do not access GitHub or modify protocol, Git, SSH, Keychain, Login Item, or remote state.

## Build and bundle integration verification

```bash
/usr/bin/xcrun swift build
./script/build_and_run.sh build
/usr/bin/plutil -lint "dist/GitHub Ready.app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "dist/GitHub Ready.app"
```

## Manual smoke test

- Launch once from `dist`.
- Confirm the process and status-bar item appear.
- Confirm that no Dock icon, Terminal, or browser login is opened unexpectedly.
- Confirm that the active protocol is classified as Ready and the other protocol is shown independently in Details.
- Confirm that the protocol switch button is visible; automation does not click it.
- Confirm that development paths disable Launch at Login.
- Confirm that the app remains responsive and exits normally.

## Explicitly not run

The following paths modify machine configuration. This plan checks their code and UI guards but does not execute them:

- `gh auth setup-git`
- `gh auth login`
- `gh config set git_protocol ...`
- `/usr/bin/ssh-add --apple-use-keychain ...`
- `SMAppService.register()` / `unregister()`
- Installation into `~/Applications`
- Git/SSH/Keychain/remote writes
