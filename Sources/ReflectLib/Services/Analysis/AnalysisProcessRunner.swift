import Foundation

struct AnalysisProcessInvocation {
    let executableURL: URL
    let arguments: [String]
    let input: Data
    let workingDirectory: URL
    let environment: [String: String]
    let timeout: TimeInterval
    let outputLimit: Int
}

struct AnalysisProcessResult {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
}

protocol AnalysisProcessRunning {
    func run(_ invocation: AnalysisProcessInvocation) throws -> AnalysisProcessResult
}

enum AnalysisProcessError: LocalizedError {
    case timedOut
    case launchFailed
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case .timedOut: return "The selected analysis agent timed out."
        case .launchFailed: return "The selected analysis agent could not be started."
        case .nonZeroExit: return "The selected analysis agent did not complete successfully."
        }
    }
}

/// Cancellable, asynchronous process execution for agent discovery. Discovery
/// must be able to stop waiting for a slow CLI; ordinary analysis runs keep
/// the synchronous `AnalysisProcessRunning` contract unchanged.
protocol AnalysisDiscoveryProcessRunning {
    func run(_ invocation: AnalysisProcessInvocation) async throws -> AnalysisProcessResult
}

final class DefaultAnalysisProcessRunner: AnalysisProcessRunning, AnalysisDiscoveryProcessRunning {
    func run(_ invocation: AnalysisProcessInvocation) throws -> AnalysisProcessResult {
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = invocation.environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let stdoutReader = CappedPipeReader(pipe: outputPipe, limit: invocation.outputLimit)
        let stderrReader = CappedPipeReader(pipe: errorPipe, limit: invocation.outputLimit)

        do {
            try process.run()
        } catch {
            throw AnalysisProcessError.launchFailed
        }

        inputPipe.fileHandleForWriting.write(invocation.input)
        inputPipe.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(invocation.timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                // Do not leave an unbounded child behind if it ignores SIGTERM.
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    while process.isRunning {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                    }
                }
                _ = stdoutReader.finish()
                _ = stderrReader.finish()
                throw AnalysisProcessError.timedOut
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        let stdout = stdoutReader.finish()
        let stderr = stderrReader.finish()
        guard process.terminationStatus == 0 else {
            throw AnalysisProcessError.nonZeroExit(process.terminationStatus)
        }
        return AnalysisProcessResult(stdout: stdout, stderr: stderr, terminationStatus: process.terminationStatus)
    }

    /// Discovery path. Waits on a background thread, checks for cancellation
    /// between polls, and terminates (then force-kills) the child when the
    /// surrounding task is canceled or the invocation timeout elapses. The
    /// timeout stays bounded exactly as in the synchronous path.
    func run(_ invocation: AnalysisProcessInvocation) async throws -> AnalysisProcessResult {
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.workingDirectory
        process.environment = invocation.environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let stdoutReader = CappedPipeReader(pipe: outputPipe, limit: invocation.outputLimit)
        let stderrReader = CappedPipeReader(pipe: errorPipe, limit: invocation.outputLimit)

        do {
            try process.run()
        } catch {
            throw AnalysisProcessError.launchFailed
        }

        inputPipe.fileHandleForWriting.write(invocation.input)
        inputPipe.fileHandleForWriting.closeFile()

        return try await withTaskCancellationHandler(operation: {
            let deadline = Date().addingTimeInterval(invocation.timeout)
            while process.isRunning {
                if Task.isCancelled {
                    // Cancellation wakes this poll immediately (Task.sleep
                    // returns at once), so the bounded terminate/wait/kill
                    // escalation runs here on the worker thread — never on
                    // the canceling (main actor) thread.
                    Self.stopWaitingForChild(process)
                    _ = stdoutReader.finish()
                    _ = stderrReader.finish()
                    throw CancellationError()
                }
                if Date() >= deadline {
                    Self.stopWaitingForChild(process)
                    _ = stdoutReader.finish()
                    _ = stderrReader.finish()
                    throw AnalysisProcessError.timedOut
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }

            let stdout = stdoutReader.finish()
            let stderr = stderrReader.finish()
            guard process.terminationStatus == 0 else {
                throw AnalysisProcessError.nonZeroExit(process.terminationStatus)
            }
            return AnalysisProcessResult(stdout: stdout, stderr: stderr, terminationStatus: process.terminationStatus)
        }, onCancel: {
            // Runs synchronously on the canceling thread (possibly the main
            // actor), so it must never block: send SIGTERM only. The bounded
            // wait and SIGKILL escalation happen on the worker side once
            // cancellation wakes the poll above.
            if process.isRunning {
                process.terminate()
            }
        })
    }

    /// Terminates the child and escalates to SIGKILL if it ignores SIGTERM.
    /// Idempotent, with bounded waits so cancellation itself never hangs.
    private static func stopWaitingForChild(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let terminationDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < terminationDeadline {
            usleep(10_000)
        }
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
        let killDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < killDeadline {
            usleep(10_000)
        }
    }

    /// Drain both pipes while the child is running so a noisy CLI cannot block
    /// on a full pipe. The retained data is capped before it reaches Reflect.
    private final class CappedPipeReader {
        private let handle: FileHandle
        private let limit: Int
        private let lock = NSLock()
        private var data = Data()

        init(pipe: Pipe, limit: Int) {
            self.handle = pipe.fileHandleForReading
            self.limit = max(0, limit)
            handle.readabilityHandler = { [weak self] handle in
                self?.consume(handle.availableData)
            }
        }

        func finish() -> Data {
            handle.readabilityHandler = nil
            consume(handle.readDataToEndOfFile())
            lock.lock()
            defer { lock.unlock() }
            return data
        }

        private func consume(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            guard data.count < limit else { return }
            data.append(chunk.prefix(limit - data.count))
        }
    }
}

protocol ExecutableLocating {
    func executableURL(for command: String) -> URL?
}

struct DefaultExecutableLocator: ExecutableLocating {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func executableURL(for command: String) -> URL? {
        if command.contains("/") {
            let url = URL(fileURLWithPath: command)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }

        let path = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for directory in path.split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

enum AnalysisProcessEnvironment {
    /// Agent CLIs need location and locale context, but Reflect must not pass
    /// arbitrary environment variables that may contain raw credentials.
    static func sanitized() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let allowed = ["PATH", "HOME", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "COPILOT_HOME", "LANG", "LC_ALL"]
        return source.reduce(into: [:]) { result, entry in
            if allowed.contains(entry.key) {
                result[entry.key] = entry.value
            }
        }
    }
}
