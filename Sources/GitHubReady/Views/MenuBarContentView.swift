import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: AppStore
    let fixedWidth: CGFloat?
    @Environment(\.openWindow) private var openWindow
    @State private var showRepairConfirmation = false
    @State private var showLoginConfirmation = false
    @State private var protocolSwitchTarget: GitHubProtocol?
    @State private var activeActionTitle: String?

    init(store: AppStore, fixedWidth: CGFloat? = 400) {
        self.store = store
        self.fixedWidth = fixedWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            statusRows
            if let message = store.actionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Action result: \(message)")
            }
            Divider()
            actionGrid
            Divider()
            launchAtLoginControl
            footerActions
        }
        .padding(14)
        .frame(width: fixedWidth)
        .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
        .onChange(of: store.isChecking) { isChecking in
            if !isChecking {
                activeActionTitle = nil
            }
        }
        .onChange(of: store.isActionRunning) { isActionRunning in
            if !isActionRunning {
                activeActionTitle = nil
            }
        }
        .alert(repairAlertTitle, isPresented: $showRepairConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Repair") {
                Task { await store.repairActiveProtocol() }
            }
        } message: {
            Text(repairConfirmationMessage)
        }
        .alert("Log In to GitHub?", isPresented: $showLoginConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                Task { await store.logIn() }
            }
        } message: {
            Text(loginConfirmationMessage)
        }
        .alert("Change Preferred Protocol?", isPresented: Binding(
            get: { protocolSwitchTarget != nil },
            set: { if !$0 { protocolSwitchTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { protocolSwitchTarget = nil }
            Button("Change") {
                guard let target = protocolSwitchTarget else { return }
                protocolSwitchTarget = nil
                Task { await store.switchProtocol(to: target) }
            }
        } message: {
            Text("GitHub CLI will prefer \(protocolSwitchTarget?.displayName ?? "the selected protocol") for future clone and push workflows. Existing repository remote URLs will not be rewritten.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandLogo(state: store.snapshot.visualState, size: 34, showsPulse: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub Ready")
                    .font(.headline)
                Text(store.snapshot.visualState.title)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if store.isChecking || store.isActionRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var statusRows: some View {
        VStack(spacing: 5) {
            StatusRow(label: "Account", value: accountName)
            StatusRow(label: "Active protocol", value: activeProtocolSummary)
            StatusRow(label: "GitHub CLI", value: store.snapshot.ghVersion ?? "Not installed")
            StatusRow(label: "Git", value: store.snapshot.gitVersion ?? "Not installed")
            StatusRow(label: "GitHub authentication", value: store.snapshot.authentication.displayName)
            StatusRow(label: "Active protocol status", value: activeProtocolStatus)
            StatusRow(label: "Last checked", value: formattedLastChecked)
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: actionColumns, spacing: 6) {
            actionButton("Check Again") { Task { await store.refresh() } }
            actionButton("Test Connection") { Task { await store.testConnection() } }
            actionButton(protocolSwitchTitle) {
                protocolSwitchTarget = store.snapshot.activeProtocol.switchTarget
            }
            .disabled(store.snapshot.activeProtocol.switchTarget == nil)

            actionButton(repairButtonTitle) { showRepairConfirmation = true }
            actionButton("Copy Diagnostics") { Task { await store.copySafeDiagnostics() } }
            actionButton("Open Details") { openWindow(id: "details") }

            if store.snapshot.visualState == .authenticationRequired {
                actionButton("Log In to GitHub") { showLoginConfirmation = true }
            }
        }
        .disabled(store.isChecking || store.isActionRunning)
    }

    private var actionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 3)
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            activeActionTitle = title
            action()
            Task { @MainActor in
                await Task.yield()
                if !store.isChecking && !store.isActionRunning {
                    activeActionTitle = nil
                }
            }
        } label: {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(ActionPillButtonStyle(isActive: activeActionTitle == title))
        .focusable(false)
    }

    private var launchAtLoginControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { store.snapshot.launchAtLogin == .enabled },
                    set: { newValue in Task { await store.setLaunchAtLogin(newValue) } }
                )
            )
            .toggleStyle(CompactCheckboxToggleStyle())
            .disabled(!store.snapshot.applicationLocation.allowsLaunchAtLogin || store.isActionRunning)
            if !store.snapshot.applicationLocation.allowsLaunchAtLogin {
                Text("Install in ~/Applications to enable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if store.snapshot.launchAtLogin == .requiresApproval {
                Text("Approve in System Settings → Login Items.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var footerActions: some View {
        HStack {
            footerActionButton("Open Logs") { store.openLogs() }
            footerActionButton("Open GitHub") { store.openGitHub() }
            Spacer()
            footerActionButton("Quit") { store.quit() }
        }
        .font(.caption)
    }

    private func footerActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(FooterActionButtonStyle())
        .focusable(false)
    }

    private var accountName: String {
        guard case .authenticated(let account, let additionalAccounts, _) = store.snapshot.authentication else {
            return "None"
        }
        return additionalAccounts > 0 ? "\(account) (+\(additionalAccounts))" : account
    }

    private var formattedLastChecked: String {
        store.snapshot.lastCheckedAt?.formatted(date: .omitted, time: .standard) ?? "Never"
    }

    private var loginConfirmationMessage: String {
        if case .authenticated = store.snapshot.authentication {
            return "A valid account is already active. Continuing may replace or add GitHub CLI credentials. The browser flow starts only after you confirm."
        }
        return "GitHub Ready will start the GitHub CLI browser login flow for github.com using HTTPS."
    }

    private var activeProtocolSummary: String {
        if store.snapshot.activeProtocol == .ssh, store.snapshot.ssh.route == .ready {
            return store.snapshot.ssh.safeProtocolSummary
        }
        return store.snapshot.activeProtocol.displayName
    }

    private var activeProtocolStatus: String {
        switch store.snapshot.activeProtocol {
        case .https: store.snapshot.helper.displayName
        case .ssh: store.snapshot.ssh.authentication.displayName
        case .unknown: "Protocol unavailable"
        }
    }

    private var protocolSwitchTitle: String {
        switch store.snapshot.activeProtocol {
        case .https: "Use SSH"
        case .ssh: "Use HTTPS"
        case .unknown: "Switch Protocol"
        }
    }

    private var repairButtonTitle: String {
        store.snapshot.activeProtocol == .ssh ? "Repair SSH" : "Repair HTTPS"
    }

    private var repairAlertTitle: String {
        store.snapshot.activeProtocol == .ssh ? "Repair SSH?" : "Repair HTTPS Integration?"
    }

    private var repairConfirmationMessage: String {
        if store.snapshot.activeProtocol == .ssh {
            return "GitHub Ready will re-inspect SSH, test GitHub, and only if needed try to load id_ed25519 with the system ssh-add. It will not modify SSH config, known_hosts, Keychain, or repository remotes."
        }
        return "GitHub Ready will run gh auth setup-git for github.com, then recheck the HTTPS helper configuration."
    }

    private var statusColor: Color {
        switch store.snapshot.visualState {
        case .ready: .green
        case .checking: .blue
        case .partial: .yellow
        case .networkUnavailable: .orange
        case .authenticationRequired: .red
        case .cliMissing: .gray
        }
    }

}

private struct ActionPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isHighlighted = isActive || configuration.isPressed

        configuration.label
            .font(.caption)
            .fontWeight(.regular)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Capsule())
            .background {
                Capsule()
                    .fill(isHighlighted ? Color.primary.opacity(0.16) : Color.primary.opacity(0.09))
            }
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }
}

private struct CompactCheckboxToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)

                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct FooterActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.13) : .clear)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
