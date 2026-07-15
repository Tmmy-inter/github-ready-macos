import Darwin
import Foundation

struct SelfTestCase: Sendable {
    let name: String
    let body: @Sendable () async throws -> Void
}

struct SelfTestFailure: Error, CustomStringConvertible, Sendable {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SelfTestFailure(description: message) }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw SelfTestFailure(description: "\(message); expected=\(expected) actual=\(actual)")
    }
}

@_cdecl("github_ready_run_self_tests")
func githubReadyRunSelfTests() {
    let completion = DispatchSemaphore(value: 0)

    Task.detached {
        var failures: [(String, String)] = []
        for test in GitHubReadySelfTests.all {
            do {
                try await test.body()
            } catch {
                failures.append((test.name, String(describing: error)))
            }
        }

        if failures.isEmpty {
            writeTestOutput("GitHubReadyTests: executed \(GitHubReadySelfTests.all.count) tests, 0 failures\n")
            completion.signal()
        } else {
            writeTestOutput("GitHubReadyTests: executed \(GitHubReadySelfTests.all.count) tests, \(failures.count) failures\n")
            for (name, message) in failures {
                writeTestOutput("FAIL \(name): \(message)\n")
            }
            Darwin.exit(EXIT_FAILURE)
        }
    }

    completion.wait()
}

@used @section("__DATA,__mod_init_func")
let githubReadySelfTestInitializer: @convention(c) () -> Void = githubReadyRunSelfTests

private func writeTestOutput(_ value: String) {
    FileHandle.standardError.write(Data(value.utf8))
}
