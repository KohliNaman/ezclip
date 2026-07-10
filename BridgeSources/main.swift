import Foundation

struct BrowserDesignContext: Codable {
    var schemaVersion: Int?
    var sourceBrowser: String?
    var sourceExtensionId: String?
    var extractedAt: Date?
    var transportStatus: String?
    var transportError: String?
    var url: String?
    var title: String?
    var capturedAt: Date?
    var scroll: ScrollInfo?
    var fonts: [FontInfo]
    var colors: [ColorInfo]
    var cssTokens: [CSSToken]
    var buttons: [ButtonInfo]
    var fontFaceCSS: String?

    struct ScrollInfo: Codable {
        var x: Double
        var y: Double
        var viewportWidth: Double
        var viewportHeight: Double
        var documentHeight: Double
    }

    struct FontInfo: Codable {
        var fontFamily: String
        var fontSize: String
        var fontWeight: String
        var sampleText: String
        var selector: String?
        var count: Int
    }

    struct ColorInfo: Codable {
        var role: String
        var value: String
        var count: Int
    }

    struct CSSToken: Codable {
        var name: String
        var value: String
    }

    struct ButtonInfo: Codable {
        var text: String
        var html: String
        var width: Double
        var height: Double
        var backgroundColor: String?
        var color: String?
    }
}

func readNativeMessage() -> Data? {
    let input = FileHandle.standardInput
    let lengthData = input.readData(ofLength: 4)
    guard lengthData.count == 4 else { return nil }
    let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    guard length > 0, length < 750_000 else { return nil }
    return input.readData(ofLength: Int(length))
}

func writeNativeMessage(_ object: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    var length = UInt32(data.count).littleEndian
    let prefix = Data(bytes: &length, count: 4)
    FileHandle.standardOutput.write(prefix)
    FileHandle.standardOutput.write(data)
}

func outputURL() throws -> URL {
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directory = support.appendingPathComponent("ezclip", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("browser-context-latest.json")
}

func sourceOutputURL(sourceBrowser: String?) throws -> URL? {
    guard let sourceBrowser, !sourceBrowser.isEmpty else { return nil }
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directory = support
        .appendingPathComponent("ezclip", isDirectory: true)
        .appendingPathComponent("browser-contexts", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(sourceBrowser)-latest.json")
}

func historyOutputURL(sourceBrowser: String?) throws -> URL? {
    guard let sourceBrowser, !sourceBrowser.isEmpty else { return nil }
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let directory = support
        .appendingPathComponent("ezclip/browser-contexts", isDirectory: true)
        .appendingPathComponent(sourceBrowser, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json")
}

func pruneHistory(sourceBrowser: String?) {
    guard let sourceBrowser,
          let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          ) else { return }
    let directory = support.appendingPathComponent("ezclip/browser-contexts/\(sourceBrowser)")
    let files = ((try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []).sorted {
        let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return lhs > rhs
    }
    for file in files.dropFirst(50) { try? FileManager.default.removeItem(at: file) }
}

func atomicallyWrite(_ data: Data, to destination: URL) throws {
    let temporary = destination.deletingLastPathComponent()
        .appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString)")
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
}

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

guard let message = readNativeMessage(),
      var context = try? decoder.decode(BrowserDesignContext.self, from: message) else {
    writeNativeMessage(["ok": "false"])
    exit(1)
}

context.capturedAt = Date()

do {
    let data = try encoder.encode(context)
    let destination = try outputURL()
    try atomicallyWrite(data, to: destination)
    if let sourceDestination = try sourceOutputURL(sourceBrowser: context.sourceBrowser) {
        try atomicallyWrite(data, to: sourceDestination)
    }
    if let historyDestination = try historyOutputURL(sourceBrowser: context.sourceBrowser) {
        try atomicallyWrite(data, to: historyDestination)
        pruneHistory(sourceBrowser: context.sourceBrowser)
    }
    writeNativeMessage(["ok": "true"])
} catch {
    writeNativeMessage(["ok": "false"])
    exit(1)
}
