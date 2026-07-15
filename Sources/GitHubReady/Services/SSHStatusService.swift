import Foundation

struct SSHStatusService: Sendable {
    private let runner: CommandRunner
    private let configurationParser = SSHEffectiveConfigurationParser()
    private let agentParser = SSHAgentParser()
    private let connectionParser = SSHConnectionParser()

    init(runner: CommandRunner) {
        self.runner = runner
    }

    func inspect(executables: ResolvedExecutables, activeAccount: String?) async -> SSHStatus {
        guard let sshURL = executables.ssh else { return .unavailable }

        let configResult = await runner.run(CommandRequest(
            executableURL: sshURL,
            arguments: ["-G", "github.com"],
            timeout: .seconds(5),
            maximumOutputBytes: 64 * 1_024
        ))
        guard configResult.exitStatus == 0,
              let configuration = configurationParser.parse(configResult.standardOutput) else {
            return SSHStatus(
                executableAvailable: true,
                configuration: nil,
                route: .inspectionFailed,
                agent: await inspectAgent(executables.sshAdd),
                authentication: .notTested,
                lastTestedAt: nil
            )
        }

        let route = classifyRoute(configuration)
        let agent = await inspectAgent(executables.sshAdd)
        var authentication = await testConnection(sshURL: sshURL, expectedAccount: activeAccount)
        if authentication == .rejected,
           agent == .noIdentities,
           configuration.useKeychain == true {
            // BatchMode cannot distinguish a rejected key from an encrypted key
            // that first needs macOS Keychain interaction. Avoid a false red state.
            authentication = .interactionRequired
        }
        return SSHStatus(
            executableAvailable: true,
            configuration: configuration,
            route: route,
            agent: agent,
            authentication: authentication,
            lastTestedAt: Date()
        )
    }

    func testConnection(sshURL: URL, expectedAccount: String?) async -> SSHAuthenticationState {
        let result = await runner.run(CommandRequest(
            executableURL: sshURL,
            arguments: [
                "-T",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=10",
                "-o", "ConnectionAttempts=1",
                "-o", "StrictHostKeyChecking=yes",
                "git@github.com"
            ],
            timeout: .seconds(15),
            maximumOutputBytes: 64 * 1_024
        ))
        return connectionParser.parse(
            exitStatus: result.exitStatus,
            output: result.standardOutput + "\n" + result.standardError,
            timedOut: result.timedOut,
            expectedAccount: expectedAccount
        )
    }

    func repair(executables: ResolvedExecutables, activeAccount: String?) async -> RepairOutcome {
        let initial = await inspect(executables: executables, activeAccount: activeAccount)
        if initial.isReady { return .notRequired }
        guard initial.route == .ready else {
            return .blocked("SSH route is not ready. Review the required ssh.github.com:443 configuration in Details.")
        }
        guard initial.agent == .noIdentities else {
            return .blocked("SSH could not authenticate without interaction. Load the key from macOS Keychain and try again.")
        }
        guard let sshAddURL = executables.sshAdd,
              let identity = initial.configuration?.identityFiles.first(where: { $0.hasSuffix("/id_ed25519") }),
              let expandedIdentity = expandedPath(identity),
              FileManager.default.fileExists(atPath: expandedIdentity) else {
            return .blocked("The expected id_ed25519 identity is not available.")
        }

        let addResult = await runner.run(CommandRequest(
            executableURL: sshAddURL,
            arguments: ["--apple-use-keychain", expandedIdentity],
            timeout: .seconds(15),
            maximumOutputBytes: 32 * 1_024
        ))
        guard addResult.succeeded else {
            return .failed("The key could not be loaded non-interactively. Load it from macOS Keychain, then try again.")
        }
        let final = await inspect(executables: executables, activeAccount: activeAccount)
        return final.isReady ? .completed : .failed("SSH authentication is still not confirmed after loading the key.")
    }

    func classifyRoute(
        _ configuration: EffectiveSSHConfiguration,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> SSHRouteState {
        guard configuration.hostname?.lowercased() == "ssh.github.com" else {
            return .malformed("Effective SSH host must be ssh.github.com")
        }
        guard configuration.port == 443 else {
            return .malformed("Effective SSH port must be 443")
        }
        guard configuration.user?.lowercased() == "git" else {
            return .malformed("Effective SSH user must be git")
        }
        guard let identity = configuration.identityFiles.first(where: { $0.hasSuffix("/id_ed25519") }),
              let expanded = expandedPath(identity), fileExists(expanded) else {
            return .identityMissing("id_ed25519")
        }
        return .ready
    }

    private func inspectAgent(_ sshAddURL: URL?) async -> SSHAgentState {
        guard let sshAddURL else { return .unavailable }
        let result = await runner.run(CommandRequest(
            executableURL: sshAddURL,
            arguments: ["-l"],
            timeout: .seconds(5),
            maximumOutputBytes: 32 * 1_024
        ))
        return agentParser.parse(
            exitStatus: result.exitStatus,
            output: result.standardOutput + "\n" + result.standardError
        )
    }

    private func expandedPath(_ path: String) -> String? {
        if path == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path.hasPrefix("/") ? path : nil
    }
}
