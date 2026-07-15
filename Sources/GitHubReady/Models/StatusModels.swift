import Foundation

enum NetworkFailure: String, Sendable, Equatable {
    case dns
    case tls
    case timeout
    case proxyOrVPN
    case githubUnavailable
    case rateLimited
    case permissionDenied
    case unknown

    var displayName: String {
        switch self {
        case .dns: "DNS unavailable"
        case .tls: "TLS connection failed"
        case .timeout: "Connection timed out"
        case .proxyOrVPN: "Network or VPN unavailable"
        case .githubUnavailable: "GitHub unavailable"
        case .rateLimited: "GitHub rate limited"
        case .permissionDenied: "Permission denied"
        case .unknown: "Authentication not confirmed"
        }
    }
}

enum AuthenticationState: Sendable, Equatable {
    case authenticated(account: String, additionalAccounts: Int, protocolName: String)
    case invalid(reason: String)
    case unavailable(NetworkFailure)
    case noConfiguredAccount
    case noActiveAccount
    case credentialStoreUnavailable
    case malformed
    case timedOut
    case cliMissing

    var displayName: String {
        switch self {
        case .authenticated: "Authenticated"
        case .invalid: "Authentication invalid"
        case .unavailable(let failure): failure.displayName
        case .noConfiguredAccount: "No configured account"
        case .noActiveAccount: "No active account"
        case .credentialStoreUnavailable: "Credential store unavailable"
        case .malformed: "Authentication status unavailable"
        case .timedOut: "Authentication check timed out"
        case .cliMissing: "GitHub CLI not installed"
        }
    }

    var activeAccount: String? {
        guard case .authenticated(let account, _, _) = self else { return nil }
        return account
    }

    var protocolName: String? {
        guard case .authenticated(_, _, let protocolName) = self else { return nil }
        return protocolName
    }
}

enum CredentialHelperState: Sendable, Equatable {
    case valid(helperPath: String)
    case systemKeychainOnly
    case missing
    case malformed(String)
    case gitMissing

    var displayName: String {
        switch self {
        case .valid: "GitHub CLI helper ready"
        case .systemKeychainOnly: "GitHub helper not configured"
        case .missing: "HTTPS helper missing"
        case .malformed: "HTTPS helper malformed"
        case .gitMissing: "Git not installed"
        }
    }

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

enum LaunchAtLoginState: String, Sendable, Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unsupported
    case error

    var displayName: String {
        switch self {
        case .enabled: "Enabled"
        case .notRegistered: "Not registered"
        case .requiresApproval: "Requires approval"
        case .notFound: "Application not found"
        case .unsupported: "Unsupported"
        case .error: "Status unavailable"
        }
    }
}

enum ApplicationLocationState: Sendable, Equatable {
    case stable
    case developmentDist
    case developmentBuild
    case unexpected

    var allowsLaunchAtLogin: Bool { self == .stable }

    var displayName: String {
        switch self {
        case .stable: "Installed"
        case .developmentDist: "Development bundle"
        case .developmentBuild: "Swift build output"
        case .unexpected: "Unstable application path"
        }
    }
}

enum MenuVisualState: String, Sendable, Equatable {
    case ready
    case checking
    case partial
    case networkUnavailable
    case authenticationRequired
    case cliMissing

    var title: String {
        switch self {
        case .ready: "Ready"
        case .checking: "Checking"
        case .partial: "Partial Configuration"
        case .networkUnavailable: "Network Unavailable"
        case .authenticationRequired: "Authentication Required"
        case .cliMissing: "GitHub CLI Not Installed"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath.circle.fill"
        case .partial: "exclamationmark.triangle.fill"
        case .networkUnavailable: "network.slash"
        case .authenticationRequired: "xmark.octagon.fill"
        case .cliMissing: "questionmark.circle.fill"
        }
    }
}

struct HealthSnapshot: Sendable, Equatable {
    var visualState: MenuVisualState
    var authentication: AuthenticationState
    var activeProtocol: GitHubProtocol
    var helper: CredentialHelperState
    var ssh: SSHStatus
    var gitPath: String?
    var ghPath: String?
    var gitVersion: String?
    var ghVersion: String?
    var launchAtLogin: LaunchAtLoginState
    var applicationLocation: ApplicationLocationState
    var lastCheckedAt: Date?
    var lastConnectionTest: String?
    var recentError: String?

    static let checking = HealthSnapshot(
        visualState: .checking,
        authentication: .malformed,
        activeProtocol: .unknown,
        helper: .missing,
        ssh: .unavailable,
        gitPath: nil,
        ghPath: nil,
        gitVersion: nil,
        ghVersion: nil,
        launchAtLogin: .notRegistered,
        applicationLocation: .unexpected,
        lastCheckedAt: nil,
        lastConnectionTest: nil,
        recentError: nil
    )
}

struct CredentialHelperEntry: Sendable, Equatable {
    enum Scope: String, Sendable {
        case system
        case global
        case local
    }

    let scope: Scope
    let key: String
    let value: String
}
