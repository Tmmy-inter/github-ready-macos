import Foundation

struct EffectiveSSHConfiguration: Sendable, Equatable {
    var hostname: String?
    var port: Int?
    var user: String?
    var identityFiles: [String]
    var identitiesOnly: Bool?
    var addKeysToAgent: Bool?
    var useKeychain: Bool?

    var primaryIdentityFilename: String? {
        identityFiles.first.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    var safeEndpoint: String {
        guard let hostname, let port else { return "Unknown" }
        return "\(hostname):\(port)"
    }
}

enum SSHRouteState: Sendable, Equatable {
    case ready
    case executableMissing
    case inspectionFailed
    case malformed(String)
    case identityMissing(String)

    var displayName: String {
        switch self {
        case .ready: "SSH over 443 ready"
        case .executableMissing: "System SSH unavailable"
        case .inspectionFailed: "SSH configuration unavailable"
        case .malformed(let reason): reason
        case .identityMissing: "SSH identity file missing"
        }
    }
}

enum SSHAgentState: Sendable, Equatable {
    case identityLoaded
    case noIdentities
    case unavailable
    case failed

    var displayName: String {
        switch self {
        case .identityLoaded: "Key loaded"
        case .noIdentities: "No keys currently loaded"
        case .unavailable: "SSH agent unavailable"
        case .failed: "SSH agent status unavailable"
        }
    }
}

enum SSHAuthenticationState: Sendable, Equatable {
    case verified(account: String?)
    case notTested
    case networkUnavailable(NetworkFailure)
    case rejected
    case hostVerificationProblem
    case interactionRequired
    case failed

    var displayName: String {
        switch self {
        case .verified: "Authentication verified"
        case .notTested: "Not tested"
        case .networkUnavailable(let failure): failure.displayName
        case .rejected: "SSH authentication rejected"
        case .hostVerificationProblem: "Host key verification required"
        case .interactionRequired: "Key interaction required"
        case .failed: "SSH authentication not confirmed"
        }
    }
}

struct SSHStatus: Sendable, Equatable {
    var executableAvailable: Bool
    var configuration: EffectiveSSHConfiguration?
    var route: SSHRouteState
    var agent: SSHAgentState
    var authentication: SSHAuthenticationState
    var lastTestedAt: Date?

    static let unavailable = SSHStatus(
        executableAvailable: false,
        configuration: nil,
        route: .executableMissing,
        agent: .unavailable,
        authentication: .notTested,
        lastTestedAt: nil
    )

    var isReady: Bool {
        guard route == .ready else { return false }
        if case .verified = authentication { return true }
        return false
    }

    var safeProtocolSummary: String {
        guard route == .ready, let configuration else { return route.displayName }
        return "SSH (\(configuration.safeEndpoint))"
    }
}
