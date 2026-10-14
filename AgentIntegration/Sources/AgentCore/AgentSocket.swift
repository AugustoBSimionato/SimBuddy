import Darwin
import Foundation

public enum AgentSocket {
    public static var directory: String { "/private/tmp/simbuddy-agents-\(getuid())" }
    public static var path: String { directory + "/bridge.sock" }
    static let maximumFrame = 2_097_152

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw AgentFailure("Socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func configure(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw AgentFailure("Socket peer is not the current user.") }
    }

    static func readFrame(_ fd: Int32) throws -> Data {
        let header = try readExactly(fd, count: 4)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size > 0, size <= maximumFrame else { throw AgentFailure("Invalid bridge frame size.") }
        return try readExactly(fd, count: Int(size))
    }

    static func readExactly(_ fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let result = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw AgentFailure("Bridge disconnected or timed out.") }
                offset += result
            }
        }
        return data
    }

    static func writeFrame(_ data: Data, to fd: Int32) throws {
        guard data.count <= maximumFrame else { throw AgentFailure("Bridge response exceeds size limit.") }
        var size = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &size) { Data($0) }
        frame.append(data)
        try frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < frame.count {
                let result = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), frame.count - offset)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw AgentFailure("Could not write bridge frame.") }
                offset += result
            }
        }
    }

    public static func request(_ request: AgentBridgeRequest, path: String = AgentSocket.path) async throws -> AgentBridgeResponse {
        try await Task.detached {
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw AgentFailure("Could not create bridge socket.") }
            defer { Darwin.close(fd) }
            configure(fd)
            var address = try address(path)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { throw AgentFailure("SimBuddy is not running. Open the app and enable agent monitoring.") }
            try verifyPeer(fd)
            try writeFrame(JSONEncoder().encode(request), to: fd)
            return try JSONDecoder().decode(AgentBridgeResponse.self, from: readFrame(fd))
        }.value
    }
}

public final class AgentSocketServer: @unchecked Sendable {
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var lockFile: Int32 = -1
    private var clients: Set<Int32> = []
    private let path: String

    public init(path: String = AgentSocket.path) { self.path = path }

    public func start(handler: @escaping @Sendable (AgentBridgeRequest) async -> AgentBridgeResponse) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw AgentFailure("Could not create bridge directory.") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_mode & 0o077) == 0 else { throw AgentFailure("Bridge directory must be owned by this user with mode 0700.") }
        let lockFD = Darwin.open(directory + "/server.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lockFD >= 0 else { throw AgentFailure("Could not lock bridge.") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lockFD)
            throw AgentFailure("Another SimBuddy instance owns the bridge.")
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Darwin.close(lockFD); throw AgentFailure("Could not create bridge listener.") }
        do {
            AgentSocket.configure(fd)
            unlink(path)
            var address = try AgentSocket.address(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else { throw AgentFailure("Could not bind bridge socket.") }
            lock.withLock { listener = fd; lockFile = lockFD }
            DispatchQueue.global(qos: .utility).async { [self] in
                while lock.withLock({ listener == fd }) {
                    let client = accept(fd, nil, nil)
                    if client < 0 {
                        if errno == EINTR || errno == EAGAIN { continue }
                        break
                    }
                    let accepted = lock.withLock {
                        guard listener == fd, clients.count < 32 else { return false }
                        clients.insert(client); return true
                    }
                    guard accepted else { Darwin.close(client); continue }
                    DispatchQueue.global().async { [self] in
                        defer { _ = lock.withLock { clients.remove(client) }; Darwin.close(client) }
                        do {
                            AgentSocket.configure(client)
                            try AgentSocket.verifyPeer(client)
                            let request = try JSONDecoder().decode(AgentBridgeRequest.self, from: AgentSocket.readFrame(client))
                            let completion = DispatchSemaphore(value: 0)
                            Task {
                                let response = await handler(request)
                                if let data = try? JSONEncoder().encode(response) { try? AgentSocket.writeFrame(data, to: client) }
                                completion.signal()
                            }
                            completion.wait()
                        } catch {
                            let response = AgentBridgeResponse("Invalid bridge request.", isError: true)
                            if let data = try? JSONEncoder().encode(response) { try? AgentSocket.writeFrame(data, to: client) }
                        }
                    }
                }
            }
        } catch {
            Darwin.close(fd); Darwin.close(lockFD); throw error
        }
    }

    public func stop() {
        lock.withLock {
            guard listener >= 0 else { return }
            Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
            listener = -1
            for client in clients { Darwin.shutdown(client, SHUT_RDWR) }
            unlink(path)
            Darwin.close(lockFile)
            lockFile = -1
        }
    }
    deinit { stop() }
}
