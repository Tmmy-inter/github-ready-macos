import Foundation

struct SensitiveValueRedactor: Sendable {
    private struct Rule: Sendable {
        let expression: NSRegularExpression
        let replacement: String
    }

    private let rules: [Rule]

    init() {
        rules = [
            Self.rule(#"(?i)\b(?:gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,})\b"#),
            Self.rule(#"(?i)\b(?:oauth|access)[_-]?token\s*[:=]\s*[^\s,;]+"#, replacement: "token=[REDACTED]"),
            Self.rule(#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, replacement: "Bearer [REDACTED]"),
            Self.rule(#"(?im)^\s*Authorization\s*:\s*.*$"#, replacement: "Authorization: [REDACTED]"),
            Self.rule(#"(?im)^\s*(?:Cookie|Set-Cookie)\s*:\s*.*$"#, replacement: "Cookie: [REDACTED]"),
            Self.rule(#"(?i)\b(password|passwd|passphrase|secret|client_secret)\s*[:=]\s*[^\s,;]+"#, replacement: "$1=[REDACTED]"),
            Self.rule(#"(?i)\bSHA256:[A-Za-z0-9+/=]{12,}"#, replacement: "SHA256:[REDACTED]"),
            Self.rule(#"(?i)(https?://)[^/@\s:]+:[^/@\s]+@"#, replacement: "$1[REDACTED]@"),
            Self.rule(#"(?is)-----BEGIN [^-]*(?:PRIVATE KEY|CREDENTIAL)[^-]*-----.*?-----END [^-]*(?:PRIVATE KEY|CREDENTIAL)[^-]*-----"#, replacement: "[REDACTED_PRIVATE_BLOCK]"),
            Self.rule(#"(?i)\b[A-Za-z0-9+/=_-]{64,}\b"#, replacement: "[REDACTED_LONG_SECRET]")
        ]
    }

    func redact(_ text: String) -> String {
        rules.reduce(text) { partial, rule in
            let range = NSRange(partial.startIndex..<partial.endIndex, in: partial)
            return rule.expression.stringByReplacingMatches(
                in: partial,
                range: range,
                withTemplate: rule.replacement
            )
        }
    }

    func sanitizeArguments(_ arguments: [String]) -> [String] {
        var sanitized: [String] = []
        var redactNext = false

        for argument in arguments {
            if redactNext {
                sanitized.append("[REDACTED]")
                redactNext = false
                continue
            }

            let lowercased = argument.lowercased()
            if ["--token", "--password", "--passphrase", "--client-secret"].contains(lowercased) {
                sanitized.append(argument)
                redactNext = true
            } else {
                sanitized.append(redact(argument))
            }
        }

        return sanitized
    }

    private static func rule(_ pattern: String, replacement: String = "[REDACTED]") -> Rule {
        let expression = try! NSRegularExpression(pattern: pattern)
        return Rule(expression: expression, replacement: replacement)
    }
}
