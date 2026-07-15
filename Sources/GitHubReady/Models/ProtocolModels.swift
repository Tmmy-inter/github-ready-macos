import Foundation

enum GitHubProtocol: String, Sendable, Equatable, CaseIterable {
    case https
    case ssh
    case unknown

    init(commandOutput: String) {
        switch commandOutput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "https": self = .https
        case "ssh": self = .ssh
        default: self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .https: "HTTPS"
        case .ssh: "SSH"
        case .unknown: "Unknown"
        }
    }

    var switchTarget: GitHubProtocol? {
        switch self {
        case .https: .ssh
        case .ssh: .https
        case .unknown: nil
        }
    }
}

struct ProtocolSwitchCommand: Sendable, Equatable {
    let arguments: [String]

    init?(target: GitHubProtocol, userConfirmed: Bool) {
        guard userConfirmed, target == .https || target == .ssh else { return nil }
        arguments = ["config", "set", "git_protocol", target.rawValue, "--host", "github.com"]
    }
}
