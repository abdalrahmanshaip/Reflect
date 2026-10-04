import Foundation

struct AnalysisAgentDiscovery {
    private let runner: AnalysisDiscoveryProcessRunning
    private let locator: ExecutableLocating

    init(
        runner: AnalysisDiscoveryProcessRunning = DefaultAnalysisProcessRunner(),
        locator: ExecutableLocating = DefaultExecutableLocator()
    ) {
        self.runner = runner
        self.locator = locator
    }

    /// Agent discovery is asynchronous and cooperative: as a nonisolated async
    /// function it never runs on the caller's actor, cancellation between
    /// agents stops the remaining checks, and a canceled discovery returns a
    /// partial result that the caller must discard.
    func discover() async -> [AnalysisAgentStatus] {
        var statuses: [AnalysisAgentStatus] = []
        for kind in AnalysisAgentKind.supported {
            if Task.isCancelled { break }
            guard let executableURL = locator.executableURL(for: kind.executableName) else {
                statuses.append(AnalysisAgentStatus(kind: kind, executableURL: nil, availability: .notInstalled))
                continue
            }

            let invocation = AnalysisProcessInvocation(
                executableURL: executableURL,
                arguments: kind.authenticationArguments,
                input: Data(),
                workingDirectory: FileManager.default.temporaryDirectory,
                environment: AnalysisProcessEnvironment.sanitized(),
                timeout: 8,
                outputLimit: 8_192
            )

            do {
                let result = try await runner.run(invocation)
                statuses.append(AnalysisAgentStatus(
                    kind: kind,
                    executableURL: executableURL,
                    availability: Self.classify(result: result)
                ))
            } catch is CancellationError {
                break
            } catch {
                // Timeout, launch failure, and abnormal exits stay honest:
                // the agent is not reported ready or absent, only unknown.
                statuses.append(AnalysisAgentStatus(kind: kind, executableURL: executableURL, availability: .unknown))
            }
        }
        return statuses
    }

    private static func classify(result: AnalysisProcessResult) -> AnalysisAgentAvailability {
        if let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
           let loggedIn = object["loggedIn"] as? Bool {
            return loggedIn ? .ready : .notAuthenticated
        }

        let output = String(decoding: result.stdout + result.stderr, as: UTF8.self).lowercased()

        let notAuthenticatedMarkers = [
            "not logged",
            "not authenticated",
            "no authentication",
            "authentication required",
            "login required",
            "unauthorized"
        ]
        if notAuthenticatedMarkers.contains(where: output.contains) {
            return .notAuthenticated
        }

        let authenticatedMarkers = [
            "logged in",
            "authenticated",
            "authentication:",
            "auth method",
            "api key"
        ]
        if result.terminationStatus == 0,
           authenticatedMarkers.contains(where: output.contains) {
            return .ready
        }
        return .unknown
    }
}
