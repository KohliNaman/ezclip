@preconcurrency import AppKit
import Foundation
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AITaggingProviderKind: String, CaseIterable, Identifiable {
    case off
    case gemini
    case appleLocal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .gemini: "Gemini"
        case .appleLocal: "Apple Local"
        }
    }
}

struct AITaggingSettings {
    var providerKind: AITaggingProviderKind
    var autoTagNewCaptures: Bool
    var bypassRateLimit: Bool
    var maxTagsPerRun: Int
    var delayBetweenRequests: TimeInterval
    var geminiAPIKey: String
    var geminiModel: String
    var allowCloudVision: Bool

    static var current: AITaggingSettings {
        let defaults = UserDefaults.standard
        return AITaggingSettings(
            providerKind: AITaggingProviderKind(rawValue: defaults.string(forKey: "ezclip.ai.provider") ?? "off") ?? .off,
            autoTagNewCaptures: defaults.bool(forKey: "ezclip.ai.autoTagNewCaptures"),
            bypassRateLimit: defaults.bool(forKey: "ezclip.ai.bypassRateLimit"),
            maxTagsPerRun: max(1, defaults.object(forKey: "ezclip.ai.maxTagsPerRun") as? Int ?? 12),
            delayBetweenRequests: max(0, defaults.object(forKey: "ezclip.ai.delayBetweenRequests") as? TimeInterval ?? 8),
            geminiAPIKey: KeychainStore.string(for: "geminiAPIKey") ?? defaults.string(forKey: "ezclip.ai.geminiAPIKey") ?? "",
            geminiModel: defaults.string(forKey: "ezclip.ai.geminiModel") ?? "gemini-3.1-flash-lite",
            allowCloudVision: defaults.bool(forKey: "ezclip.ai.allowCloudVision")
        )
    }
}

struct AITaggingRequest: Sendable {
    var capture: Capture
    var imageData: Data
    var imageMimeType: String
}

struct AITaggingResult: Codable, Equatable, Sendable {
    var visibleTags: [String]
    var hiddenSearchTags: [String]
    var summary: String
    var confidence: Double
    var kind: CaptureKind? = nil
    var suggestedTitle: String? = nil
    var entities: [String: [String]]? = nil
}

struct AITaggingProviderAvailability: Equatable, Sendable {
    enum State: String, Sendable {
        case available
        case unavailable
        case unknown
    }

    var state: State
    var message: String
}

protocol AITaggingProvider: Sendable {
    var providerId: String { get }
    var modelId: String { get }
    func generateTags(for request: AITaggingRequest) async throws -> AITaggingResult
}

enum AITaggingError: LocalizedError {
    case providerOff
    case missingAPIKey
    case imageUnavailable
    case unsupportedProvider(String)
    case cloudVisionDisabled
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerOff: "AI tagging is off."
        case .missingAPIKey: "Gemini API key is missing."
        case .imageUnavailable: "The screenshot file is unavailable."
        case .unsupportedProvider(let message): message
        case .cloudVisionDisabled: "Enable screenshot uploads in Settings > AI before using Gemini vision."
        case .invalidResponse: "The AI provider returned an invalid response."
        case .requestFailed(let message): message
        }
    }
}

@MainActor
final class AITaggingService {
    static let shared = AITaggingService()

    private let db = DatabaseManager.shared
    private var automaticTagsThisRun = 0
    private var lastAutomaticTagDate: Date?

    private init() {}

    func generateTags(for capture: Capture, isUserInitiated: Bool = true) async {
        let settings = AITaggingSettings.current
        guard await canStartTagging(capture: capture, settings: settings, isUserInitiated: isUserInitiated) else {
            return
        }

        guard settings.providerKind != .off else {
            await saveFailure(
                for: capture,
                provider: settings.providerKind.rawValue,
                model: settings.geminiModel,
                error: AITaggingError.providerOff
            )
            return
        }

        let provider: AITaggingProvider
        do {
            provider = try makeProvider(settings: settings)
        } catch {
            await saveFailure(for: capture, provider: settings.providerKind.rawValue, model: settings.geminiModel, error: error)
            return
        }

        let existing = try? await db.aiTaggingContext(for: capture.id)
        do {
            try await db.saveAITaggingContext(.pending(
                captureId: capture.id,
                provider: provider.providerId,
                model: provider.modelId,
                existing: existing
            ))
            NotificationCenter.default.post(name: .captureAIContextChanged, object: capture.id)

            let request = try await makeRequest(for: capture)
            let result = try await provider.generateTags(for: request)
            let visibleTags = DatabaseManager.normalizedTagNames(result.visibleTags)
            let hiddenTags = DatabaseManager.normalizedTagNames(result.hiddenSearchTags)
            let context = CaptureAIContext(
                captureId: capture.id,
                visibleTags: visibleTags,
                hiddenSearchTags: hiddenTags,
                summary: result.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                provider: provider.providerId,
                model: provider.modelId,
                status: .complete,
                confidence: min(max(result.confidence, 0), 1),
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date()
                , kind: result.kind ?? existing?.kind ?? .other
                , suggestedTitle: result.suggestedTitle ?? existing?.suggestedTitle
                , entitiesJSON: Self.entitiesJSON(result.entities) ?? existing?.entitiesJSON ?? "{}"
                , ocrText: existing?.ocrText
                , attemptCount: existing?.attemptCount ?? 0
            )
            try await db.saveAITaggingContext(context)
            try await db.addTagNames(visibleTags, to: [capture.id])
            NotificationCenter.default.post(name: .captureAIContextChanged, object: capture.id)
            NotificationCenter.default.post(name: .captureTagsChanged, object: capture.id)
        } catch {
            await saveFailure(for: capture, provider: provider.providerId, model: provider.modelId, error: error)
        }
    }

    nonisolated private static func entitiesJSON(_ entities: [String: [String]]?) -> String? {
        guard let entities, let data = try? JSONEncoder().encode(entities) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func canStartTagging(capture: Capture, settings: AITaggingSettings, isUserInitiated: Bool) async -> Bool {
        guard !isUserInitiated, !settings.bypassRateLimit else { return true }

        let existing = try? await db.aiTaggingContext(for: capture.id)
        guard automaticTagsThisRun < settings.maxTagsPerRun else {
            try? await db.saveAITaggingContext(.skipped(
                captureId: capture.id,
                provider: settings.providerKind.rawValue,
                model: settings.geminiModel,
                message: "Skipped by AI rate limit. Use Settings > AI to backfill later or bypass the limit.",
                existing: existing
            ))
            NotificationCenter.default.post(name: .captureAIContextChanged, object: capture.id)
            return false
        }

        if let lastAutomaticTagDate,
           settings.delayBetweenRequests > 0 {
            let elapsed = Date().timeIntervalSince(lastAutomaticTagDate)
            if elapsed < settings.delayBetweenRequests {
                try? await Task.sleep(nanoseconds: UInt64((settings.delayBetweenRequests - elapsed) * 1_000_000_000))
            }
        }

        automaticTagsThisRun += 1
        lastAutomaticTagDate = Date()
        return true
    }

    func generateTags(for captures: [Capture], isUserInitiated: Bool = true) async {
        let settings = AITaggingSettings.current
        let limitedCaptures = settings.bypassRateLimit ? captures : Array(captures.prefix(settings.maxTagsPerRun))
        for (index, capture) in limitedCaptures.enumerated() {
            if index > 0, !settings.bypassRateLimit, settings.delayBetweenRequests > 0 {
                try? await Task.sleep(nanoseconds: UInt64(settings.delayBetweenRequests * 1_000_000_000))
            }
            await generateTags(for: capture, isUserInitiated: isUserInitiated)
        }
    }

    private func makeProvider(settings: AITaggingSettings) throws -> AITaggingProvider {
        switch settings.providerKind {
        case .off:
            throw AITaggingError.providerOff
        case .gemini:
            guard settings.allowCloudVision else { throw AITaggingError.cloudVisionDisabled }
            guard !settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AITaggingError.missingAPIKey
            }
            return GeminiVisionTaggingProvider(apiKey: settings.geminiAPIKey, modelId: settings.geminiModel)
        case .appleLocal:
            return AppleFoundationTaggingProvider()
        }
    }

    private func makeRequest(for capture: Capture) async throws -> AITaggingRequest {
        let url = URL(fileURLWithPath: capture.screenshotPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AITaggingError.imageUnavailable
        }
        return try await Task.detached(priority: .utility) {
            let encoded = try AITaggingImageEncoder.encodeForVisionModel(url: url)
            return AITaggingRequest(capture: capture, imageData: encoded.data, imageMimeType: encoded.mimeType)
        }.value
    }

    private func saveFailure(for capture: Capture, provider: String, model: String, error: Error) async {
        let existing = try? await db.aiTaggingContext(for: capture.id)
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let message = String(rawMessage.prefix(700))
        try? await db.saveAITaggingContext(.failed(
            captureId: capture.id,
            provider: provider,
            model: model,
            message: message,
            existing: existing
        ))
        NotificationCenter.default.post(name: .captureAIContextChanged, object: capture.id)
    }
}

struct AITaggingPromptBuilder {
    static func prompt(for capture: Capture) -> String {
        var lines: [String] = [
            "You organize screenshots for ezclip, a personal visual memory library.",
            "The archive contains songs, conversations, bookings, places, articles, products, social posts, documents, and design references.",
            "Optimize for retrieval months later: identify what this is, who or what it concerns, and why the user may want it again.",
            "Return strict JSON only. No markdown, no commentary.",
            "",
            "Tagging rules:",
            "- kind: exactly one of music, conversation, booking, place, article, design, product, social, document, other.",
            "- suggestedTitle: a concise human title based only on visible evidence.",
            "- visibleTags: 4-10 concise reusable user-facing tags.",
            "- hiddenSearchTags: 10-30 retrieval phrases, including names, locations, dates, categories, topics, and likely future queries.",
            "- entities: arrays named people, places, dates, prices, artists, songs, brands, and links. Omit unsupported guesses.",
            "- summary: one short paragraph saying what was saved and why it may be useful.",
            "- confidence: number from 0 to 1.",
            "- Do not create tags that are only raw colors. Color context is provided separately and can inform the summary.",
            "- For design captures, include precise component taxonomy and layout terms. For other captures, prioritize factual retrieval over visual style.",
            "",
            "JSON schema:",
            #"{"kind":"place","suggestedTitle":"Kyoto coffee shop","visibleTags":["kyoto","coffee"],"hiddenSearchTags":["quiet cafe in kyoto"],"entities":{"places":["Kyoto"]},"summary":"A cafe worth visiting.","confidence":0.8}"#,
            "",
            "Capture context:",
            "- app: \(capture.appName)",
            "- bundleId: \(capture.appBundleId)",
            "- windowTitle: \(capture.windowTitle)",
            "- contextType: \(capture.contextType.rawValue)"
        ]

        if let url = capture.url { lines.append("- url: \(url)") }
        if let pageTitle = capture.pageTitle { lines.append("- pageTitle: \(pageTitle)") }
        if let fileName = capture.designFileName { lines.append("- designFileName: \(fileName)") }
        if let pageName = capture.designPageName { lines.append("- designPageName: \(pageName)") }
        if let notes = capture.notes { lines.append("- userNotes: \(notes)") }
        if let designContext = BrowserDesignContextStore.decode(capture.designContextJSON) {
            appendDesignContext(designContext, to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    static func localPrompt(for capture: Capture) -> String {
        prompt(for: capture) + "\n\nLocal provider note: You cannot inspect raw pixels in this mode. Infer useful design tags only from the capture metadata and extracted browser design context above. If visual evidence is weak, lower confidence."
    }

    private static func appendDesignContext(_ context: BrowserDesignContext, to lines: inout [String]) {
        if !context.fonts.isEmpty {
            let fonts = context.fonts.prefix(8).map { font in
                "\(font.fontFamily) \(font.fontWeight) \(font.fontSize)"
            }
            lines.append("- fonts: \(fonts.joined(separator: ", "))")
        }
        if !context.colors.isEmpty {
            let colors = context.colors.prefix(12).map { "\($0.role): \($0.value)" }
            lines.append("- capturedColors: \(colors.joined(separator: ", "))")
        }
        if !context.cssTokens.isEmpty {
            let tokens = context.cssTokens.prefix(12).map { "\($0.name)=\($0.value)" }
            lines.append("- cssTokens: \(tokens.joined(separator: ", "))")
        }
        if !context.buttons.isEmpty {
            let buttons = context.buttons.prefix(8).map { button in
                "\(button.text) \(Int(button.width))x\(Int(button.height))"
            }
            lines.append("- buttons: \(buttons.joined(separator: ", "))")
        }
    }
}

enum AITaggingImageEncoder {
    static func encodeForVisionModel(url: URL, maxPixelSize: CGFloat = 1600) throws -> (data: Data, mimeType: String) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AITaggingError.imageUnavailable
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AITaggingError.imageUnavailable
        }

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            throw AITaggingError.imageUnavailable
        }
        return (data, "image/jpeg")
    }
}

struct GeminiVisionTaggingProvider: AITaggingProvider {
    let apiKey: String
    let modelId: String

    var providerId: String { "gemini" }
    var endpointURL: URL { URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelId):generateContent")! }

    func generateTags(for request: AITaggingRequest) async throws -> AITaggingResult {
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.timeoutInterval = 45

        let payload = GeminiGenerateContentRequest(
            contents: [
                GeminiContent(parts: [
                    .text(AITaggingPromptBuilder.prompt(for: request.capture)),
                    .inlineData(GeminiInlineData(mimeType: request.imageMimeType, data: request.imageData.base64EncodedString()))
                ])
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.2,
                responseMimeType: "application/json",
                responseSchema: GeminiResponseSchema.aiTagging
            )
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await performWithRetry(urlRequest)

        let apiResponse = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        guard let text = apiResponse.candidates.first?.content.parts.compactMap(\.text).joined(),
              let resultData = text.data(using: .utf8) else {
            throw AITaggingError.invalidResponse
        }
        return try AITaggingResultParser.parse(resultData)
    }

    private func performWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return (data, response) }
                if (200..<300).contains(http.statusCode) { return (data, response) }
                let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
                guard retryable, attempt < 2 else {
                    throw AITaggingError.requestFailed("Gemini request failed with HTTP \(http.statusCode).")
                }
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                let delay = retryAfter ?? pow(2, Double(attempt))
                attempt += 1
                try await Task.sleep(for: .seconds(delay))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < 2, !(error is AITaggingError) else { throw error }
                attempt += 1
                try await Task.sleep(for: .seconds(pow(2, Double(attempt - 1))))
            }
        }
    }
}

struct AppleFoundationTaggingProvider: AITaggingProvider {
    var providerId: String { "appleLocal" }
    var modelId: String { "foundation-models" }

    static func availability() -> AITaggingProviderAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .contentTagging)
            switch model.availability {
            case .available:
                return AITaggingProviderAvailability(
                    state: .available,
                    message: "Apple Foundation Models are available for local text/context tagging."
                )
            default:
                return AITaggingProviderAvailability(
                    state: .unavailable,
                    message: "Apple Intelligence is not available. Enable it in System Settings > Apple Intelligence & Siri."
                )
            }
        }
        #endif
        return AITaggingProviderAvailability(
            state: .unavailable,
            message: "Apple Local requires macOS 26 or newer with Apple Intelligence enabled."
        )
    }

    func generateTags(for request: AITaggingRequest) async throws -> AITaggingResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .contentTagging)
            guard case .available = model.availability else {
                throw AITaggingError.unsupportedProvider("Apple Intelligence is not available right now. Enable it in System Settings > Apple Intelligence & Siri, then try Apple Local again.")
            }
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: AITaggingPromptBuilder.localPrompt(for: request.capture))
            guard let data = response.content.data(using: .utf8) else {
                throw AITaggingError.invalidResponse
            }
            return try AITaggingResultParser.parse(data)
        }
        #endif
        throw AITaggingError.unsupportedProvider("Apple Local tagging requires macOS 26 or newer with Apple Intelligence enabled. Use Gemini or keep AI tagging off on this Mac.")
    }
}

enum AITaggingResultParser {
    static func parse(_ data: Data) throws -> AITaggingResult {
        let decoder = JSONDecoder()
        let result: RawAITaggingResult
        do {
            result = try decoder.decode(RawAITaggingResult.self, from: data)
        } catch {
            result = try decoder.decode(RawAITaggingResult.self, from: extractJSONObject(from: data))
        }
        return AITaggingResult(
            visibleTags: DatabaseManager.normalizedTagNames(result.visibleTags),
            hiddenSearchTags: DatabaseManager.normalizedTagNames(result.hiddenSearchTags),
            summary: result.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: min(max(result.confidence.value, 0), 1),
            kind: result.kind.flatMap(CaptureKind.init(rawValue:)),
            suggestedTitle: result.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            entities: result.entities
        )
    }

    private static func extractJSONObject(from data: Data) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw AITaggingError.invalidResponse
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end,
              let jsonData = String(text[start...end]).data(using: .utf8) else {
            throw AITaggingError.invalidResponse
        }
        return jsonData
    }
}

private struct RawAITaggingResult: Decodable {
    var visibleTags: [String]
    var hiddenSearchTags: [String]
    var summary: String
    var confidence: FlexibleDouble
    var kind: String?
    var suggestedTitle: String?
    var entities: [String: [String]]?
}

private struct FlexibleDouble: Decodable {
    var value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self),
                  let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            value = double
        } else {
            throw AITaggingError.invalidResponse
        }
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Codable {
    var parts: [GeminiPart]
}

private enum GeminiPart: Codable {
    case text(String)
    case inlineData(GeminiInlineData)

    enum CodingKeys: String, CodingKey {
        case text
        case inlineData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else if let inlineData = try container.decodeIfPresent(GeminiInlineData.self, forKey: .inlineData) {
            self = .inlineData(inlineData)
        } else {
            throw AITaggingError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .inlineData(let inlineData):
            try container.encode(inlineData, forKey: .inlineData)
        }
    }

    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

private struct GeminiInlineData: Codable {
    var mimeType: String
    var data: String
}

private struct GeminiGenerationConfig: Encodable {
    var temperature: Double
    var responseMimeType: String
    var responseSchema: GeminiResponseSchema
}

private indirect enum GeminiResponseSchema: Encodable, Sendable {
    case string
    case number
    case array(GeminiResponseSchema)
    case object(properties: [String: GeminiResponseSchema], required: [String])

    static let aiTagging: GeminiResponseSchema = .object(
        properties: [
            "visibleTags": .array(.string),
            "hiddenSearchTags": .array(.string),
            "summary": .string,
            "confidence": .number
            , "kind": .string
            , "suggestedTitle": .string
            , "entities": .object(
                properties: [
                    "people": .array(.string), "places": .array(.string),
                    "dates": .array(.string), "prices": .array(.string),
                    "artists": .array(.string), "songs": .array(.string),
                    "brands": .array(.string), "links": .array(.string)
                ],
                required: []
            )
        ],
        required: ["visibleTags", "hiddenSearchTags", "summary", "confidence"]
    )

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case items
        case required
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string:
            try container.encode("STRING", forKey: .type)
        case .number:
            try container.encode("NUMBER", forKey: .type)
        case .array(let itemSchema):
            try container.encode("ARRAY", forKey: .type)
            try container.encode(itemSchema, forKey: .items)
        case .object(let properties, let required):
            try container.encode("OBJECT", forKey: .type)
            try container.encode(properties, forKey: .properties)
            try container.encode(required, forKey: .required)
        }
    }
}

private struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    var content: GeminiContent
}
