@preconcurrency import AppKit
import Foundation
import Vision

struct LocalCaptureEntities: Codable, Equatable, Sendable {
    var links: [String]
    var dates: [String]
    var phoneNumbers: [String]
    var prices: [String]
}

enum LocalCaptureClassifier {
    static func classify(capture: Capture, text: String) -> CaptureKind {
        let value = "\(capture.appName) \(capture.windowTitle) \(capture.url ?? "") \(text)".lowercased()
        if capture.contextType == .music || contains(value, ["spotify", "apple music", "song", "album", "playlist"]) { return .music }
        if contains(value, ["imessage", "whatsapp", "telegram", "message", "replied to you"]) { return .conversation }
        if contains(value, ["booking confirmed", "reservation", "check-in", "check out", "flight", "boarding pass", "hotel"]) { return .booking }
        if contains(value, ["maps", "directions", "restaurant", "museum", "things to do", "visit"]) { return .place }
        if contains(value, ["add to cart", "buy now", "in stock", "price", "wishlist"]) { return .product }
        if capture.contextType == .design || contains(value, ["figma", "design system", "dribbble", "behance"]) { return .design }
        if contains(value, ["instagram", "twitter", "x.com", "linkedin", "tiktok", "followers"]) { return .social }
        if contains(value, ["article", "newsletter", "substack", "medium.com", "read time", "minutes read"]) { return .article }
        if capture.contextType == .file || contains(value, ["pdf", "document", "invoice", "receipt"]) { return .document }
        return .other
    }

    private static func contains(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }
}

actor LocalCaptureAnalysisService {
    static let shared = LocalCaptureAnalysisService()

    func analyze(_ capture: Capture) async {
        let state = CaptureMetrics.signposter.beginInterval("LocalAnalysis")
        defer { CaptureMetrics.signposter.endInterval("LocalAnalysis", state) }
        do {
            let text = try recognizeText(at: URL(fileURLWithPath: capture.screenshotPath))
            let entities = extractEntities(from: text)
            let data = try JSONEncoder().encode(entities)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            let kind = LocalCaptureClassifier.classify(capture: capture, text: text)
            let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(120)) }
            try await DatabaseManager.shared.saveLocalAnalysis(
                captureId: capture.id,
                ocrText: text,
                kind: kind,
                title: title,
                entitiesJSON: json
            )
            NotificationCenter.default.post(name: .captureAIContextChanged, object: capture.id)
        } catch {
            CaptureMetrics.logger.error("Local analysis failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recognizeText(at url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private func extractEntities(from text: String) -> LocalCaptureEntities {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue |
                NSTextCheckingResult.CheckingType.date.rawValue |
                NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        )
        let matches = detector?.matches(in: text, range: range) ?? []
        let pricePattern = #"(?:[$€£₹]\s?\d[\d,.]*|\d[\d,.]*\s?(?:USD|EUR|GBP|INR))"#
        let prices = (try? NSRegularExpression(pattern: pricePattern, options: [.caseInsensitive]))?
            .matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
        return LocalCaptureEntities(
            links: matches.compactMap { $0.url?.absoluteString },
            dates: matches.compactMap { $0.date?.ISO8601Format() },
            phoneNumbers: matches.compactMap(\.phoneNumber),
            prices: prices
        )
    }
}
