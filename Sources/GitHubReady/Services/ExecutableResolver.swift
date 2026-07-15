import Foundation

struct ResolvedExecutables: Sendable, Equatable {
    let git: URL?
    let gh: URL?
    let ssh: URL?
    let sshAdd: URL?
}

struct ExecutableResolver: Sendable {
    static let gitCandidates = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git"
    ]

    static let ghCandidates = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh"
    ]

    static let trustedSystemPaths: Set<String> = [
        "/usr/bin/open",
        "/usr/bin/sw_vers",
        "/usr/bin/uname"
    ]

    func resolve() -> ResolvedExecutables {
        ResolvedExecutables(
            git: firstExecutable(in: Self.gitCandidates),
            gh: firstExecutable(in: Self.ghCandidates),
            ssh: firstExecutable(in: ["/usr/bin/ssh"]),
            sshAdd: firstExecutable(in: ["/usr/bin/ssh-add"])
        )
    }

    var allowedPaths: Set<String> {
        Set(Self.gitCandidates + Self.ghCandidates + ["/usr/bin/ssh", "/usr/bin/ssh-add"])
            .union(Self.trustedSystemPaths)
    }

    private func firstExecutable(in candidates: [String]) -> URL? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
