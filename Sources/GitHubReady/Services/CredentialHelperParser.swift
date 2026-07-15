import Foundation

struct CredentialHelperParser: Sendable {
    func classify(
        entries: [CredentialHelperEntry],
        resolvedGHPath: String
    ) -> CredentialHelperState {
        let relevantEntries = entries.filter { entry in
            let key = entry.key.lowercased()
            return key == "credential.helper" ||
                key == "credential.https://github.com.helper" ||
                key == "credential.https://gist.github.com.helper"
        }

        let githubScoped = relevantEntries.filter {
            $0.key.lowercased().contains("github.com") || $0.key.lowercased().contains("gist.github.com")
        }
        let generic = relevantEntries.filter { $0.key.lowercased() == "credential.helper" }
        let candidates = githubScoped.isEmpty ? generic : githubScoped

        let nonEmpty = candidates
            .map { normalize($0.value) }
            .filter { !$0.isEmpty }

        let parsedHelpers = nonEmpty.compactMap(parseGHHelper)
        if parsedHelpers.contains(resolvedGHPath) {
            return .valid(helperPath: resolvedGHPath)
        }
        if let configuredPath = parsedHelpers.first, configuredPath != resolvedGHPath {
            return .malformed("GitHub CLI helper points to a different executable.")
        }
        if !nonEmpty.isEmpty {
            let onlySystemKeychain = nonEmpty.allSatisfy { normalize($0).lowercased() == "osxkeychain" }
            if onlySystemKeychain { return .systemKeychainOnly }
            return .malformed("GitHub credential helper value is not supported.")
        }

        let hasSystemKeychain = generic.contains {
            $0.scope == .system && normalize($0.value).lowercased() == "osxkeychain"
        }
        return hasSystemKeychain ? .systemKeychainOnly : .missing
    }

    func entries(scope: CredentialHelperEntry.Scope, key: String, output: String) -> [CredentialHelperEntry] {
        guard !output.isEmpty else { return [] }
        var lines = output.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        return lines.map { CredentialHelperEntry(scope: scope, key: key, value: $0) }
    }

    private func normalize(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count >= 2,
           (result.hasPrefix("\"") && result.hasSuffix("\"") || result.hasPrefix("'") && result.hasSuffix("'")) {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func parseGHHelper(_ rawValue: String) -> String? {
        let value = normalize(rawValue)
        let pattern = #"^!\s*(?:\"([^\"]+)\"|'([^']+)'|([^\s]+))\s+auth\s+git-credential\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..<value.endIndex, in: value)
              ) else { return nil }

        for index in 1...3 {
            let range = match.range(at: index)
            if range.location != NSNotFound, let swiftRange = Range(range, in: value) {
                let path = String(value[swiftRange])
                return path.hasPrefix("/") ? URL(fileURLWithPath: path).standardizedFileURL.path : nil
            }
        }
        return nil
    }
}
