import Foundation

struct BrowserDesignContext: Codable, Sendable {
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

enum BrowserDesignEnrichmentStatus: String, Codable, Sendable, CaseIterable {
    case enriched
    case extensionMissing
    case nativeHostMissing
    case stalePayload
    case urlMismatch
    case emptyPayload
    case restrictedPage
    case transportFailed

    var displayName: String {
        switch self {
        case .enriched: "Design context ready"
        case .extensionMissing: "Extension missing"
        case .nativeHostMissing: "Native host missing"
        case .stalePayload: "Extension data stale"
        case .urlMismatch: "Extension data from another page"
        case .emptyPayload: "No design data found"
        case .restrictedPage: "Browser blocked this page"
        case .transportFailed: "Extension connection failed"
        }
    }

    var isMissing: Bool { self != .enriched }
}

struct BrowserDesignContextMatch: Sendable {
    var json: String?
    var status: BrowserDesignEnrichmentStatus
    var message: String
    var sourceBrowser: String?
    var updatedAt: Date?
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

    static var recordsDirectoryURL: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("ezclip", isDirectory: true)
            .appendingPathComponent("browser-contexts", isDirectory: true)
    }

    static func latestJSON(matching url: String?) -> String? {
        latestMatch(matching: url, bundleId: nil).json
    }

    static func authoritativeContext(
        matchingWindowTitle windowTitle: String,
        bundleId: String?,
        now: Date = Date()
    ) -> BrowserDesignContext? {
        let source = sourceBrowser(for: bundleId)
        return candidatePayloads(sourceBrowser: source).compactMap { payload -> BrowserDesignContext? in
            guard let context = try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: payload.data),
                  context.sourceBrowser == source,
                  isFresh(context, maxAge: 30, now: now),
                  titleScore(context.title, windowTitle) >= 2
            else { return nil }
            return context
        }.first
    }

    static func latestMatch(matching url: String?, bundleId: String?, now: Date = Date()) -> BrowserDesignContextMatch {
        let source = sourceBrowser(for: bundleId)
        let payloads = candidatePayloads(sourceBrowser: source)
        guard !payloads.isEmpty else {
            let health = BrowserExtensionDiagnostics.health(for: bundleId)
            return BrowserDesignContextMatch(
                json: nil,
                status: health.status,
                message: health.message,
                sourceBrowser: source,
                updatedAt: nil
            )
        }

        let matches = payloads.map { payload in
            match(data: payload.data, requestedURL: url, now: now, fileModifiedAt: payload.modifiedAt)
        }
        if let enriched = matches.first(where: { $0.status == .enriched }) {
            return enriched
        }
        return matches.first ?? BrowserDesignContextMatch(
            json: nil,
            status: .emptyPayload,
            message: "No browser design context payload could be decoded.",
            sourceBrowser: source,
            updatedAt: nil
        )
    }

    static func latestJSON(from data: Data, matching url: String?, now: Date = Date()) -> String? {
        match(data: data, requestedURL: url, now: now, fileModifiedAt: nil).json
    }

    static func latestMatch(from data: Data, matching url: String?, now: Date = Date()) -> BrowserDesignContextMatch {
        match(data: data, requestedURL: url, now: now, fileModifiedAt: nil)
    }

    static func decode(_ json: String?) -> BrowserDesignContext? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: data)
    }

    static func sourceBrowser(for bundleId: String?) -> String? {
        switch bundleId {
        case "com.google.Chrome": "chrome"
        case "net.imput.helium": "helium"
        case "org.mozilla.firefox": "firefox"
        case "app.zen-browser.zen": "zen"
        default: nil
        }
    }

    private static func candidatePayloads(sourceBrowser: String?) -> [(data: Data, modifiedAt: Date?)] {
        var urls: [URL] = []
        if let sourceBrowser, let recordsDirectoryURL {
            let historyDirectory = recordsDirectoryURL.appendingPathComponent(sourceBrowser, isDirectory: true)
            let history = ((try? FileManager.default.contentsOfDirectory(
                at: historyDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []).sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            urls.append(contentsOf: history.prefix(50))
            urls.append(recordsDirectoryURL.appendingPathComponent("\(sourceBrowser)-latest.json"))
            switch sourceBrowser {
            case "chrome", "helium":
                urls.append(recordsDirectoryURL.appendingPathComponent("chromium-latest.json"))
            case "firefox", "zen":
                urls.append(recordsDirectoryURL.appendingPathComponent("firefox-latest.json"))
            default:
                break
            }
        }
        if let latestContextURL {
            urls.append(latestContextURL)
        }

        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url), data.count < 750_000 else { return nil }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (data, modified)
        }
    }

    private static func match(
        data: Data,
        requestedURL url: String?,
        now: Date,
        fileModifiedAt: Date?
    ) -> BrowserDesignContextMatch {
        guard data.count < 750_000,
              let context = try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: data)
        else {
            return BrowserDesignContextMatch(
                json: nil,
                status: .emptyPayload,
                message: "The browser payload was empty, too large, or invalid.",
                sourceBrowser: nil,
                updatedAt: fileModifiedAt
            )
        }

        let updatedAt = context.capturedAt ?? context.extractedAt ?? fileModifiedAt
        if context.transportStatus == BrowserDesignEnrichmentStatus.restrictedPage.rawValue {
            return BrowserDesignContextMatch(
                json: nil,
                status: .restrictedPage,
                message: context.transportError ?? "The browser blocked extension access to this page.",
                sourceBrowser: context.sourceBrowser,
                updatedAt: updatedAt
            )
        }
        if context.transportStatus == BrowserDesignEnrichmentStatus.transportFailed.rawValue {
            return BrowserDesignContextMatch(
                json: nil,
                status: .transportFailed,
                message: context.transportError ?? "The extension could not send design context to ezclip.",
                sourceBrowser: context.sourceBrowser,
                updatedAt: updatedAt
            )
        }

        if let url, let contextURL = context.url,
           normalizedURL(url) != normalizedURL(contextURL) {
            let sameHost = sameHost(url, contextURL)
            guard sameHost, isFresh(context, maxAge: maxHostAge, now: now) else {
                return BrowserDesignContextMatch(
                    json: nil,
                    status: sameHost ? .stalePayload : .urlMismatch,
                    message: sameHost
                        ? "The latest extension data is older than the same-host fallback window."
                        : "The latest extension data came from \(contextURL), not this capture.",
                    sourceBrowser: context.sourceBrowser,
                    updatedAt: updatedAt
                )
            }
        } else if !isFresh(context, maxAge: maxExactURLAge, now: now) {
            return BrowserDesignContextMatch(
                json: nil,
                status: .stalePayload,
                message: "The latest extension data is too old for this capture.",
                sourceBrowser: context.sourceBrowser,
                updatedAt: updatedAt
            )
        }

        let hasDesignData = !context.fonts.isEmpty || !context.colors.isEmpty ||
            !context.cssTokens.isEmpty || !context.buttons.isEmpty ||
            !(context.fontFaceCSS?.isEmpty ?? true)
        guard hasDesignData else {
            return BrowserDesignContextMatch(
                json: nil,
                status: .emptyPayload,
                message: "The extension ran, but did not find fonts, colors, CSS tokens, or buttons.",
                sourceBrowser: context.sourceBrowser,
                updatedAt: updatedAt
            )
        }

        return BrowserDesignContextMatch(
            json: String(data: data, encoding: .utf8),
            status: .enriched,
            message: "Design context matched this capture.",
            sourceBrowser: context.sourceBrowser,
            updatedAt: updatedAt
        )
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

    private static func isFresh(_ context: BrowserDesignContext, maxAge: TimeInterval, now: Date) -> Bool {
        guard let capturedAt = context.capturedAt else { return true }
        return abs(capturedAt.timeIntervalSince(now)) <= maxAge
    }

    private static func titleScore(_ lhs: String?, _ rhs: String) -> Int {
        guard let lhs else { return 0 }
        let left = titleWords(lhs)
        let right = titleWords(rhs)
        if left == right, !left.isEmpty { return 100 }
        return left.intersection(right).count
    }

    private static func titleWords(_ value: String) -> Set<String> {
        Set(value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !["zen", "firefox", "mozilla"].contains($0) })
    }
}

extension JSONDecoder {
    static var ezclip: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
