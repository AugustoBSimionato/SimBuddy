import Darwin
import Foundation

public struct AgentProcessResult: Codable, Sendable {
    public let exitCode: Int32
    public let output: String
    public let errorOutput: String
    public let truncated: Bool
    public let cancelled: Bool
    public var succeeded: Bool { exitCode == 0 && !cancelled }
    public init(exitCode: Int32, output: String = "", errorOutput: String = "", truncated: Bool = false, cancelled: Bool = false) {
        self.exitCode = exitCode; self.output = output; self.errorOutput = errorOutput
        self.truncated = truncated; self.cancelled = cancelled
    }
}

public protocol AgentProcessRunning: Sendable {
    func run(_ command: AgentCommand) async -> AgentProcessResult
    func cancel()
}

public final class ManagedProcess: AgentProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t?
    private var cancellationRequested = false
    private let outputLimit: Int

    public init(outputLimit: Int = 65_536) { self.outputLimit = outputLimit }

    public func cancel() {
        let pid = lock.withLock { cancellationRequested = true; return self.pid }
        if let pid { interrupt(pid) }
    }

    private func interrupt(_ pid: pid_t) {
        kill(-pid, SIGINT)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.withLock {
                if self.pid == pid { kill(-pid, SIGKILL) }
            }
        }
    }

    public func run(_ command: AgentCommand) async -> AgentProcessResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: self.runSynchronously(command))
                }
            }
        } onCancel: { self.cancel() }
    }

    private func runSynchronously(_ command: AgentCommand) -> AgentProcessResult {
        func failure(_ text: String) -> AgentProcessResult {
            AgentProcessResult(exitCode: -1, output: "", errorOutput: text, truncated: false,
                               cancelled: lock.withLock { cancellationRequested })
        }
        if lock.withLock({ cancellationRequested }) { return failure("Cancelled before execution.") }
        let output = Pipe(), error = Pipe(), input = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults); sigemptyset(&mask)
        for signal in [SIGINT, SIGTERM, SIGPIPE] { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, error.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        let argv = ([command.executable] + command.arguments).map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; environment.forEach { free($0) } }
        var child: pid_t = 0
        let code = argv.withUnsafeBufferPointer { args in
            environment.withUnsafeBufferPointer { env in
                posix_spawn(&child, command.executable, &actions, &attributes,
                            UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
            }
        }
        try? output.fileHandleForWriting.close()
        try? error.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        guard code == 0 else { return failure(String(cString: strerror(code))) }
        let shouldCancel = lock.withLock { pid = child; return cancellationRequested }
        if shouldCancel { interrupt(child) }
        let outputReader = BoundedReader(limit: outputLimit)
        let errorReader = BoundedReader(limit: outputLimit)
        let readers = DispatchGroup()
        for (handle, reader) in [(output.fileHandleForReading, outputReader), (error.fileHandleForReading, errorReader)] {
            readers.enter()
            DispatchQueue.global().async { reader.drain(handle); readers.leave() }
        }
        readers.enter()
        DispatchQueue.global().async {
            if let data = command.standardInput { try? input.fileHandleForWriting.write(contentsOf: data) }
            try? input.fileHandleForWriting.close()
            readers.leave()
        }
        var status: Int32 = 0
        while waitpid(child, &status, 0) < 0 && errno == EINTR {}
        // Reap descendants that keep inherited pipes open after their parent exits.
        kill(-child, SIGKILL)
        let cancelled = lock.withLock { pid = nil; return cancellationRequested }
        readers.wait()
        let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return AgentProcessResult(exitCode: exitCode, output: outputReader.string, errorOutput: errorReader.string,
                                  truncated: outputReader.truncated || errorReader.truncated, cancelled: cancelled)
    }
}

private final class BoundedReader: @unchecked Sendable {
    private let limit: Int
    private var data = Data()
    private(set) var truncated = false
    var string: String { String(decoding: data, as: UTF8.self) }
    init(limit: Int) { self.limit = limit }
    func drain(_ handle: FileHandle) {
        defer { try? handle.close() }
        while let chunk = try? handle.read(upToCount: 16_384), !chunk.isEmpty {
            let remaining = max(0, limit - data.count)
            data.append(chunk.prefix(remaining))
            if chunk.count > remaining { truncated = true }
        }
    }
}
