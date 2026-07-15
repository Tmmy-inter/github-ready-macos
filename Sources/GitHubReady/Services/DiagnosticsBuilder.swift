import Foundation

struct DiagnosticsBuilder: Sendable {
    private let redactor = SensitiveValueRedactor()

    func build(snapshot: HealthSnapshot, recentErrors: String) -> String {
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif

        let lines = [
            "GitHub Ready Diagnostics",
            "Application version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(architecture)",
            "Git path: \(snapshot.gitPath ?? "not found")",
            "GitHub CLI path: \(snapshot.ghPath ?? "not found")",
            "Git version: \(snapshot.gitVersion ?? "unknown")",
            "GitHub CLI version: \(snapshot.ghVersion ?? "unknown")",
            "Authentication: \(snapshot.authentication.displayName)",
            "Active GitHub CLI protocol: \(snapshot.activeProtocol.displayName)",
            "HTTPS helper: \(snapshot.helper.displayName)",
            "SSH executable available: \(snapshot.ssh.executableAvailable ? "yes" : "no")",
            "Effective SSH host: \(snapshot.ssh.configuration?.hostname ?? "unknown")",
            "Effective SSH port: \(snapshot.ssh.configuration?.port.map(String.init) ?? "unknown")",
            "Effective SSH user: \(snapshot.ssh.configuration?.user ?? "unknown")",
            "SSH identity filename: \(snapshot.ssh.configuration?.primaryIdentityFilename ?? "unknown")",
            "SSH route: \(snapshot.ssh.route.displayName)",
            "SSH agent: \(snapshot.ssh.agent.displayName)",
            "SSH authentication: \(snapshot.ssh.authentication.displayName)",
            "SSH over port 443 active: \(snapshot.activeProtocol == .ssh && snapshot.ssh.route == .ready ? "yes" : "no")",
            "Overall status: \(snapshot.visualState.title)",
            "Launch at Login: \(snapshot.launchAtLogin.displayName)",
            "Application location: \(snapshot.applicationLocation.displayName)",
            "Last checked: \(snapshot.lastCheckedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "never")",
            "Recent sanitized errors:",
            recentErrors
        ]
        return redactor.redact(lines.joined(separator: "\n"))
    }
}
