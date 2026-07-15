import Foundation

struct SSHEffectiveConfigurationParser: Sendable {
    func parse(_ output: String) -> EffectiveSSHConfiguration? {
        var configuration = EffectiveSSHConfiguration(identityFiles: [])
        var sawValue = false

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            sawValue = true
            switch key {
            case "hostname": configuration.hostname = value
            case "port": configuration.port = Int(value)
            case "user": configuration.user = value
            case "identityfile": configuration.identityFiles.append(value)
            case "identitiesonly": configuration.identitiesOnly = parseBoolean(value)
            case "addkeystoagent": configuration.addKeysToAgent = parseBoolean(value)
            case "usekeychain": configuration.useKeychain = parseBoolean(value)
            default: break
            }
        }
        return sawValue ? configuration : nil
    }

    private func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "yes", "true", "on": true
        case "no", "false", "off": false
        default: nil
        }
    }
}
