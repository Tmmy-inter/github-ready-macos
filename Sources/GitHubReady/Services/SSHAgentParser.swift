import Foundation

struct SSHAgentParser: Sendable {
    func parse(exitStatus: Int32, output: String) -> SSHAgentState {
        let value = output.lowercased()
        if exitStatus == 0, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .identityLoaded
        }
        if value.contains("the agent has no identities") || value.contains("no identities") {
            return .noIdentities
        }
        if value.contains("could not open a connection to your authentication agent") ||
            value.contains("error connecting to agent") {
            return .unavailable
        }
        return .failed
    }
}
