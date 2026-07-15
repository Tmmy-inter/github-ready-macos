import Foundation

actor HealthCheckService {
    private let resolver: ExecutableResolver
    private let runner: CommandRunner
    private let authParser: AuthenticationStatusParser
    private let helperParser: CredentialHelperParser
    private let sshService: SSHStatusService
    private let launchAtLoginService: LaunchAtLoginService
    private let stableInstallationPolicy: StableInstallationPolicy
    private let logger: SafeLogger

    init(
        resolver: ExecutableResolver = ExecutableResolver(),
        logger: SafeLogger = .shared
    ) {
        self.resolver = resolver
        self.runner = CommandRunner(allowedExecutablePaths: resolver.allowedPaths)
        self.authParser = AuthenticationStatusParser()
        self.helperParser = CredentialHelperParser()
        self.sshService = SSHStatusService(runner: self.runner)
        self.launchAtLoginService = LaunchAtLoginService()
        self.stableInstallationPolicy = StableInstallationPolicy()
        self.logger = logger
    }

    func check() async -> HealthSnapshot {
        let executables = resolver.resolve()
        let location = stableInstallationPolicy.classify(
            bundleURL: Bundle.main.bundleURL,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let launchState = launchAtLoginService.currentState()

        guard let ghURL = executables.gh else {
            let snapshot = HealthSnapshot(
                visualState: .cliMissing,
                authentication: .cliMissing,
                activeProtocol: .unknown,
                helper: executables.git == nil ? .gitMissing : .missing,
                ssh: await sshService.inspect(executables: executables, activeAccount: nil),
                gitPath: executables.git?.path,
                ghPath: nil,
                gitVersion: await version(for: executables.git, arguments: ["--version"]),
                ghVersion: nil,
                launchAtLogin: launchState,
                applicationLocation: location,
                lastCheckedAt: Date(),
                lastConnectionTest: nil,
                recentError: "GitHub CLI was not found in trusted locations."
            )
            await logger.logEvent(name: "health-check", summary: "GitHub CLI missing")
            return snapshot
        }

        async let ghVersion = version(for: ghURL, arguments: ["--version"])
        async let gitVersion = version(for: executables.git, arguments: ["--version"])
        async let protocolResult = runner.run(CommandRequest(
            executableURL: ghURL,
            arguments: ["config", "get", "git_protocol", "--host", "github.com"],
            timeout: .seconds(5),
            maximumOutputBytes: 8 * 1_024,
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        ))

        let authRequest = CommandRequest(
            executableURL: ghURL,
            arguments: ["auth", "status", "--hostname", "github.com", "--json", "hosts"],
            timeout: .seconds(20),
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        )
        let authResult = await runner.run(authRequest)
        var authentication = authParser.parse(
            json: authResult.standardOutput,
            supplementaryOutput: authResult.standardError,
            timedOut: authResult.timedOut,
            fatalClassification: authResult.errorClassification
        )

        if case .unavailable(.unknown) = authentication {
            let supplementary = await runner.run(CommandRequest(
                executableURL: ghURL,
                arguments: ["auth", "status", "--hostname", "github.com"],
                timeout: .seconds(20),
                environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
            ))
            authentication = authParser.parse(
                json: authResult.standardOutput,
                supplementaryOutput: supplementary.standardOutput + "\n" + supplementary.standardError,
                timedOut: supplementary.timedOut,
                fatalClassification: supplementary.errorClassification
            )
        }

        let resolvedProtocolResult = await protocolResult
        let activeProtocol = GitHubProtocol(commandOutput: resolvedProtocolResult.standardOutput)

        let helperState: CredentialHelperState
        if let gitURL = executables.git {
            helperState = await inspectCredentialHelpers(gitURL: gitURL, ghURL: ghURL)
        } else {
            helperState = .gitMissing
        }

        let sshStatus = await sshService.inspect(
            executables: executables,
            activeAccount: authentication.activeAccount
        )

        let visualState = StatusClassifier().classify(
            authentication: authentication,
            activeProtocol: activeProtocol,
            helper: helperState,
            gitInstalled: executables.git != nil,
            ssh: sshStatus
        )
        let snapshot = HealthSnapshot(
            visualState: visualState,
            authentication: authentication,
            activeProtocol: activeProtocol,
            helper: helperState,
            ssh: sshStatus,
            gitPath: executables.git?.path,
            ghPath: ghURL.path,
            gitVersion: await gitVersion,
            ghVersion: await ghVersion,
            launchAtLogin: launchState,
            applicationLocation: location,
            lastCheckedAt: Date(),
            lastConnectionTest: sshStatus.authentication.displayName,
            recentError: actionableError(
                for: authentication,
                activeProtocol: activeProtocol,
                helper: helperState,
                ssh: sshStatus
            )
        )

        await logger.logEvent(
            name: "health-check",
            exitStatus: authResult.exitStatus,
            duration: authResult.duration,
            timedOut: authResult.timedOut,
            classification: authResult.errorClassification,
            summary: "status=\(visualState.rawValue) auth=\(authentication.displayName) protocol=\(activeProtocol.rawValue) https=\(helperState.displayName) ssh=\(sshStatus.authentication.displayName) route=\(sshStatus.route.displayName) launch=\(launchState.rawValue) location=\(location.displayName)"
        )
        return snapshot
    }

    func testConnection(current snapshot: HealthSnapshot) async -> ConnectionTestResult {
        if snapshot.activeProtocol == .ssh {
            guard let sshURL = resolver.resolve().ssh else {
                return ConnectionTestResult(
                    succeeded: false,
                    networkFailure: nil,
                    authenticationRejected: false,
                    duration: 0,
                    message: "System SSH is unavailable."
                )
            }
            let startedAt = Date()
            let state = await sshService.testConnection(
                sshURL: sshURL,
                expectedAccount: snapshot.authentication.activeAccount
            )
            let duration = Date().timeIntervalSince(startedAt)
            let result = connectionResult(for: state, duration: duration)
            await logger.logEvent(
                name: "connection-test-ssh",
                duration: duration,
                classification: commandClassification(for: result.networkFailure),
                summary: result.message
            )
            return result
        }

        guard let ghURL = resolver.resolve().gh else {
            return ConnectionTestResult(
                succeeded: false,
                networkFailure: nil,
                authenticationRejected: false,
                duration: 0,
                message: "GitHub CLI is not installed."
            )
        }

        let result = await runner.run(CommandRequest(
            executableURL: ghURL,
            arguments: ["api", "--method", "GET", "user", "--silent"],
            timeout: .seconds(20),
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        ))
        let combined = result.standardOutput + "\n" + result.standardError
        let classifier = NetworkErrorClassifier()
        let networkFailure = classifier.classify(combined, timedOut: result.timedOut)
        let authenticationRejected = classifier.explicitlyRejectsAuthentication(combined) || result.errorClassification == .authentication
        let message: String
        if result.succeeded {
            message = "GitHub connection succeeded."
        } else if authenticationRejected {
            message = "GitHub rejected the current credential."
        } else if let networkFailure {
            message = networkFailure.displayName
        } else {
            message = "GitHub connection could not be confirmed."
        }
        await logger.logEvent(
            name: "connection-test",
            exitStatus: result.exitStatus,
            duration: result.duration,
            timedOut: result.timedOut,
            classification: result.errorClassification,
            summary: message
        )
        return ConnectionTestResult(
            succeeded: result.succeeded,
            networkFailure: networkFailure,
            authenticationRejected: authenticationRejected,
            duration: result.duration,
            message: message
        )
    }

    func switchProtocol(to target: GitHubProtocol, userConfirmed: Bool) async -> ProtocolSwitchOutcome {
        guard let command = ProtocolSwitchCommand(target: target, userConfirmed: userConfirmed) else {
            return .blocked("Select HTTPS or SSH before switching.")
        }
        guard let ghURL = resolver.resolve().gh else {
            return .blocked("GitHub CLI is not installed.")
        }
        let result = await runner.run(CommandRequest(
            executableURL: ghURL,
            arguments: command.arguments,
            timeout: .seconds(10),
            maximumOutputBytes: 16 * 1_024,
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        ))
        await logger.logEvent(
            name: "protocol-switch",
            exitStatus: result.exitStatus,
            duration: result.duration,
            timedOut: result.timedOut,
            classification: result.errorClassification,
            summary: result.succeeded ? "Preferred protocol changed to \(target.rawValue)" : "Protocol change failed"
        )
        return result.succeeded ? .completed : .failed("The preferred GitHub CLI protocol could not be changed.")
    }

    func repairSSH(current snapshot: HealthSnapshot) async -> RepairOutcome {
        guard snapshot.activeProtocol == .ssh else {
            return .blocked("Switch to SSH before using SSH repair.")
        }
        let outcome = await sshService.repair(
            executables: resolver.resolve(),
            activeAccount: snapshot.authentication.activeAccount
        )
        await logger.logEvent(
            name: "repair-ssh",
            summary: outcome == .notRequired ? "No SSH repair required" : "SSH repair action completed without configuration rewrites"
        )
        return outcome
    }

    func repairHTTPS(current snapshot: HealthSnapshot) async -> RepairOutcome {
        guard case .authenticated = snapshot.authentication else {
            return .blocked("Authenticate with GitHub before repairing HTTPS integration.")
        }
        guard snapshot.activeProtocol == .https else {
            return .blocked("GitHub CLI must be configured for HTTPS.")
        }
        if snapshot.helper.isValid { return .notRequired }
        guard let ghURL = resolver.resolve().gh else {
            return .blocked("GitHub CLI is not installed.")
        }

        let result = await runner.run(CommandRequest(
            executableURL: ghURL,
            arguments: ["auth", "setup-git", "--hostname", "github.com"],
            timeout: .seconds(30),
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        ))
        await logger.logEvent(
            name: "repair-https",
            exitStatus: result.exitStatus,
            duration: result.duration,
            timedOut: result.timedOut,
            classification: result.errorClassification,
            summary: result.succeeded ? "Repair command completed" : "Repair command failed"
        )
        return result.succeeded ? .completed : .failed("HTTPS integration repair failed. Review the sanitized logs.")
    }

    func logIn() async -> LoginOutcome {
        guard let ghURL = resolver.resolve().gh else {
            return .failed("GitHub CLI is not installed.")
        }
        let result = await runner.run(CommandRequest(
            executableURL: ghURL,
            arguments: ["auth", "login", "--hostname", "github.com", "--web", "--git-protocol", "https"],
            timeout: .seconds(600),
            maximumOutputBytes: 64 * 1_024
        ))
        await logger.logEvent(
            name: "github-login",
            exitStatus: result.exitStatus,
            duration: result.duration,
            timedOut: result.timedOut,
            classification: result.errorClassification,
            summary: result.succeeded ? "Login flow completed" : "Login flow ended without success"
        )
        if result.succeeded { return .completed }
        if result.exitStatus == 130 { return .cancelled }
        if result.timedOut { return .failed("GitHub login timed out.") }
        return .failed("GitHub login did not complete. Review the sanitized logs.")
    }

    func setLaunchAtLogin(enabled: Bool, location: ApplicationLocationState) throws -> LaunchAtLoginState {
        guard location.allowsLaunchAtLogin else { throw LaunchAtLoginError.unstableApplicationPath }
        if enabled {
            try launchAtLoginService.register()
        } else {
            try launchAtLoginService.unregister()
        }
        return launchAtLoginService.currentState()
    }

    private func version(for executableURL: URL?, arguments: [String]) async -> String? {
        guard let executableURL else { return nil }
        let result = await runner.run(CommandRequest(
            executableURL: executableURL,
            arguments: arguments,
            timeout: .seconds(5),
            maximumOutputBytes: 8 * 1_024,
            environmentOverrides: ["GH_PROMPT_DISABLED": "1"]
        ))
        guard result.exitStatus == 0 else { return nil }
        return result.standardOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)
    }

    private func inspectCredentialHelpers(gitURL: URL, ghURL: URL) async -> CredentialHelperState {
        let queries: [(CredentialHelperEntry.Scope, String, [String])] = [
            (.system, "credential.helper", ["config", "--system", "--get-all", "credential.helper"]),
            (.global, "credential.helper", ["config", "--global", "--get-all", "credential.helper"]),
            (.global, "credential.https://github.com.helper", ["config", "--global", "--get-all", "credential.https://github.com.helper"]),
            (.global, "credential.https://gist.github.com.helper", ["config", "--global", "--get-all", "credential.https://gist.github.com.helper"])
        ]
        var entries: [CredentialHelperEntry] = []
        for (scope, key, arguments) in queries {
            let result = await runner.run(CommandRequest(
                executableURL: gitURL,
                arguments: arguments,
                timeout: .seconds(5),
                maximumOutputBytes: 16 * 1_024
            ))
            if result.exitStatus == 0 {
                entries.append(contentsOf: helperParser.entries(scope: scope, key: key, output: result.standardOutput))
            }
        }
        return helperParser.classify(entries: entries, resolvedGHPath: ghURL.path)
    }

    private func actionableError(
        for authentication: AuthenticationState,
        activeProtocol: GitHubProtocol,
        helper: CredentialHelperState,
        ssh: SSHStatus
    ) -> String? {
        switch authentication {
        case .authenticated:
            switch activeProtocol {
            case .https: return helper.isValid ? nil : helper.displayName
            case .ssh: return ssh.isReady ? nil : ssh.authentication.displayName
            case .unknown: return "GitHub CLI protocol is not recognized."
            }
        case .invalid: return "Use Log In to GitHub to replace the rejected credential."
        case .unavailable(let failure): return failure.displayName
        case .noConfiguredAccount: return "No GitHub account is configured."
        case .noActiveAccount: return "No active GitHub account is selected."
        case .credentialStoreUnavailable: return "Unlock the macOS login Keychain, then check again."
        case .malformed: return "GitHub CLI returned an unsupported status response."
        case .timedOut: return "The authentication check timed out. Try again when the network is stable."
        case .cliMissing: return "Install GitHub CLI before checking authentication."
        }
    }

    private func connectionResult(
        for state: SSHAuthenticationState,
        duration: TimeInterval
    ) -> ConnectionTestResult {
        switch state {
        case .verified:
            return ConnectionTestResult(succeeded: true, networkFailure: nil, authenticationRejected: false, duration: duration, message: "GitHub SSH authentication succeeded over port 443.")
        case .networkUnavailable(let failure):
            return ConnectionTestResult(succeeded: false, networkFailure: failure, authenticationRejected: false, duration: duration, message: failure.displayName)
        case .rejected:
            return ConnectionTestResult(succeeded: false, networkFailure: nil, authenticationRejected: true, duration: duration, message: "GitHub rejected the SSH key.")
        case .hostVerificationProblem:
            return ConnectionTestResult(succeeded: false, networkFailure: nil, authenticationRejected: false, duration: duration, message: "Host key verification requires attention.")
        case .interactionRequired:
            return ConnectionTestResult(succeeded: false, networkFailure: nil, authenticationRejected: false, duration: duration, message: "Load the SSH key from macOS Keychain, then try again.")
        case .notTested, .failed:
            return ConnectionTestResult(succeeded: false, networkFailure: nil, authenticationRejected: false, duration: duration, message: "GitHub SSH authentication could not be confirmed.")
        }
    }

    private func commandClassification(for failure: NetworkFailure?) -> CommandErrorClassification {
        switch failure {
        case .dns: .dns
        case .tls: .tls
        case .timeout: .timeout
        case .permissionDenied: .permission
        case .proxyOrVPN, .githubUnavailable, .rateLimited: .network
        case .unknown, .none: .none
        }
    }
}
