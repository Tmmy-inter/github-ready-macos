import Foundation

enum CommandErrorClassification: String, Sendable, Equatable {
    case none
    case executableMissing
    case executableNotAllowed
    case timeout
    case dns
    case tls
    case network
    case authentication
    case permission
    case malformedOutput
    case launchFailure
    case nonZeroExit
}

struct CommandRequest: Sendable, Equatable {
    let executableURL: URL
    let arguments: [String]
    let timeout: Duration
    let maximumOutputBytes: Int
    let environmentOverrides: [String: String]

    init(
        executableURL: URL,
        arguments: [String],
        timeout: Duration = .seconds(15),
        maximumOutputBytes: Int = 256 * 1_024,
        environmentOverrides: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
        self.maximumOutputBytes = max(1_024, maximumOutputBytes)
        self.environmentOverrides = environmentOverrides
    }
}

struct CommandResult: Sendable, Equatable {
    let executablePath: String
    let sanitizedArguments: [String]
    let exitStatus: Int32
    let standardOutput: String
    let standardError: String
    let duration: TimeInterval
    let timedOut: Bool
    let outputTruncated: Bool
    let errorClassification: CommandErrorClassification

    var succeeded: Bool {
        exitStatus == 0 && !timedOut && errorClassification == .none
    }
}
