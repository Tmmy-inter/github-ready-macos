# Security Model

## Threat boundary

The primary risks are command injection, credential output, unbounded child processes, malicious or malformed CLI output, log disclosure, accidental rewriting of health configuration, and registering a temporary bundle as a Login Item.

## Credential rules

- Never call `gh auth token` or `--show-token`.
- Do not request, receive, or store a PAT.
- Do not read Keychain contents.
- Do not record raw login-command output.
- Do not record the complete environment.
- Do not pass token environment variables to child processes.
- Show the account name only where required by the local UI; do not include complete account metadata in security diagnostics.

## Command allowlist

The app allows only these executable candidates:

- `/opt/homebrew/bin/gh`
- `/usr/local/bin/gh`
- `/usr/bin/gh`
- `/opt/homebrew/bin/git`
- `/usr/local/bin/git`
- `/usr/bin/git`
- `/usr/bin/ssh`
- `/usr/bin/ssh-add`
- A small set of fixed macOS system-tool paths.

There are no arbitrary command strings, `sh -c`, `bash -c`, `zsh -c`, `eval`, or `sudo` paths.

## Output and logs

Command output is limited to 256 KiB by default. Logs are limited to 512 KiB with one rotated file. Logs contain only high-level events, command names, redacted arguments, exit status, duration, timeout state, and error classification; raw API or login responses are never written.

Redaction covers GitHub tokens, Bearer/OAuth values, Authorization/Cookie headers, URL credentials, passwords, passphrases, SSH fingerprints, generic secrets, private-key/credential blocks, and long random credential-shaped strings. Copying diagnostics performs a complete second redaction pass.

## Timeouts and responsiveness

`CommandRunner` manages blocking `Process` calls in detached tasks while SwiftUI waits only for the actor result. Normal version and configuration queries use a 5-second timeout, authentication and API calls use 20 seconds, repair uses 30 seconds, and explicit browser login uses a maximum of 10 minutes.

## Browser-login boundary

The login command runs only after the user clicks and confirms. If an account is already valid, the app adds an extra warning that the flow may add or replace GitHub CLI credentials. Automated verification never calls this path.

## Read-only startup guarantee

Startup only reads version, authentication, active protocol, Git helper, effective SSH configuration/agent state, read-only connection state, and `SMAppService` status. Protocol switching, repair, login, and register/unregister are separate confirmed actions, and development bundles disable the Launch at Login toggle.

SSH uses system binaries and non-interactive `BatchMode`; it does not accept passphrases or display/log key contents, complete public keys, fingerprints, or raw `ssh-add` output. Strict host-key failures produce an actionable message only; the app does not automatically accept host keys, modify `known_hosts`, or rewrite `~/.ssh/config`.
