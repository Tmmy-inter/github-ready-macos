import Foundation
@testable import GitHubReady

enum GitHubReadySelfTests {
    static let all: [SelfTestCase] = commandTests + authenticationTests + helperTests + redactionTests + protocolTests + sshTests + classificationTests + locationAndDiagnosticsTests

    private static let commandTests: [SelfTestCase] = [
        SelfTestCase(name: "command execution success") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["hello"]
            ))
            try expect(result.succeeded, "echo should succeed")
            try expectEqual(result.standardOutput, "hello\n", "echo output")
        },
        SelfTestCase(name: "command timeout") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: .milliseconds(100)
            ))
            try expect(result.timedOut, "sleep should time out")
            try expectEqual(result.errorClassification, .timeout, "timeout classification")
        },
        SelfTestCase(name: "executable missing") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/tmp/github-ready-missing-executable"),
                arguments: []
            ))
            try expectEqual(result.errorClassification, .executableMissing, "missing executable classification")
        },
        SelfTestCase(name: "executable allowlist") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: []
            ))
            try expectEqual(result.errorClassification, .executableNotAllowed, "allowlist rejection")
        },
        SelfTestCase(name: "bounded output") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["%s", String(repeating: "x", count: 4_096)],
                maximumOutputBytes: 1_024
            ))
            try expectEqual(result.exitStatus, 0, "printf exit status")
            try expect(result.outputTruncated, "output should be truncated")
            try expect(result.standardOutput.utf8.count <= 1_024, "captured output should respect limit")
        }
    ]

    private static let authenticationTests: [SelfTestCase] = [
        SelfTestCase(name: "authentication valid JSON exit zero") {
            let state = authParser.parse(json: authEnvelope([authAccount(active: true, state: "success")]))
            try expectEqual(state, .authenticated(account: "octocat", additionalAccounts: 0, protocolName: "https"), "valid authentication")
        },
        SelfTestCase(name: "authentication invalid JSON exit zero") {
            let state = authParser.parse(json: authEnvelope([authAccount(active: true, state: "failure", error: "Bad credentials")]))
            guard case .invalid = state else { throw SelfTestFailure(description: "expected invalid authentication") }
        },
        SelfTestCase(name: "authentication missing github host") {
            try expectEqual(authParser.parse(json: #"{"hosts":{"enterprise.example":[]}}"#), .noConfiguredAccount, "missing github.com")
        },
        SelfTestCase(name: "authentication multiple accounts one active") {
            let state = authParser.parse(json: authEnvelope([
                authAccount(login: "first", active: false, state: "success"),
                authAccount(login: "second", active: true, state: "success")
            ]))
            try expectEqual(state, .authenticated(account: "second", additionalAccounts: 1, protocolName: "https"), "one active account")
        },
        SelfTestCase(name: "authentication multiple accounts no active") {
            let state = authParser.parse(json: authEnvelope([
                authAccount(login: "first", active: false, state: "success"),
                authAccount(login: "second", active: false, state: "success")
            ]))
            try expectEqual(state, .noActiveAccount, "no active account")
        },
        SelfTestCase(name: "authentication missing fields") {
            try expectEqual(authParser.parse(json: #"{"hosts":{"github.com":[{"active":true}]}}"#), .malformed, "missing JSON fields")
        },
        SelfTestCase(name: "authentication malformed JSON") {
            try expectEqual(authParser.parse(json: "{not-json"), .malformed, "malformed JSON")
        },
        SelfTestCase(name: "authentication timeout") {
            try expectEqual(authParser.parse(json: "", timedOut: true), .timedOut, "command timeout")
        },
        SelfTestCase(name: "authentication fatal CLI error") {
            try expectEqual(authParser.parse(json: "", fatalClassification: .launchFailure), .malformed, "fatal CLI error")
        },
        SelfTestCase(name: "authentication DNS unavailable") {
            let state = authParser.parse(
                json: authEnvelope([authAccount(active: true, state: "failure")]),
                supplementaryOutput: "dial tcp: lookup github.com: no such host"
            )
            try expectEqual(state, .unavailable(.dns), "DNS must not become invalid auth")
        },
        SelfTestCase(name: "authentication failure unconfirmed") {
            let state = authParser.parse(json: authEnvelope([authAccount(active: true, state: "failure")]))
            try expectEqual(state, .unavailable(.unknown), "ambiguous failure remains unconfirmed")
        },
        SelfTestCase(name: "authentication credential store unavailable") {
            let state = authParser.parse(
                json: authEnvelope([authAccount(active: true, state: "failure")]),
                supplementaryOutput: "The macOS keyring is locked and unavailable"
            )
            try expectEqual(state, .credentialStoreUnavailable, "credential store failure")
        }
    ]

    private static let helperTests: [SelfTestCase] = [
        SelfTestCase(name: "helper system keychain only") {
            try expectEqual(helperParser.classify(entries: [helperEntry(.system, "credential.helper", "osxkeychain")], resolvedGHPath: ghPath), .systemKeychainOnly, "system keychain only")
        },
        SelfTestCase(name: "helper github scoped") {
            try expectEqual(helperParser.classify(entries: [helperEntry(.global, githubHelperKey, "!/opt/homebrew/bin/gh auth git-credential")], resolvedGHPath: ghPath), .valid(helperPath: ghPath), "scoped helper")
        },
        SelfTestCase(name: "helper empty reset followed by gh") {
            let state = helperParser.classify(entries: [
                helperEntry(.global, githubHelperKey, ""),
                helperEntry(.global, githubHelperKey, "!/opt/homebrew/bin/gh auth git-credential")
            ], resolvedGHPath: ghPath)
            try expectEqual(state, .valid(helperPath: ghPath), "reset plus helper")
        },
        SelfTestCase(name: "helper system plus github scoped") {
            let state = helperParser.classify(entries: [
                helperEntry(.system, "credential.helper", "osxkeychain"),
                helperEntry(.global, githubHelperKey, ""),
                helperEntry(.global, githubHelperKey, "!/opt/homebrew/bin/gh auth git-credential")
            ], resolvedGHPath: ghPath)
            try expectEqual(state, .valid(helperPath: ghPath), "coexisting helpers")
        },
        SelfTestCase(name: "helper duplicate") {
            let entry = helperEntry(.global, githubHelperKey, "!/opt/homebrew/bin/gh auth git-credential")
            try expectEqual(helperParser.classify(entries: [entry, entry], resolvedGHPath: ghPath), .valid(helperPath: ghPath), "duplicate helpers")
        },
        SelfTestCase(name: "helper missing") {
            try expectEqual(helperParser.classify(entries: [], resolvedGHPath: ghPath), .missing, "missing helper")
        },
        SelfTestCase(name: "helper malformed") {
            let state = helperParser.classify(entries: [helperEntry(.global, githubHelperKey, "!custom credential script")], resolvedGHPath: ghPath)
            guard case .malformed = state else { throw SelfTestFailure(description: "expected malformed helper") }
        },
        SelfTestCase(name: "helper executable moved") {
            let movedPath = "/usr/local/bin/gh"
            let state = helperParser.classify(
                entries: [helperEntry(.global, githubHelperKey, "!\"/usr/local/bin/gh\"   auth   git-credential")],
                resolvedGHPath: movedPath
            )
            try expectEqual(state, .valid(helperPath: movedPath), "moved valid helper")
        },
        SelfTestCase(name: "helper stale executable path") {
            let state = helperParser.classify(
                entries: [helperEntry(.global, githubHelperKey, "!/opt/homebrew/bin/gh auth git-credential")],
                resolvedGHPath: "/usr/local/bin/gh"
            )
            guard case .malformed = state else { throw SelfTestFailure(description: "expected stale helper path") }
        },
        SelfTestCase(name: "helper output preserves reset") {
            let entries = helperParser.entries(scope: .global, key: githubHelperKey, output: "\n!/opt/homebrew/bin/gh auth git-credential\n")
            try expectEqual(entries.map(\.value), ["", "!/opt/homebrew/bin/gh auth git-credential"], "empty reset preservation")
        }
    ]

    private static let redactionTests: [SelfTestCase] = [
        SelfTestCase(name: "redaction github and bearer tokens") {
            let fakeGitHubToken = "gh" + "p_" + "abcdefghijklmnopqrstuvwxyz123456"
            let fakeBearer = "abc" + ".def.ghi"
            let output = redactor.redact(fakeGitHubToken + " Bearer " + fakeBearer)
            try expect(!output.contains("ghp_"), "GitHub token leaked")
            try expect(!output.contains(fakeBearer), "Bearer token leaked")
        },
        SelfTestCase(name: "redaction preserves account and repo") {
            let input = "account=octocat repository=hello-world"
            try expectEqual(redactor.redact(input), input, "normal names")
        },
        SelfTestCase(name: "redaction preserves normal path") {
            let input = "/Users/example/Projects/hello-world"
            try expectEqual(redactor.redact(input), input, "normal file path")
        },
        SelfTestCase(name: "redaction URL credentials") {
            let unsafeURL = "https://user:" + "password@example.com/repo.git"
            try expectEqual(redactor.redact(unsafeURL), "https://[REDACTED]@example.com/repo.git", "URL credentials")
        },
        SelfTestCase(name: "redaction authorization header") {
            let header = "Authorization" + ": token secret-value"
            try expectEqual(redactor.redact(header), "Authorization: [REDACTED]", "authorization header")
        },
        SelfTestCase(name: "redaction private credential block") {
            let begin = "-----BEGIN " + "PRIVATE KEY-----"
            let end = "-----END " + "PRIVATE KEY-----"
            let output = redactor.redact("before\n\(begin)\nfictional\n\(end)\nafter")
            try expect(!output.contains("fictional"), "private block leaked")
            try expect(output.contains("before") && output.contains("after"), "safe context removed")
        },
        SelfTestCase(name: "redaction mixed stdout stderr") {
            let output = redactor.redact("stdout normal\nstderr password=" + "hunter2\nCookie: session=fake")
            try expect(output.contains("stdout normal"), "safe output removed")
            try expect(!output.contains("hunter2") && !output.contains("session=fake"), "mixed secret leaked")
        },
        SelfTestCase(name: "redaction command arguments") {
            try expectEqual(redactor.sanitizeArguments(["auth", "--token", "fictional-token-value"]), ["auth", "--token", "[REDACTED]"], "sensitive argument")
        },
        SelfTestCase(name: "redaction SSH fingerprint") {
            let fingerprint = "SHA256:" + "FictionalFingerprintValue1234567890"
            let output = redactor.redact("256 \(fingerprint) example-key")
            try expect(!output.contains("FictionalFingerprintValue"), "SSH fingerprint leaked")
        }
    ]

    private static let classificationTests: [SelfTestCase] = [
        SelfTestCase(name: "status ready") {
            try expectEqual(statusClassifier.classify(
                authentication: .authenticated(account: "octocat", additionalAccounts: 0, protocolName: "https"),
                activeProtocol: .https,
                helper: .valid(helperPath: ghPath),
                gitInstalled: true,
                ssh: rejectedSSH
            ), .ready, "ready state")
        },
        SelfTestCase(name: "status network orange") {
            try expectEqual(statusClassifier.classify(
                authentication: .unavailable(.dns),
                activeProtocol: .https,
                helper: .valid(helperPath: ghPath),
                gitInstalled: true,
                ssh: readySSH
            ), .networkUnavailable, "network state")
        },
        SelfTestCase(name: "status auth invalid red") {
            try expectEqual(statusClassifier.classify(
                authentication: .invalid(reason: "Bad credentials"),
                activeProtocol: .https,
                helper: .valid(helperPath: ghPath),
                gitInstalled: true,
                ssh: readySSH
            ), .authenticationRequired, "invalid auth state")
        },
        SelfTestCase(name: "status helper missing yellow") {
            try expectEqual(statusClassifier.classify(
                authentication: .authenticated(account: "octocat", additionalAccounts: 0, protocolName: "https"),
                activeProtocol: .https,
                helper: .missing,
                gitInstalled: true,
                ssh: readySSH
            ), .partial, "missing helper state")
        },
        SelfTestCase(name: "active SSH valid is ready") {
            try expectEqual(statusClassifier.classify(
                authentication: .authenticated(account: "octocat", additionalAccounts: 0, protocolName: "ssh"),
                activeProtocol: .ssh,
                helper: .missing,
                gitInstalled: true,
                ssh: readySSH
            ), .ready, "active SSH ready")
        },
        SelfTestCase(name: "active SSH timeout orange") {
            var ssh = readySSH
            ssh.authentication = .networkUnavailable(.timeout)
            try expectEqual(classify(activeProtocol: .ssh, helper: .valid(helperPath: ghPath), ssh: ssh), .networkUnavailable, "SSH timeout")
        },
        SelfTestCase(name: "active SSH rejection red") {
            try expectEqual(classify(activeProtocol: .ssh, helper: .valid(helperPath: ghPath), ssh: rejectedSSH), .authenticationRequired, "SSH rejection")
        },
        SelfTestCase(name: "inactive SSH failure does not downgrade HTTPS") {
            try expectEqual(classify(activeProtocol: .https, helper: .valid(helperPath: ghPath), ssh: rejectedSSH), .ready, "inactive SSH")
        },
        SelfTestCase(name: "inactive HTTPS failure does not downgrade SSH") {
            try expectEqual(classify(activeProtocol: .ssh, helper: .missing, ssh: readySSH), .ready, "inactive HTTPS")
        },
        SelfTestCase(name: "active protocol determines visual state") {
            let https = classify(activeProtocol: .https, helper: .valid(helperPath: ghPath), ssh: rejectedSSH)
            let ssh = classify(activeProtocol: .ssh, helper: .valid(helperPath: ghPath), ssh: rejectedSSH)
            try expectEqual(https, .ready, "HTTPS visual state")
            try expectEqual(ssh, .authenticationRequired, "SSH visual state")
        },
        SelfTestCase(name: "network DNS classification") {
            try expectEqual(networkClassifier.classify("Could not resolve host: github.com"), .dns, "DNS classification")
        },
        SelfTestCase(name: "network timeout classification") {
            try expectEqual(networkClassifier.classify("", timedOut: true), .timeout, "timeout classification")
        },
        SelfTestCase(name: "network VPN routing classification") {
            try expectEqual(networkClassifier.classify("Network is unreachable"), .proxyOrVPN, "VPN classification")
        }
    ]

    private static let protocolTests: [SelfTestCase] = [
        SelfTestCase(name: "protocol parses HTTPS") {
            try expectEqual(GitHubProtocol(commandOutput: "https\n"), .https, "HTTPS protocol")
        },
        SelfTestCase(name: "protocol parses SSH") {
            try expectEqual(GitHubProtocol(commandOutput: "ssh\n"), .ssh, "SSH protocol")
        },
        SelfTestCase(name: "protocol parses unknown") {
            try expectEqual(GitHubProtocol(commandOutput: "git"), .unknown, "unknown protocol")
        },
        SelfTestCase(name: "build HTTPS switch command") {
            try expectEqual(
                ProtocolSwitchCommand(target: .https, userConfirmed: true)?.arguments,
                ["config", "set", "git_protocol", "https", "--host", "github.com"],
                "HTTPS switch"
            )
        },
        SelfTestCase(name: "build SSH switch command") {
            try expectEqual(
                ProtocolSwitchCommand(target: .ssh, userConfirmed: true)?.arguments,
                ["config", "set", "git_protocol", "ssh", "--host", "github.com"],
                "SSH switch"
            )
        },
        SelfTestCase(name: "protocol switch requires explicit confirmation") {
            try expect(ProtocolSwitchCommand(target: .ssh, userConfirmed: false) == nil, "unconfirmed switch must not build")
        }
    ]

    private static let sshTests: [SelfTestCase] = [
        SelfTestCase(name: "ssh config parser hostname") {
            try expectEqual(sshConfigParser.parse(validSSHConfig)?.hostname, "ssh.github.com", "SSH hostname")
        },
        SelfTestCase(name: "ssh config parser port 443") {
            try expectEqual(sshConfigParser.parse(validSSHConfig)?.port, 443, "SSH port")
        },
        SelfTestCase(name: "ssh config parser user git") {
            try expectEqual(sshConfigParser.parse(validSSHConfig)?.user, "git", "SSH user")
        },
        SelfTestCase(name: "ssh config parser identity") {
            try expectEqual(sshConfigParser.parse(validSSHConfig)?.primaryIdentityFilename, "id_ed25519", "SSH identity")
        },
        SelfTestCase(name: "ssh route missing identity") {
            guard let configuration = sshConfigParser.parse(validSSHConfig) else { throw SelfTestFailure(description: "config missing") }
            let service = SSHStatusService(runner: CommandRunner(allowedExecutablePaths: []))
            try expectEqual(service.classifyRoute(configuration, fileExists: { _ in false }), .identityMissing("id_ed25519"), "missing identity")
        },
        SelfTestCase(name: "ssh agent loaded identity") {
            try expectEqual(sshAgentParser.parse(exitStatus: 0, output: "256 SHA256:fictional key (ED25519)"), .identityLoaded, "loaded identity")
        },
        SelfTestCase(name: "ssh agent no identities") {
            try expectEqual(sshAgentParser.parse(exitStatus: 1, output: "The agent has no identities."), .noIdentities, "empty agent")
        },
        SelfTestCase(name: "ssh agent unavailable") {
            try expectEqual(sshAgentParser.parse(exitStatus: 2, output: "Could not open a connection to your authentication agent."), .unavailable, "agent unavailable")
        },
        SelfTestCase(name: "ssh GitHub success exit one") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 1, output: sshSuccess, timedOut: false, expectedAccount: "octocat"), .verified(account: "octocat"), "GitHub success")
        },
        SelfTestCase(name: "ssh account mismatch rejected") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 1, output: sshSuccess, timedOut: false, expectedAccount: "hubot"), .rejected, "account mismatch")
        },
        SelfTestCase(name: "ssh permission denied") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Permission denied (publickey).", timedOut: false, expectedAccount: nil), .rejected, "permission denied")
        },
        SelfTestCase(name: "ssh DNS failure") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Could not resolve hostname github.com", timedOut: false, expectedAccount: nil), .networkUnavailable(.dns), "DNS failure")
        },
        SelfTestCase(name: "ssh connection timeout") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Connection timed out", timedOut: false, expectedAccount: nil), .networkUnavailable(.timeout), "connection timeout")
        },
        SelfTestCase(name: "ssh connection refused") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Connection refused", timedOut: false, expectedAccount: nil), .networkUnavailable(.proxyOrVPN), "connection refused")
        },
        SelfTestCase(name: "ssh host verification failure") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Host key verification failed.", timedOut: false, expectedAccount: nil), .hostVerificationProblem, "host verification")
        },
        SelfTestCase(name: "ssh proxy routing failure") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "Proxy connection failed", timedOut: false, expectedAccount: nil), .networkUnavailable(.proxyOrVPN), "proxy failure")
        },
        SelfTestCase(name: "ssh command timeout") {
            try expectEqual(sshConnectionParser.parse(exitStatus: -1, output: "", timedOut: true, expectedAccount: nil), .networkUnavailable(.timeout), "command timeout")
        },
        SelfTestCase(name: "bounded SSH output") {
            let result = await commandRunner.run(CommandRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
                arguments: ["%s", String(repeating: "s", count: 8_192)],
                maximumOutputBytes: 1_024
            ))
            try expect(result.outputTruncated, "SSH-style output should be bounded")
            try expect(result.standardOutput.utf8.count <= 1_024, "bounded SSH output limit")
        },
        SelfTestCase(name: "ssh passphrase interaction") {
            try expectEqual(sshConnectionParser.parse(exitStatus: 255, output: "read_passphrase: can't open /dev/tty", timedOut: false, expectedAccount: nil), .interactionRequired, "interaction")
        }
    ]

    private static let locationAndDiagnosticsTests: [SelfTestCase] = [
        SelfTestCase(name: "location dist") {
            try expectEqual(locationPolicy.classify(bundleURL: URL(fileURLWithPath: "/Users/example/Project/dist/GitHub Ready.app"), homeDirectory: testHome), .developmentDist, "dist path")
        },
        SelfTestCase(name: "location build") {
            try expectEqual(locationPolicy.classify(bundleURL: URL(fileURLWithPath: "/Users/example/Project/.build/GitHub Ready.app"), homeDirectory: testHome), .developmentBuild, "build path")
        },
        SelfTestCase(name: "location stable with spaces") {
            try expectEqual(locationPolicy.classify(bundleURL: URL(fileURLWithPath: "/Users/example/Applications/GitHub Ready.app"), homeDirectory: testHome), .stable, "stable path")
        },
        SelfTestCase(name: "location unexpected") {
            try expectEqual(locationPolicy.classify(bundleURL: URL(fileURLWithPath: "/tmp/GitHub Ready.app"), homeDirectory: testHome), .unexpected, "unexpected path")
        },
        SelfTestCase(name: "launch at login mapping") {
            try expectEqual(LaunchAtLoginStateMapper.map(.enabled), .enabled, "enabled")
            try expectEqual(LaunchAtLoginStateMapper.map(.notRegistered), .notRegistered, "not registered")
            try expectEqual(LaunchAtLoginStateMapper.map(.requiresApproval), .requiresApproval, "requires approval")
            try expectEqual(LaunchAtLoginStateMapper.map(.notFound), .notFound, "not found")
            try expectEqual(LaunchAtLoginStateMapper.map(.unsupported), .unsupported, "unsupported")
            try expectEqual(LaunchAtLoginStateMapper.map(.unknown), .error, "unknown")
        },
        SelfTestCase(name: "diagnostics redaction") {
            var snapshot = HealthSnapshot.checking
            snapshot.visualState = .ready
            snapshot.authentication = .authenticated(account: "octocat", additionalAccounts: 0, protocolName: "https")
            snapshot.helper = .valid(helperPath: ghPath)
            let diagnostics = DiagnosticsBuilder().build(snapshot: snapshot, recentErrors: "Authorization" + ": Bearer fictional-secret-value")
            try expect(!diagnostics.contains("fictional-secret-value"), "diagnostics leaked a credential")
            try expect(diagnostics.contains("Overall status: Ready"), "diagnostics omitted status")
        },
        SelfTestCase(name: "SSH diagnostics contain safe summary only") {
            var snapshot = HealthSnapshot.checking
            snapshot.activeProtocol = .ssh
            snapshot.ssh = readySSH
            let fingerprint = "SHA256:" + "FictionalFingerprintValue1234567890"
            let diagnostics = DiagnosticsBuilder().build(snapshot: snapshot, recentErrors: fingerprint)
            try expect(diagnostics.contains("Effective SSH host: ssh.github.com"), "safe SSH host missing")
            try expect(diagnostics.contains("SSH identity filename: id_ed25519"), "safe identity filename missing")
            try expect(!diagnostics.contains("FictionalFingerprintValue"), "SSH diagnostics leaked fingerprint")
        }
    ]

    private static let commandRunner = CommandRunner(allowedExecutablePaths: [
        "/bin/echo", "/bin/sleep", "/usr/bin/printf", "/tmp/github-ready-missing-executable"
    ])
    private static let authParser = AuthenticationStatusParser()
    private static let helperParser = CredentialHelperParser()
    private static let redactor = SensitiveValueRedactor()
    private static let statusClassifier = StatusClassifier()
    private static let networkClassifier = NetworkErrorClassifier()
    private static let sshConfigParser = SSHEffectiveConfigurationParser()
    private static let sshAgentParser = SSHAgentParser()
    private static let sshConnectionParser = SSHConnectionParser()
    private static let locationPolicy = StableInstallationPolicy()
    private static let testHome = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    private static let ghPath = "/opt/homebrew/bin/gh"
    private static let githubHelperKey = "credential.https://github.com.helper"
    private static let validSSHConfig = """
    host github.com
    hostname ssh.github.com
    port 443
    user git
    identityfile /Users/example/.ssh/id_ed25519
    identitiesonly yes
    addkeystoagent yes
    usekeychain yes
    """
    private static let sshSuccess = "Hi octocat! You've successfully authenticated, but GitHub does not provide shell access."
    private static let readySSH = SSHStatus(
        executableAvailable: true,
        configuration: EffectiveSSHConfiguration(
            hostname: "ssh.github.com",
            port: 443,
            user: "git",
            identityFiles: ["/Users/example/.ssh/id_ed25519"],
            identitiesOnly: true,
            addKeysToAgent: true,
            useKeychain: true
        ),
        route: .ready,
        agent: .identityLoaded,
        authentication: .verified(account: "octocat"),
        lastTestedAt: nil
    )
    private static let rejectedSSH = SSHStatus(
        executableAvailable: true,
        configuration: readySSH.configuration,
        route: .ready,
        agent: .identityLoaded,
        authentication: .rejected,
        lastTestedAt: nil
    )

    private static func classify(
        activeProtocol: GitHubProtocol,
        helper: CredentialHelperState,
        ssh: SSHStatus
    ) -> MenuVisualState {
        statusClassifier.classify(
            authentication: .authenticated(account: "octocat", additionalAccounts: 0, protocolName: activeProtocol.rawValue),
            activeProtocol: activeProtocol,
            helper: helper,
            gitInstalled: true,
            ssh: ssh
        )
    }

    private static func authEnvelope(_ accounts: [String]) -> String {
        "{\"hosts\":{\"github.com\":[\(accounts.joined(separator: ","))]}}"
    }

    private static func authAccount(
        login: String = "octocat",
        active: Bool,
        state: String,
        error: String? = nil
    ) -> String {
        let errorField = error.map { ",\"error\":\"\($0)\"" } ?? ""
        return "{\"active\":\(active),\"gitProtocol\":\"https\",\"host\":\"github.com\",\"login\":\"\(login)\",\"state\":\"\(state)\"\(errorField)}"
    }

    private static func helperEntry(
        _ scope: CredentialHelperEntry.Scope,
        _ key: String,
        _ value: String
    ) -> CredentialHelperEntry {
        CredentialHelperEntry(scope: scope, key: key, value: value)
    }
}
