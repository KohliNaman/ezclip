import Foundation
import Dispatch

final class LocalCaptureServer: @unchecked Sendable {
    static let shared = LocalCaptureServer()

    private let port: UInt16 = 19843
    private let lock = NSLock()
    private var listenSocket: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private let clientQueue = DispatchQueue(
        label: "com.ezclip.httpserver.clients",
        attributes: .concurrent
    )

    private(set) var pendingRequestId: UUID?
    private var pendingContext: [String: Any]?
    private var contextContinuation: CheckedContinuation<[String: Any]?, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        defer { lock.unlock() }

        guard listenSocket == -1 else {
            print("⚠️ LocalCaptureServer already running")
            return
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("❌ Failed to create socket")
            return
        }

        var opt: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &opt,
            socklen_t(MemoryLayout.size(ofValue: opt))
        )

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            print("❌ Failed to bind to port \(port): \(errno)")
            close(fd)
            return
        }

        guard listen(fd, 10) == 0 else {
            print("❌ Failed to listen on socket: \(errno)")
            close(fd)
            return
        }

        listenSocket = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: clientQueue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            self?.listenSocket = -1
        }
        source.resume()
        listenSource = source

        print("✅ LocalCaptureServer listening on port \(port)")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        let fd = listenSocket
        listenSocket = -1

        if fd != -1 {
            close(fd)
        }

        listenSource?.cancel()
        listenSource = nil

        if let continuation = contextContinuation {
            contextContinuation = nil
            continuation.resume(returning: nil)
        }

        pendingRequestId = nil
        pendingContext = nil
    }

    // MARK: - Pending state

    func setPending(requestId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        pendingRequestId = requestId
        pendingContext = nil

        // Cancel any existing waiter so the old capture doesn't leak
        if let continuation = contextContinuation {
            contextContinuation = nil
            continuation.resume(returning: nil)
        }
    }

    func clearPending() {
        lock.lock()
        defer { lock.unlock() }

        pendingRequestId = nil
        pendingContext = nil

        if let continuation = contextContinuation {
            contextContinuation = nil
            continuation.resume(returning: nil)
        }
    }

    // MARK: - Wait for extension context

    func waitForContext(timeout: TimeInterval = 5) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            lock.lock()

            // Context already arrived
            if let context = pendingContext {
                pendingContext = nil
                lock.unlock()
                continuation.resume(returning: context)
                return
            }

            // No pending request → nothing to wait for
            guard pendingRequestId != nil else {
                lock.unlock()
                continuation.resume(returning: nil)
                return
            }

            contextContinuation = continuation
            lock.unlock()

            // Timeout guard
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.lock.lock()
                if let cont = self?.contextContinuation {
                    self?.contextContinuation = nil
                    self?.lock.unlock()
                    cont.resume(returning: nil)
                } else {
                    self?.lock.unlock()
                }
            }
        }
    }

    // MARK: - Socket handling

    private func acceptConnection() {
        let fd = listenSocket
        guard fd != -1 else { return }

        var addr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(fd, sockaddrPtr, &len)
            }
        }

        guard clientFd >= 0 else { return }

        clientQueue.async { [weak self] in
            self?.handleClient(clientFd)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        let readHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = readHandle.readDataToEndOfFile()

        guard let request = String(data: data, encoding: .utf8) else { return }

        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let path = parts[1]

        // Parse body for POST requests
        var body: [String: Any]?
        if method == "POST" {
            if let emptyLineIndex = lines.firstIndex(of: "") {
                let bodyLines = lines.suffix(from: emptyLineIndex + 1)
                let bodyString = bodyLines.joined(separator: "\r\n")
                if let bodyData = bodyString.data(using: .utf8) {
                    body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                }
            }
        }

        let response: String
        if method == "GET" && path == "/status" {
            let pending: Bool
            lock.lock()
            pending = (pendingRequestId != nil)
            lock.unlock()
            response = httpResponse(status: 200, body: "{\"capturePending\": \(pending)}")
        } else if method == "POST" && path == "/context" {
            if let body = body {
                lock.lock()
                pendingContext = body
                if let continuation = contextContinuation {
                    contextContinuation = nil
                    lock.unlock()
                    continuation.resume(returning: body)
                } else {
                    lock.unlock()
                }
            }
            response = httpResponse(status: 200, body: "{\"ok\": true}")
        } else if method == "GET" && path == "/health" {
            response = httpResponse(status: 200, body: "{\"ok\": true}")
        } else {
            response = httpResponse(status: 404, body: "{\"error\": \"not found\"}")
        }

        if let responseData = response.data(using: .utf8) {
            let writeHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            writeHandle.write(responseData)
        }
    }

    // MARK: - Helpers

    private func httpResponse(status: Int, body: String) -> String {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        default:  statusText = "Internal Server Error"
        }
        return [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body
        ].joined(separator: "\r\n")
    }
}
