import Foundation

struct BrowserDesignContext: Codable, Sendable {
    var url: String?
    var title: String?
    var capturedAt: Date?
    var scroll: ScrollInfo?
    var fonts: [FontInfo]
    var colors: [ColorInfo]
    var cssTokens: [CSSToken]
    var buttons: [ButtonInfo]
    var fontFaceCSS: String?

    struct ScrollInfo: Codable, Sendable {
        var x: Double
        var y: Double
        var viewportWidth: Double
        var viewportHeight: Double
        var documentHeight: Double
    }

    struct FontInfo: Codable, Identifiable, Sendable {
        var id: String { "\(fontFamily)-\(fontSize)-\(fontWeight)" }
        var fontFamily: String
        var fontSize: String
        var fontWeight: String
        var sampleText: String
        var selector: String?
        var count: Int
    }

    struct ColorInfo: Codable, Identifiable, Sendable {
        var id: String { value }
        var role: String
        var value: String
        var count: Int
    }

    struct CSSToken: Codable, Identifiable, Sendable {
        var id: String { name }
        var name: String
        var value: String
    }

    struct ButtonInfo: Codable, Identifiable, Sendable {
        var id: String { "\(text)-\(html.hashValue)" }
        var text: String
        var html: String
        var width: Double
        var height: Double
        var backgroundColor: String?
        var color: String?
    }
}

enum BrowserDesignContextStore {
    private static let maxExactURLAge: TimeInterval = 10 * 60
    private static let maxHostAge: TimeInterval = 2 * 60

    static var latestContextURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("ezclip", isDirectory: true)
            .appendingPathComponent("browser-context-latest.json")
    }

    static func latestJSON(matching url: String?) -> String? {
        guard let latestContextURL,
              let data = try? Data(contentsOf: latestContextURL),
              data.count < 750_000,
              let context = try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: data)
        else { return nil }

        if let url, let contextURL = context.url,
           normalizedURL(url) != normalizedURL(contextURL) {
            guard sameHost(url, contextURL),
                  isFresh(context, maxAge: maxHostAge) else { return nil }
        } else if !isFresh(context, maxAge: maxExactURLAge) {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> BrowserDesignContext? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: data)
    }

    private static func normalizedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return value }
        components.fragment = nil
        return components.string ?? value
    }

    private static func sameHost(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsHost = URLComponents(string: lhs)?.host?.lowercased(),
              let rhsHost = URLComponents(string: rhs)?.host?.lowercased() else { return false }
        return lhsHost == rhsHost
    }

    private static func isFresh(_ context: BrowserDesignContext, maxAge: TimeInterval) -> Bool {
        guard let capturedAt = context.capturedAt else { return true }
        return abs(capturedAt.timeIntervalSinceNow) <= maxAge
    }
}

extension JSONDecoder {
    static var ezclip: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
