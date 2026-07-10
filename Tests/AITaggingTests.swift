import XCTest
@testable import ezclip

@MainActor
final class AITaggingTests: XCTestCase {
    func testTagInputNormalizesAndDeduplicates() {
        XCTAssertEqual(
            LibraryViewModel.parseTagInput(" Pricing Page, pricing page\nSidebar Nav "),
            ["pricing page", "sidebar nav"]
        )
    }

    func testTagSymbolParsesEmojiAndPhosphorStorageValues() {
        let phosphor = TagSymbol(storageValue: "phosphor:briefcase")
        XCTAssertEqual(phosphor?.kind, .phosphor)
        XCTAssertEqual(phosphor?.value, "briefcase")
        XCTAssertEqual(phosphor?.storageValue, "phosphor:briefcase")

        let emoji = TagSymbol(storageValue: "emoji:🚀")
        XCTAssertEqual(emoji?.kind, .emoji)
        XCTAssertEqual(emoji?.value, "🚀")
        XCTAssertEqual(emoji?.storageValue, "emoji:🚀")
    }

    func testLegacyCollectionIconFallsBackToPhosphorFolder() {
        let collection = Collection(
            id: UUID(),
            name: "Legacy",
            color: "blue",
            icon: "folder",
            sortOrder: 0
        )

        XCTAssertEqual(collection.collectionSymbol.kind, .phosphor)
        XCTAssertEqual(collection.collectionSymbol.value, PhosphorTagIcon.folder.rawValue)
    }

    func testAIContextEncodesAndDecodesSearchTags() {
        let context = CaptureAIContext(
            captureId: UUID(),
            visibleTags: ["Landing Page", "landing page", " SaaS "],
            hiddenSearchTags: ["Hero Layout", "CTA Hierarchy"],
            summary: "A focused product hero with strong hierarchy.",
            provider: "gemini",
            model: "gemini-3.1-flash-lite",
            status: .complete,
            confidence: 0.85
        )

        XCTAssertEqual(context.visibleTags, ["landing page", "saas"])
        XCTAssertEqual(context.hiddenSearchTags, ["cta hierarchy", "hero layout"])
        XCTAssertEqual(context.status, .complete)
    }

    func testAutoTagsUseSiteNameWithoutDuplicateDomainTag() {
        var capture = Capture(
            id: UUID(),
            timestamp: Date(),
            appName: "Zen",
            appBundleId: "app.zen-browser.zen",
            windowTitle: "Video - YouTube",
            screenshotPath: "/tmp/example.png",
            thumbnailPath: "/tmp/example_thumb.png",
            contextType: .website,
            notes: nil,
            collectionId: nil,
            isScrolling: false,
            scrollIndex: nil,
            parentCaptureId: nil
        )
        capture.url = "https://www.youtube.com/watch?v=abc"

        let tags = CapturePipeline.deriveAutoTags(from: capture)

        XCTAssertTrue(tags.contains("youtube"))
        XCTAssertFalse(tags.contains("youtube.com"))
    }

    func testBrowserAndSiteTagsAreHiddenButSearchable() {
        var capture = Capture(
            id: UUID(),
            timestamp: Date(),
            appName: "Zen",
            appBundleId: "app.zen-browser.zen",
            windowTitle: "Video - YouTube",
            screenshotPath: "/tmp/example.png",
            thumbnailPath: "/tmp/example_thumb.png",
            contextType: .website,
            notes: nil,
            collectionId: nil,
            isScrolling: false,
            scrollIndex: nil,
            parentCaptureId: nil
        )
        capture.url = "https://www.youtube.com/watch?v=abc"

        XCTAssertTrue(TagVisibility.isHidden("website", for: capture))
        XCTAssertTrue(TagVisibility.isHidden("zen", for: capture))
        XCTAssertTrue(TagVisibility.isHidden("youtube", for: capture))
        XCTAssertFalse(TagVisibility.isHidden("card grid", for: capture))

        let viewModel = LibraryViewModel()
        viewModel.captures = [capture]
        viewModel.tags = [
            Tag(id: UUID(), name: "website", usageCount: 1),
            Tag(id: UUID(), name: "youtube", usageCount: 1),
            Tag(id: UUID(), name: "card grid", usageCount: 1)
        ]
        viewModel.captureTagsByCaptureID = [capture.id: ["website", "youtube", "card grid"]]

        XCTAssertEqual(viewModel.visibleTags(for: capture).map(\.name), ["card grid"])
        viewModel.searchText = "youtube"
        XCTAssertEqual(viewModel.filteredCaptures.map(\.id), [capture.id])
    }

    func testPromptIncludesDesignerSpecificInstructionsAndContext() {
        var capture = Capture(
            id: UUID(),
            timestamp: Date(),
            appName: "Safari",
            appBundleId: "com.apple.Safari",
            windowTitle: "Pricing - Example",
            screenshotPath: "/tmp/example.png",
            thumbnailPath: "/tmp/example_thumb.png",
            contextType: .website,
            notes: "Useful tier comparison",
            collectionId: nil,
            isScrolling: false,
            scrollIndex: nil,
            parentCaptureId: nil
        )
        capture.url = "https://example.com/pricing"
        capture.pageTitle = "Pricing"

        let prompt = AITaggingPromptBuilder.prompt(for: capture)

        XCTAssertTrue(prompt.contains("component taxonomy"))
        XCTAssertTrue(prompt.contains("visibleTags"))
        XCTAssertTrue(prompt.contains("hiddenSearchTags"))
        XCTAssertTrue(prompt.contains("Pricing - Example"))
        XCTAssertTrue(prompt.contains("Useful tier comparison"))
    }

    func testAITaggingResultParserClampsConfidenceAndNormalizesTags() throws {
        let data = """
        {
          "visibleTags": ["Pricing Page", "pricing page", "Card Grid"],
          "hiddenSearchTags": ["Plan Comparison", "Conversion CTA"],
          "summary": "  A compact pricing comparison with clear conversion hierarchy.  ",
          "confidence": 1.4
        }
        """.data(using: .utf8)!

        let result = try AITaggingResultParser.parse(data)

        XCTAssertEqual(result.visibleTags, ["card grid", "pricing page"])
        XCTAssertEqual(result.hiddenSearchTags, ["conversion cta", "plan comparison"])
        XCTAssertEqual(result.summary, "A compact pricing comparison with clear conversion hierarchy.")
        XCTAssertEqual(result.confidence, 1)
    }

    func testAITaggingResultParserAcceptsFencedJSON() throws {
        let data = """
        ```json
        {
          "visibleTags": ["Command Palette"],
          "hiddenSearchTags": ["keyboard driven workflow"],
          "summary": "A compact command surface for fast navigation.",
          "confidence": 0.7
        }
        ```
        """.data(using: .utf8)!

        let result = try AITaggingResultParser.parse(data)

        XCTAssertEqual(result.visibleTags, ["command palette"])
        XCTAssertEqual(result.hiddenSearchTags, ["keyboard driven workflow"])
        XCTAssertEqual(result.confidence, 0.7)
    }

    func testAITaggingResultParserAcceptsStringConfidence() throws {
        let data = """
        {
          "visibleTags": ["Design Inspiration"],
          "hiddenSearchTags": ["browser interface"],
          "summary": "A browser-based design reference.",
          "confidence": "1.0"
        }
        """.data(using: .utf8)!

        let result = try AITaggingResultParser.parse(data)

        XCTAssertEqual(result.visibleTags, ["design inspiration"])
        XCTAssertEqual(result.confidence, 1)
    }

    func testAIImageEncoderDownsamplesLargeImagesForVisionRequests() throws {
        let image = NSImage(size: NSSize(width: 3200, height: 2000))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 3200, height: 2000)).fill()
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let encoded = try AITaggingImageEncoder.encodeForVisionModel(url: url, maxPixelSize: 1000)

        XCTAssertEqual(encoded.mimeType, "image/jpeg")
        XCTAssertLessThan(encoded.data.count, png.count)
    }
}
