import Foundation

struct StableInstallationPolicy: Sendable {
    func classify(bundleURL: URL, homeDirectory: URL) -> ApplicationLocationState {
        let path = bundleURL.standardizedFileURL.path
        let stablePath = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("GitHub Ready.app", isDirectory: true)
            .standardizedFileURL.path

        if path == stablePath { return .stable }

        let components = bundleURL.standardizedFileURL.pathComponents.map { $0.lowercased() }
        if components.contains("dist") { return .developmentDist }
        if components.contains(".build") { return .developmentBuild }
        return .unexpected
    }
}
