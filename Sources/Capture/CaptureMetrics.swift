import OSLog

enum CaptureMetrics {
    static let logger = Logger(subsystem: "com.namaankohli.ezclip", category: "Capture")
    static let signposter = OSSignposter(logger: logger)
}
