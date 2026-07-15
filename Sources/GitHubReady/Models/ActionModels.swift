import Foundation

struct ConnectionTestResult: Sendable, Equatable {
    let succeeded: Bool
    let networkFailure: NetworkFailure?
    let authenticationRejected: Bool
    let duration: TimeInterval
    let message: String
}

enum RepairOutcome: Sendable, Equatable {
    case notRequired
    case completed
    case blocked(String)
    case failed(String)
}

enum LoginOutcome: Sendable, Equatable {
    case completed
    case cancelled
    case failed(String)
}

enum ProtocolSwitchOutcome: Sendable, Equatable {
    case completed
    case blocked(String)
    case failed(String)
}
