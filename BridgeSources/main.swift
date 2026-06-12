import Foundation

struct BrowserDesignContext: Codable {
    var url: String?
    var title: String?
    var capturedAt: Date?
    var scroll: ScrollInfo?
    var fonts: [FontInfo]
    var colors: [ColorInfo]
    var cssTokens: [CSSToken]
    var buttons: [ButtonInfo]

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
    let temporary = destination.deletingLastPathComponent()
        .appendingPathComponent(".browser-context-\(UUID().uuidString).json")
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
    writeNativeMessage(["ok": "true"])
} catch {
    writeNativeMessage(["ok": "false"])
    exit(1)
}
