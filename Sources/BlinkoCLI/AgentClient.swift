import BlinkoKit
import Foundation

/// Minimal blocking Unix-socket client. Every failure is silent for hooks: if Blinko isn't
/// running, Claude Code just carries on (and shows its own permission prompt).
struct SocketClient {
    let fd: Int32
    private var buffer = Data()

    init?(path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 2, tv_usec: 0) // a stuck Blinko must never stall the agent
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard ok == 0 else { close(fd); return nil }
        self.fd = fd
    }

    func send(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    /// Next line, or nil on EOF / timeout.
    mutating func readLine(timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return Data(line)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let r = poll(&pfd, 1, Int32(min(remaining, 60) * 1000))
            if r < 0, errno == EINTR { continue }
            guard r > 0 else { if r == 0 { continue } else { return nil } }
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > AgentProtocol.maxLineBytes { return nil }
        }
    }

    func shutdown() { close(fd) }
}

/// Claude Code hook: stdin JSON → one protocol line. For PermissionRequest, waits for the
/// island's decision and prints it; anything else (no Blinko, timeout, "ask") prints nothing,
/// so Claude Code falls back to its normal prompt. Always exits 0.
func runHook() -> Int32 {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
          let message = ClaudeHooks.message(fromHookInput: object),
          var client = SocketClient(path: AgentProtocol.socketPath)
    else { return 0 }
    defer { client.shutdown() }
    guard client.send(message.line()) else { return 0 }
    guard message.type == AgentMessage.Kind.permissionRequest, let id = message.id else { return 0 }

    let deadline = Date().addingTimeInterval(AgentProtocol.maxApprovalWait)
    while deadline.timeIntervalSinceNow > 0 {
        guard let line = client.readLine(timeout: deadline.timeIntervalSinceNow) else { return 0 }
        guard let reply = AgentMessage.decode(line),
              reply.type == AgentMessage.Kind.permissionResponse, reply.id == id else { continue }
        if let out = ClaudeHooks.hookOutput(for: reply) {
            FileHandle.standardOutput.write(out)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        return 0
    }
    return 0
}

/// Generic agent integration: forwards protocol lines from stdin and prints every reply.
/// After stdin closes, waits up to `BLINKO_WAIT` seconds (default 0; set it when sending a
/// permission request) for replies.
func runSend() -> Int32 {
    guard var client = SocketClient(path: AgentProtocol.socketPath) else {
        FileHandle.standardError.write(Data("blinko: Blinko isn't running or the Agent Hub is off\n".utf8))
        return 1
    }
    defer { client.shutdown() }
    let input = FileHandle.standardInput.readDataToEndOfFile()
    for line in input.split(separator: 0x0A) where !line.isEmpty {
        guard AgentMessage.decode(Data(line)) != nil else {
            FileHandle.standardError.write(Data("blinko: skipping a line that isn't a protocol message\n".utf8))
            continue
        }
        guard client.send(Data(line) + Data([0x0A])) else { return 1 }
    }
    let wait = Double(ProcessInfo.processInfo.environment["BLINKO_WAIT"] ?? "") ?? 0
    let deadline = Date().addingTimeInterval(wait)
    while deadline.timeIntervalSinceNow > 0, let line = client.readLine(timeout: deadline.timeIntervalSinceNow) {
        FileHandle.standardOutput.write(line + Data([0x0A]))
    }
    return 0
}
