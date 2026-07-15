import Foundation

struct SSHConnectionParser: Sendable {
    private let networkClassifier = NetworkErrorClassifier()

    func parse(
        exitStatus: Int32,
        output: String,
        timedOut: Bool,
        expectedAccount: String?
    ) -> SSHAuthenticationState {
        if timedOut { return .networkUnavailable(.timeout) }
        if let account = successAccount(in: output), exitStatus == 0 || exitStatus == 1 {
            if let expectedAccount, account.caseInsensitiveCompare(expectedAccount) != .orderedSame {
                return .rejected
            }
            return .verified(account: account)
        }

        let value = output.lowercased()
        if value.contains("host key verification failed") || value.contains("no host key is known") {
            return .hostVerificationProblem
        }
        if value.contains("permission denied (publickey)") ||
            value.contains("no supported authentication methods available") {
            return .rejected
        }
        if value.contains("passphrase") || value.contains("read_passphrase") ||
            value.contains("agent refused operation") || value.contains("can't open /dev/tty") {
            return .interactionRequired
        }
        if let failure = networkClassifier.classify(output) {
            return .networkUnavailable(failure)
        }
        return .failed
    }

    private func successAccount(in output: String) -> String? {
        let pattern = #"(?im)Hi\s+([^!\r\n]+)!\s+You've successfully authenticated, but GitHub does not provide shell access\."#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..<output.endIndex, in: output)
              ),
              let accountRange = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[accountRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
