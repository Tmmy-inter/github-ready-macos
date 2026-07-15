# GitHub Ready

GitHub Ready is a local SwiftUI macOS utility with a regular desktop window and a native status-bar popover. It checks whether GitHub CLI, Git, HTTPS, and GitHub SSH-over-443 are ready. Startup performs only a silent, read-only check; it does not automatically log in or repair configuration.

## Features

- Green, blue, yellow, orange, red, and gray health states.
- Active GitHub account, the preferred protocol from `gh config get`, Git/`gh` versions, and both protocol states.
- Separate classification for DNS, TLS, network/VPN, timeout, and explicit credential rejection.
- Effective `ssh -G github.com` routing, high-level `ssh-add -l` agent state, and GitHub SSH validation with strict host-key checking.
- Manual `Check Again` and a read-only `Test Connection` for the active protocol.
- User-confirmed switching of GitHub CLI's future clone/push preference between HTTPS and SSH.
- Protocol-specific repair: HTTPS helper repair; SSH only attempts to reload `id_ed25519` with the system `ssh-add` when necessary.
- Browser login starts only after an explicit user confirmation.
- Privacy-conscious local logs and copyable diagnostics.
- `SMAppService.mainApp` support for Launch at Login; development bundles keep this toggle disabled.

The repository remote and GitHub CLI's preferred protocol are separate concepts. Switching the protocol does not rewrite existing remotes. This version does not provide account switching, remote migration, or GitHub Enterprise repair.

## Requirements

- macOS 13 or later.
- Swift 6 toolchain.
- GitHub CLI and Git; Homebrew installation is recommended.
- No administrator privileges are required.

## Build

```bash
cd Git_connection
./script/build_and_run.sh build
```

Output:

```text
dist/GitHub Ready.app
```

The build script generates `Info.plist`, runs `plutil -lint`, and applies a local ad-hoc signature to the development bundle.

## Tests and verification

```bash
/usr/bin/xcrun swift test
/usr/bin/xcrun swift build
./script/build_and_run.sh verify
```

The test target includes a self-contained harness with no third-party dependencies. It is loaded by `swift test`, runs the complete suite during test-bundle initialization, returns a non-zero exit status on failure, and reports the number of executed and failed tests.

## Run

```bash
./script/build_and_run.sh run
```

The app provides both a desktop window and a native status-bar entry. Double-clicking the Finder, Desktop, or Dock icon opens the main window. Clicking the GitHub Ready status icon opens the status/action popover below the icon; clicking outside it dismisses the popover. Normal startup does not open Terminal, a browser, or a repair command.

## Local MVP launcher

After stable installation, double-click this Desktop Alias:

```text
~/Desktop/GitHub Ready
```

The Alias points to `~/Applications/GitHub Ready.app`, does not open Terminal, and does not create a second application copy. It can be dragged into the Dock like a normal application. When the app is running, the Dock and status bar show the GitHub Ready brand icon.

The primary action area uses three equal-width, equal-height capsule buttons per row.

## Stable installation

This project does not install itself automatically. After separate authorization, the stable location is:

```text
~/Applications/GitHub Ready.app
```

Launch at Login is available only when running from that location. The app calls `SMAppService.mainApp.register()` or `unregister()` only after the user changes the toggle; startup only reads the registration status.

## Disable Launch at Login

Start the app from the stable installation and turn off `Launch at Login`. If macOS requests approval, check System Settings → General → Login Items.

## Uninstall

After confirming that Launch at Login is disabled, quit the app and remove:

```text
~/Applications/GitHub Ready.app
```

To remove app-generated logs, remove:

```text
~/Library/Logs/GitHubReady/
```

Uninstalling the app does not remove GitHub CLI login state, Git configuration, or macOS Keychain credentials.

## Known limitations

- Only `github.com` is supported. SSH Ready requires `ssh.github.com:443`, user `git`, and an available `id_ed25519` key.
- Switching affects GitHub CLI's future workflow preference only; it does not migrate existing repository remotes.
- GitHub Enterprise hosts are not repaired.
- The app does not modify `~/.ssh/config`, `known_hosts`, SSH keys, or Keychain. Non-interactive key-loading failures require action outside the app.
- Browser login is driven by `gh auth login --web`. If the installed GitHub CLI requires terminal-style interaction, the app fails safely with a redacted error and does not fall back to a shell or read a PAT.
- A development bundle cannot be used as a permanent Login Item.
- The status bar uses a fixed GitHub Ready brand mark; detailed health state is shown in the status/action popover.

## Brand icon and status animation

The project includes the user-provided `Sources/GitHubReady/Resources/GitHubReadyIcon.svg`. The build creates `GitHubReadyIcon.icns`, so Finder, the Desktop Alias, and `~/Applications` show the same app icon.

The Finder `.icns` icon is static. The status item uses the user-provided `GitHub-Ready-Icon-white.svg`, converted at build time to `GitHubReadyStatusIcon.png`; it has a transparent background with white branches and nodes, without a black square or green. When the main window is Ready, the complete brand icon's green node displays a soft breathing animation. The animation is not shown in non-Ready states.

If the app is pinned to the Dock, Force Quit leaves its icon in place but removes the running indicator; this is standard macOS behavior. When it is not pinned, the running Dock icon and status item disappear when the process exits.
