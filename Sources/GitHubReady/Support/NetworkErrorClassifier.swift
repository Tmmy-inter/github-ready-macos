import Foundation

struct NetworkErrorClassifier: Sendable {
    func classify(_ text: String, timedOut: Bool = false) -> NetworkFailure? {
        if timedOut { return .timeout }

        let value = text.lowercased()
        if containsAny(value, ["could not resolve host", "could not resolve hostname", "no such host", "dial tcp: lookup", "name or service not known", "temporary failure in name resolution", "dns"]) {
            return .dns
        }
        if containsAny(value, ["certificate verify failed", "tls handshake", "ssl_connect", "x509", "secure connection failed"]) {
            return .tls
        }
        if containsAny(value, ["timed out", "timeout", "deadline exceeded"]) {
            return .timeout
        }
        if containsAny(value, ["proxyconnect", "proxy error", "proxy connection failed", "network is unreachable", "no route to host", "connection reset", "connection refused", "connection closed", "vpn"]) {
            return .proxyOrVPN
        }
        if containsAny(value, ["rate limit", "http 429", "status 429"]) {
            return .rateLimited
        }
        if containsAny(value, ["http 403", "status 403", "resource not accessible", "permission denied"]) {
            return .permissionDenied
        }
        if containsAny(value, ["http 500", "http 502", "http 503", "http 504", "github is currently unavailable", "service unavailable"]) {
            return .githubUnavailable
        }
        return nil
    }

    func explicitlyRejectsAuthentication(_ text: String) -> Bool {
        let value = text.lowercased()
        return containsAny(value, [
            "bad credentials",
            "authentication token is invalid",
            "token is invalid",
            "token has expired",
            "expired token",
            "token was revoked",
            "http 401",
            "status 401"
        ])
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }
}
