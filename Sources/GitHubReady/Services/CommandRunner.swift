@preconcurrency import Foundation
import Darwin

struct CommandRunner: Sendable {
    private let allowedExecutablePaths: Set<String>
    private let redactor: SensitiveValueRedactor

    init(
        allowedExecutablePaths: Set<String>,
        redactor: SensitiveValueRedactor = SensitiveValueRedactor()
    ) {
        self.allowedExecutablePaths = allowedExecutablePaths
        self.redactor = redactor
    }

    func run(_ request: CommandRequest) async -> CommandResult {
        let path = request.executableURL.standardizedFileURL.path
        let sanitizedArguments = redactor.sanitizeArguments(request.arguments)

        guard request.executableURL.isFileURL, path.hasPrefix("/") else {
            return failureResult(
                path: path,
                arguments: sanitizedArguments,
                classification: .executableNotAllowed,
                message: "Executable path must be absolute."
            )
        }
        guard allowedExecutablePaths.contains(path) else {
            return failureResult(
                path: path,
                arguments: sanitizedArguments,
                classification: .executableNotAllowed,
                message: "Executable is not in the allowlist."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return failureResult(
                path: path,
                arguments: sanitizedArguments,
                classification: .executableMissing,
                message: "Executable not found."
            )
        }

        return await Task.detached(priority: .userInitiated) {
            Self.execute(
                request,
                sanitizedArguments: sanitizedArguments,
                redactor: redactor
            )
        }.value
    }

    private static func execute(
        _ request: CommandRequest,
        sanitizedArguments: [String],
        redactor: SensitiveValueRedactor
    ) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let output = BoundedOutput(maximumBytes: request.maximumOutputBytes)
        let completion = DispatchSemaphore(value: 0)
        let startedAt = ContinuousClock.now

        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        process.environment = safeEnvironment(overrides: request.environmentOverrides)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData, stream: .standardOutput)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData, stream: .standardError)
        }
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            return CommandResult(
                executablePath: request.executableURL.path,
                sanitizedArguments: sanitizedArguments,
                exitStatus: -1,
                standardOutput: "",
                standardError: redactor.redact(error.localizedDescription),
                duration: elapsedSeconds(since: startedAt),
                timedOut: false,
                outputTruncated: false,
                errorClassification: .launchFailure
            )
        }

        let timeoutSeconds = max(0.1, request.timeout.timeInterval)
        let timedOut = completion.wait(timeout: .now() + timeoutSeconds) == .timedOut
        if timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 2) == .timedOut {
                process.interrupt()
                if completion.wait(timeout: .now() + 1) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = completion.wait(timeout: .now() + 1)
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        output.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), stream: .standardOutput)
        output.append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), stream: .standardError)

        let captured = output.snapshot()
        let stdout = redactor.redact(String(decoding: captured.stdout, as: UTF8.self))
        let stderr = redactor.redact(String(decoding: captured.stderr, as: UTF8.self))
        let exitStatus = process.isRunning ? -1 : process.terminationStatus
        let classification = classify(
            exitStatus: exitStatus,
            timedOut: timedOut,
            output: stdout + "\n" + stderr
        )

        return CommandResult(
            executablePath: request.executableURL.path,
            sanitizedArguments: sanitizedArguments,
            exitStatus: exitStatus,
            standardOutput: stdout,
            standardError: stderr,
            duration: elapsedSeconds(since: startedAt),
            timedOut: timedOut,
            outputTruncated: captured.truncated,
            errorClassification: classification
        )
    }

    private func failureResult(
        path: String,
        arguments: [String],
        classification: CommandErrorClassification,
        message: String
    ) -> CommandResult {
        CommandResult(
            executablePath: path,
            sanitizedArguments: arguments,
            exitStatus: -1,
            standardOutput: "",
            standardError: message,
            duration: 0,
            timedOut: false,
            outputTruncated: false,
            errorClassification: classification
        )
    }

    private static func safeEnvironment(overrides: [String: String]) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let permittedKeys = [
            "HOME", "TMPDIR", "LANG", "LC_ALL", "SSH_AUTH_SOCK",
            "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
            "XDG_CONFIG_HOME", "GH_CONFIG_DIR"
        ]
        var environment = permittedKeys.reduce(into: [String: String]()) { result, key in
            if let value = source[key] { result[key] = value }
        }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment.merge(overrides) { _, new in new }
        return environment
    }

    private static func classify(
        exitStatus: Int32,
        timedOut: Bool,
        output: String
    ) -> CommandErrorClassification {
        if timedOut { return .timeout }
        if exitStatus == 0 { return .none }

        let classifier = NetworkErrorClassifier()
        if classifier.explicitlyRejectsAuthentication(output) { return .authentication }
        switch classifier.classify(output) {
        case .dns: return .dns
        case .tls: return .tls
        case .permissionDenied: return .permission
        case .proxyOrVPN, .githubUnavailable, .rateLimited: return .network
        case .timeout: return .timeout
        case .unknown, .none: return .nonZeroExit
        }
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        start.duration(to: .now).timeInterval
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

private final class BoundedOutput: @unchecked Sendable {
    enum Stream { case standardOutput, standardError }

    private let lock = NSLock()
    private let maximumBytes: Int
    private var stdout = Data()
    private var stderr = Data()
    private var truncated = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ data: Data, stream: Stream) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        let used = stdout.count + stderr.count
        let remaining = maximumBytes - used
        guard remaining > 0 else {
            truncated = true
            return
        }

        let accepted = data.prefix(remaining)
        switch stream {
        case .standardOutput: stdout.append(accepted)
        case .standardError: stderr.append(accepted)
        }
        if accepted.count < data.count { truncated = true }
    }

    func snapshot() -> (stdout: Data, stderr: Data, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (stdout, stderr, truncated)
    }
}
