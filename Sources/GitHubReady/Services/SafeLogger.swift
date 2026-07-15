import Foundation

actor SafeLogger {
    static let shared = SafeLogger()

    private let fileManager: FileManager
    private let redactor: SensitiveValueRedactor
    private let maximumBytes: Int

    init(
        fileManager: FileManager = .default,
        redactor: SensitiveValueRedactor = SensitiveValueRedactor(),
        maximumBytes: Int = 512 * 1_024
    ) {
        self.fileManager = fileManager
        self.redactor = redactor
        self.maximumBytes = maximumBytes
    }

    var logDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GitHubReady", isDirectory: true)
    }

    var logFileURL: URL {
        logDirectoryURL.appendingPathComponent("GitHubReady.log")
    }

    func logEvent(
        name: String,
        exitStatus: Int32? = nil,
        duration: TimeInterval? = nil,
        timedOut: Bool = false,
        classification: CommandErrorClassification = .none,
        summary: String
    ) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        var fields = [
            "timestamp=\(ISO8601DateFormatter().string(from: Date()))",
            "version=\(version)",
            "event=\(name)",
            "timeout=\(timedOut)",
            "classification=\(classification.rawValue)"
        ]
        if let exitStatus { fields.append("exit=\(exitStatus)") }
        if let duration { fields.append(String(format: "duration=%.3f", duration)) }
        fields.append("summary=\(summary)")
        append(redactor.redact(fields.joined(separator: " ")) + "\n")
    }

    func readRecent(maximumBytes: Int = 64 * 1_024) -> String {
        guard let data = try? Data(contentsOf: logFileURL) else { return "No local logs yet." }
        return redactor.redact(String(decoding: data.suffix(maximumBytes), as: UTF8.self))
    }

    private func append(_ text: String) {
        do {
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            try rotateIfNeeded(incomingBytes: text.utf8.count)
            let data = Data(text.utf8)
            if !fileManager.fileExists(atPath: logFileURL.path) {
                try data.write(to: logFileURL, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            }
        } catch {
            // Logging must never block health checks or expose fallback output.
        }
    }

    private func rotateIfNeeded(incomingBytes: Int) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize + incomingBytes > maximumBytes else { return }

        let rotatedURL = logDirectoryURL.appendingPathComponent("GitHubReady.log.1")
        if fileManager.fileExists(atPath: rotatedURL.path) {
            try fileManager.removeItem(at: rotatedURL)
        }
        if fileManager.fileExists(atPath: logFileURL.path) {
            try fileManager.moveItem(at: logFileURL, to: rotatedURL)
        }
    }
}
