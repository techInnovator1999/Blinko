import BlinkoKit
import Foundation
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "agents")

/// Unix domain socket listener for the Agent Hub (newline-delimited JSON, see
/// docs/AGENT_PROTOCOL.md). Fully event-driven: one `DispatchSource` for accept and one per
/// connection, on a private serial queue; nothing runs between messages. The socket is
/// 0600 and peers with another uid are rejected. Messages are only ever parsed into
/// `AgentMessage` values — nothing received is executed.
final class AgentHubServer: @unchecked Sendable {
    typealias ConnectionID = Int

    /// Called on the main actor for every decoded message.
    var onMessage: (@MainActor (ConnectionID, AgentMessage) -> Void)?
    /// Called on the main actor when a client disconnects.
    var onDisconnect: (@MainActor (ConnectionID) -> Void)?

    private let queue = DispatchQueue(label: "app.blinko.agents", qos: .userInitiated)
    private let path: String
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [ConnectionID: Connection] = [:]
    private var nextID = 1
    private static let maxConnections = 64

    private final class Connection {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        init(fd: Int32, source: DispatchSourceRead) { self.fd = fd; self.source = source }
    }

    init(path: String) { self.path = path }

    // MARK: Lifecycle

    func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        unlink(path) // stale socket from a previous run
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            unlink(path)
            throw POSIXError(.init(rawValue: err) ?? .EIO)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        acceptSource = source
        source.resume()
        log.info("agent hub listening")
    }

    func stop() {
        queue.sync {
            for id in Array(connections.keys) { closeConnection(id, notify: false) }
            acceptSource?.cancel()
            acceptSource = nil
            listenFD = -1
            unlink(path)
        }
    }

    // MARK: Sending

    func send(_ message: AgentMessage, to id: ConnectionID) {
        let data = message.line()
        queue.async { [weak self] in
            guard let self, let conn = self.connections[id] else { return }
            let ok = data.withUnsafeBytes { raw -> Bool in
                var offset = 0
                while offset < raw.count {
                    let n = write(conn.fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 { offset += n; continue }
                    if n < 0, errno == EINTR { continue }
                    return false
                }
                return true
            }
            if !ok { self.closeConnection(id, notify: true) }
        }
    }

    // MARK: Queue-confined

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return } // EAGAIN: drained
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid(), connections.count < Self.maxConnections else {
                close(fd)
                continue
            }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var tv = timeval(tv_sec: 2, tv_usec: 0) // a client that stops reading can't block the queue for long
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

            let id = nextID
            nextID += 1
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(id) }
            source.setCancelHandler { close(fd) }
            connections[id] = Connection(fd: fd, source: source)
            source.resume()
        }
    }

    private func readAvailable(_ id: ConnectionID) {
        guard let conn = connections[id] else { return }
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        let n = read(conn.fd, &chunk, chunk.count)
        if n <= 0 {
            if n < 0, errno == EAGAIN || errno == EINTR { return }
            closeConnection(id, notify: true)
            return
        }
        conn.buffer.append(contentsOf: chunk[0..<n])
        var messages: [AgentMessage] = []
        while let nl = conn.buffer.firstIndex(of: 0x0A) {
            let line = conn.buffer[conn.buffer.startIndex..<nl]
            conn.buffer.removeSubrange(conn.buffer.startIndex...nl)
            if let message = AgentMessage.decode(Data(line)) { messages.append(message) }
        }
        if conn.buffer.count > AgentProtocol.maxLineBytes {
            closeConnection(id, notify: true)
            return
        }
        guard !messages.isEmpty, let handler = onMessage else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { for m in messages { handler(id, m) } }
        }
    }

    private func closeConnection(_ id: ConnectionID, notify: Bool) {
        guard let conn = connections.removeValue(forKey: id) else { return }
        conn.source.cancel()
        guard notify, let handler = onDisconnect else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(id) } }
    }
}
