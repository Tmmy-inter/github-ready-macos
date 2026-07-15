import Foundation

struct StatusClassifier: Sendable {
    func classify(
        checking: Bool = false,
        authentication: AuthenticationState,
        activeProtocol: GitHubProtocol,
        helper: CredentialHelperState,
        gitInstalled: Bool,
        ssh: SSHStatus
    ) -> MenuVisualState {
        if checking { return .checking }

        switch authentication {
        case .cliMissing:
            return .cliMissing
        case .invalid, .noConfiguredAccount, .noActiveAccount:
            return .authenticationRequired
        case .credentialStoreUnavailable:
            return .partial
        case .unavailable, .timedOut, .malformed:
            return .networkUnavailable
        case .authenticated:
            guard gitInstalled else { return .partial }
            switch activeProtocol {
            case .https:
                return helper.isValid ? .ready : .partial
            case .ssh:
                guard ssh.route == .ready else { return .partial }
                switch ssh.authentication {
                case .verified: return .ready
                case .networkUnavailable: return .networkUnavailable
                case .rejected: return .authenticationRequired
                case .hostVerificationProblem, .interactionRequired, .notTested: return .partial
                case .failed: return .networkUnavailable
                }
            case .unknown:
                return .partial
            }
        }
    }
}
