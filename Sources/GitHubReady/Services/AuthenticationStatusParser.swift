import Foundation

struct AuthenticationStatusParser: Sendable {
    private let networkClassifier = NetworkErrorClassifier()

    func parse(
        json: String,
        supplementaryOutput: String = "",
        timedOut: Bool = false,
        fatalClassification: CommandErrorClassification? = nil
    ) -> AuthenticationState {
        if timedOut || fatalClassification == .timeout { return .timedOut }

        if let networkFailure = networkClassifier.classify(supplementaryOutput) {
            return .unavailable(networkFailure)
        }
        if networkClassifier.explicitlyRejectsAuthentication(supplementaryOutput) {
            return .invalid(reason: "GitHub rejected the current credential.")
        }
        if credentialStoreUnavailable(supplementaryOutput) {
            return .credentialStoreUnavailable
        }
        if let fatalClassification, fatalClassification != .none, json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mapFatalClassification(fatalClassification)
        }

        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(AuthEnvelope.self, from: data) else {
            return .malformed
        }

        guard let accounts = envelope.hosts["github.com"], !accounts.isEmpty else {
            return .noConfiguredAccount
        }

        let activeAccounts = accounts.filter { $0.active == true }
        guard activeAccounts.count == 1, let active = activeAccounts.first else {
            return activeAccounts.isEmpty ? .noActiveAccount : .malformed
        }

        guard let login = active.login?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty,
              let protocolName = active.gitProtocol?.trimmingCharacters(in: .whitespacesAndNewlines), !protocolName.isEmpty,
              let state = active.state?.lowercased() else {
            return .malformed
        }

        if state == "success" {
            return .authenticated(
                account: login,
                additionalAccounts: max(0, accounts.count - 1),
                protocolName: protocolName
            )
        }

        let explicitError = [active.error, supplementaryOutput]
            .compactMap { $0 }
            .joined(separator: "\n")
        if networkClassifier.explicitlyRejectsAuthentication(explicitError) {
            return .invalid(reason: "GitHub rejected the current credential.")
        }
        if let networkFailure = networkClassifier.classify(explicitError) {
            return .unavailable(networkFailure)
        }

        // A non-success JSON state without a specific rejection signal can also
        // be caused by a transient network failure. Keep it orange, not red.
        return .unavailable(.unknown)
    }

    private func credentialStoreUnavailable(_ text: String) -> Bool {
        let value = text.lowercased()
        let mentionsStore = value.contains("keychain") || value.contains("keyring") || value.contains("credential store")
        let indicatesFailure = value.contains("locked") || value.contains("unavailable") || value.contains("could not") || value.contains("failed")
        return mentionsStore && indicatesFailure
    }

    private func mapFatalClassification(_ classification: CommandErrorClassification) -> AuthenticationState {
        switch classification {
        case .dns: .unavailable(.dns)
        case .tls: .unavailable(.tls)
        case .network: .unavailable(.proxyOrVPN)
        case .permission: .unavailable(.permissionDenied)
        case .authentication: .invalid(reason: "GitHub rejected the current credential.")
        case .timeout: .timedOut
        case .executableMissing: .cliMissing
        default: .malformed
        }
    }
}

private struct AuthEnvelope: Decodable {
    let hosts: [String: [AuthAccount]]
}

private struct AuthAccount: Decodable {
    let active: Bool?
    let gitProtocol: String?
    let host: String?
    let login: String?
    let state: String?
    let tokenSource: String?
    let error: String?
}
