import Foundation
import ServiceManagement

struct LaunchAtLoginService: Sendable {
    func currentState() -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else { return .unsupported }
        switch SMAppService.mainApp.status {
        case .enabled: return LaunchAtLoginStateMapper.map(.enabled)
        case .notRegistered: return LaunchAtLoginStateMapper.map(.notRegistered)
        case .requiresApproval: return LaunchAtLoginStateMapper.map(.requiresApproval)
        case .notFound: return LaunchAtLoginStateMapper.map(.notFound)
        @unknown default: return LaunchAtLoginStateMapper.map(.unknown)
        }
    }

    func register() throws {
        guard #available(macOS 13.0, *) else { throw LaunchAtLoginError.unsupported }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard #available(macOS 13.0, *) else { throw LaunchAtLoginError.unsupported }
        try SMAppService.mainApp.unregister()
    }
}

enum SystemLaunchAtLoginStatus: Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unsupported
    case unknown
}

struct LaunchAtLoginStateMapper: Sendable {
    static func map(_ status: SystemLaunchAtLoginStatus) -> LaunchAtLoginState {
        switch status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .unsupported: .unsupported
        case .unknown: .error
        }
    }
}

enum LaunchAtLoginError: LocalizedError {
    case unsupported
    case unstableApplicationPath

    var errorDescription: String? {
        switch self {
        case .unsupported: "Launch at Login requires macOS 13 or later."
        case .unstableApplicationPath: "Install GitHub Ready in ~/Applications before enabling Launch at Login."
        }
    }
}
