import SwiftUI

struct DetailStatusView: View {
    @ObservedObject var store: AppStore
    @State private var recentLogs = "Loading sanitized logs…"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GitHub Ready Details")
                        .font(.title2.bold())
                    Text(store.snapshot.visualState.title)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Again") { Task { await store.refresh() } }
            }

            GroupBox("GitHub CLI account") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    detailRow("Authentication", store.snapshot.authentication.displayName)
                    detailRow("Active account", store.snapshot.authentication.activeAccount ?? "None")
                    detailRow("GitHub CLI", store.snapshot.ghPath ?? "Not found")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("Active protocol") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        detailRow("Preferred", store.snapshot.activeProtocol.displayName)
                        detailRow("Primary status", store.snapshot.visualState.title)
                        detailRow("Last test", store.snapshot.lastConnectionTest ?? "Not tested")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                GroupBox("HTTPS status") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    detailRow("HTTPS helper", store.snapshot.helper.displayName)
                        detailRow("Fallback", store.snapshot.activeProtocol == .https ? "Active" : "Available")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            GroupBox("SSH status") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    detailRow("Authentication", store.snapshot.ssh.authentication.displayName)
                    detailRow("Effective route", store.snapshot.ssh.configuration?.safeEndpoint ?? "Unknown")
                    detailRow("User", store.snapshot.ssh.configuration?.user ?? "Unknown")
                    detailRow("Identity", store.snapshot.ssh.configuration?.primaryIdentityFilename ?? "Unknown")
                    detailRow("Agent", store.snapshot.ssh.agent.displayName)
                    detailRow("Route status", store.snapshot.ssh.route.displayName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Application") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    detailRow("Launch at Login", store.snapshot.launchAtLogin.displayName)
                    detailRow("Application path", store.snapshot.applicationLocation.displayName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Privacy-safe local logs") {
                ScrollView {
                    Text(recentLogs)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 130)
            }

            HStack {
                Button("Refresh Logs") { Task { recentLogs = await store.readRecentLogs() } }
                Button("Open Logs") { store.openLogs() }
                Button("Copy Diagnostics") { Task { await store.copySafeDiagnostics() } }
                Spacer()
            }
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 720)
        .task { recentLogs = await store.readRecentLogs() }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
