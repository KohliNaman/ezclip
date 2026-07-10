import XCTest
@testable import ezclip

final class DesignContextTests: XCTestCase {
    func testDesignContextJSONDecodesFontsTokensAndButtons() {
        let json = """
        {
          "url": "https://example.com",
          "title": "Example",
          "capturedAt": "2026-06-12T12:00:00Z",
          "scroll": {"x": 0, "y": 10, "viewportWidth": 1200, "viewportHeight": 800, "documentHeight": 2000},
          "fonts": [{"fontFamily": "Avenir", "fontSize": "16px", "fontWeight": "500", "sampleText": "A useful sample", "selector": "p", "count": 3}],
          "colors": [{"role": "text", "value": "rgb(10, 20, 30)", "count": 5}],
          "cssTokens": [{"name": "--color-primary", "value": "#3366ff"}],
          "buttons": [{"text": "Start", "html": "<button style='color:#fff'>Start</button>", "width": 90, "height": 36, "backgroundColor": "#3366ff", "color": "#fff"}],
          "fontFaceCSS": "@font-face { font-family: Avenir; src: url(https://example.com/avenir.woff2); }"
        }
        """

        let context = BrowserDesignContextStore.decode(json)
        XCTAssertEqual(context?.fonts.first?.fontFamily, "Avenir")
        XCTAssertEqual(context?.cssTokens.first?.name, "--color-primary")
        XCTAssertEqual(context?.buttons.first?.text, "Start")
        XCTAssertTrue(context?.fontFaceCSS?.contains("avenir.woff2") == true)
    }

    func testLatestJSONReusesFreshExactURLForRepeatedScreenshots() throws {
        let data = try designContextData(
            url: "https://example.com/pricing#plans",
            capturedAt: "2026-06-12T12:00:00Z"
        )

        let json = BrowserDesignContextStore.latestJSON(
            from: data,
            matching: "https://example.com/pricing#checkout",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:09:59Z"))
        )

        XCTAssertNotNil(json)
    }

    func testLatestJSONReusesFreshSameHostFallback() throws {
        let data = try designContextData(
            url: "https://example.com/pricing",
            capturedAt: "2026-06-12T12:00:00Z"
        )

        let json = BrowserDesignContextStore.latestJSON(
            from: data,
            matching: "https://example.com/features",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:01:59Z"))
        )

        XCTAssertNotNil(json)
    }

    func testLatestJSONRejectsStaleSameHostFallback() throws {
        let data = try designContextData(
            url: "https://example.com/pricing",
            capturedAt: "2026-06-12T12:00:00Z"
        )

        let json = BrowserDesignContextStore.latestJSON(
            from: data,
            matching: "https://example.com/features",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:02:01Z"))
        )

        XCTAssertNil(json)
    }

    func testLatestJSONRejectsDifferentHost() throws {
        let data = try designContextData(
            url: "https://example.com/pricing",
            capturedAt: "2026-06-12T12:00:00Z"
        )

        let json = BrowserDesignContextStore.latestJSON(
            from: data,
            matching: "https://other.example/features",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:00:30Z"))
        )

        XCTAssertNil(json)
    }

    func testLatestMatchReportsURLMismatch() throws {
        let data = try designContextData(
            url: "https://example.com/pricing",
            capturedAt: "2026-06-12T12:00:00Z"
        )

        let match = BrowserDesignContextStore.latestMatch(
            from: data,
            matching: "https://other.example/features",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:00:30Z"))
        )

        XCTAssertNil(match.json)
        XCTAssertEqual(match.status, .urlMismatch)
    }

    func testLatestMatchReportsRestrictedPage() throws {
        let json = """
        {
          "url": "chrome://extensions",
          "title": "Extensions",
          "capturedAt": "2026-06-12T12:00:00Z",
          "transportStatus": "restrictedPage",
          "transportError": "Cannot access browser page",
          "fonts": [],
          "colors": [],
          "cssTokens": [],
          "buttons": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let match = BrowserDesignContextStore.latestMatch(
            from: data,
            matching: "chrome://extensions",
            now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-12T12:00:30Z"))
        )

        XCTAssertNil(match.json)
        XCTAssertEqual(match.status, .restrictedPage)
        XCTAssertTrue(match.message.contains("Cannot access"))
    }

    func testManifestPayloadUsesExpectedBrowserKeys() throws {
        let chrome = try XCTUnwrap(BrowserExtensionInstaller.manifestTargets.first { $0.sourceBrowser == "chrome" })
        let firefox = try XCTUnwrap(BrowserExtensionInstaller.manifestTargets.first { $0.sourceBrowser == "firefox" })

        let chromePayload = BrowserExtensionInstaller.manifestPayload(for: chrome, bridgePath: "/tmp/bridge")
        let firefoxPayload = BrowserExtensionInstaller.manifestPayload(for: firefox, bridgePath: "/tmp/bridge")

        XCTAssertEqual(chromePayload["name"] as? String, BrowserExtensionInstaller.hostName)
        XCTAssertEqual(chromePayload["allowed_origins"] as? [String], ["chrome-extension://aneomelhkigghoclfgmpejhmpgogpfij/"])
        XCTAssertNil(chromePayload["allowed_extensions"])
        XCTAssertEqual(firefoxPayload["allowed_extensions"] as? [String], ["ezclip-design-context@namaankohli.com"])
        XCTAssertNil(firefoxPayload["allowed_origins"])
    }

    private func designContextData(url: String, capturedAt: String) throws -> Data {
        let json = """
        {
          "url": "\(url)",
          "title": "Example",
          "capturedAt": "\(capturedAt)",
          "sourceBrowser": "chrome",
          "fonts": [],
          "colors": [],
          "cssTokens": [{"name": "--space", "value": "8px"}],
          "buttons": [],
          "fontFaceCSS": "@font-face { font-family: Example; src: url(https://example.com/example.woff2); }"
        }
        """
        return try XCTUnwrap(json.data(using: .utf8))
    }
}
