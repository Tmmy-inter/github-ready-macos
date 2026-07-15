import AppKit
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var snapshot: HealthSnapshot = .checking
    @Published private(set) var isChecking = false
    @Published private(set) var isActionRunning = false
    @Published var actionMessage: String?

    private let healthService: HealthCheckService
    private let logger: SafeLogger
    private let diagnosticsBuilder: DiagnosticsBuilder

    init(
        healthService: HealthCheckService = HealthCheckService(),
        logger: SafeLogger = .shared,
        diagnosticsBuilder: DiagnosticsBuilder = DiagnosticsBuilder()
    ) {
        self.healthService = healthService
        self.logger = logger
        self.diagnosticsBuilder = diagnosticsBuilder
    }

    func refresh() async {
        guard !isChecking else { return }
        isChecking = true
        actionMessage = nil
        snapshot.visualState = .checking
        let updatedSnapshot = await healthService.check()
        snapshot = updatedSnapshot
        isChecking = false
    }

    func testConnection() async {
        guard !isActionRunning else { return }
        isActionRunning = true
        let result = await healthService.testConnection(current: snapshot)
        actionMessage = result.message
        snapshot.lastConnectionTest = result.message
        isActionRunning = false
    }

    func repairHTTPS() async {
        guard !isActionRunning else { return }
        isActionRunning = true
        let outcome = await healthService.repairHTTPS(current: snapshot)
        switch outcome {
        case .notRequired:
            actionMessage = "No repair required."
        case .completed:
            actionMessage = "HTTPS integration repaired."
            snapshot = await healthService.check()
        case .blocked(let message), .failed(let message):
            actionMessage = message
        }
        isActionRunning = false
    }

    func repairActiveProtocol() async {
        if snapshot.activeProtocol == .https {
            await repairHTTPS()
            return
        }
        guard snapshot.activeProtocol == .ssh else {
            actionMessage = "The active protocol is unknown."
            return
        }
        guard !isActionRunning else { return }
        isActionRunning = true
        let outcome = await healthService.repairSSH(current: snapshot)
        switch outcome {
        case .notRequired:
            actionMessage = "No SSH repair required."
        case .completed:
            actionMessage = "SSH key reloaded and authentication verified."
            snapshot = await healthService.check()
        case .blocked(let message), .failed(let message):
            actionMessage = message
        }
        isActionRunning = false
    }

    func switchProtocol(to target: GitHubProtocol) async {
        guard !isActionRunning else { return }
        guard target != snapshot.activeProtocol else {
            actionMessage = "\(target.displayName) is already active."
            return
        }
        isActionRunning = true
        let outcome = await healthService.switchProtocol(to: target, userConfirmed: true)
        switch outcome {
        case .completed:
            actionMessage = "Preferred protocol changed to \(target.displayName). Existing repository remotes were not changed."
            snapshot = await healthService.check()
        case .blocked(let message), .failed(let message):
            actionMessage = message
        }
        isActionRunning = false
    }

    func logIn() async {
        guard !isActionRunning else { return }
        isActionRunning = true
        let outcome = await healthService.logIn()
        switch outcome {
        case .completed:
            actionMessage = "GitHub login completed."
            snapshot = await healthService.check()
        case .cancelled:
            actionMessage = "GitHub login was cancelled."
        case .failed(let message):
            actionMessage = message
        }
        isActionRunning = false
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard !isActionRunning else { return }
        guard snapshot.applicationLocation.allowsLaunchAtLogin else {
            actionMessage = "Install GitHub Ready in ~/Applications before enabling Launch at Login."
            return
        }
        isActionRunning = true
        do {
            snapshot.launchAtLogin = try await healthService.setLaunchAtLogin(
                enabled: enabled,
                location: snapshot.applicationLocation
            )
            actionMessage = enabled ? "Launch at Login enabled." : "Launch at Login disabled."
        } catch {
            actionMessage = error.localizedDescription
        }
        isActionRunning = false
    }

    func copySafeDiagnostics() async {
        let recentLogs = await logger.readRecent()
        let diagnostics = diagnosticsBuilder.build(snapshot: snapshot, recentErrors: recentLogs)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnostics, forType: .string)
        actionMessage = "Safe diagnostics copied."
    }

    func readRecentLogs() async -> String {
        await logger.readRecent()
    }

    func openLogs() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GitHubReady", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch {
            actionMessage = "The local log directory could not be opened."
        }
    }

    func openGitHub() {
        guard let url = URL(string: "https://github.com") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
