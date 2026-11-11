import Foundation

public struct CommandResult {
    public var data: Data
    public var error: String
    public var code: Int32
    public var output: String { String(decoding: data, as: UTF8.self) }
    public init(data: Data, error: String = "", code: Int32 = 0) { self.data = data; self.error = error; self.code = code }
}
public protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], cwd: String?, timeout: TimeInterval, token: CancellationToken?) throws -> CommandResult
}
private final class OutputBuffer: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
    var exceeded = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        let remaining = max(0, 8_000_000 - data.count)
        data.append(chunk.prefix(remaining)); if chunk.count > remaining { exceeded = true }
    }
}
public final class ProcessRunner: CommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], cwd: String? = nil, timeout: TimeInterval = 20, token: CancellationToken? = nil) throws -> CommandResult {
        if token?.isCancelled == true { throw ReclaimError.refused("Cancelled") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"; env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_OPTIONAL_LOCKS"] = "0"; env["LC_ALL"] = "C"
        // Never inherit a remote Docker endpoint into a local maintenance operation.
        env.removeValue(forKey: "DOCKER_HOST"); env.removeValue(forKey: "DOCKER_CONTEXT")
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe(); process.standardOutput = stdout; process.standardError = stderr
        let out = OutputBuffer(), err = OutputBuffer()
        let readers = DispatchGroup()
        try process.run()
        for (pipe, buffer) in [(stdout, out), (stderr, err)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                while true { let chunk = pipe.fileHandleForReading.availableData; if chunk.isEmpty { break }; buffer.append(chunk) }
                readers.leave()
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var interrupted = false
        while process.isRunning {
            if Date() > deadline || token?.isCancelled == true { interrupted = true; process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        if interrupted {
            let grace = Date().addingTimeInterval(1)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard readers.wait(timeout: .now() + 2) == .success else { throw ReclaimError.refused("Command output did not close; outcome must be reconciled.") }
        if interrupted { throw ReclaimError.refused("Command timed out or was cancelled; inspect state before retrying.") }
        guard !out.exceeded && !err.exceeded else { throw ReclaimError.refused("Command output exceeded the safety limit.") }
        return CommandResult(data: out.data, error: String(decoding: err.data, as: UTF8.self), code: process.terminationStatus)
    }
}
public enum ToolLocator {
    public static func find(_ name: String, overrides: [String: String] = [:]) -> String? {
        let candidates = overrides[name].map { [$0] } ?? ["/usr/bin/\(name)", "/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/Applications/Docker.app/Contents/Resources/bin/\(name)"]
        return candidates.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
    }
}
