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
          "buttons": [{"text": "Start", "html": "<button style='color:#fff'>Start</button>", "width": 90, "height": 36, "backgroundColor": "#3366ff", "color": "#fff"}]
        }
        """

        let context = BrowserDesignContextStore.decode(json)
        XCTAssertEqual(context?.fonts.first?.fontFamily, "Avenir")
        XCTAssertEqual(context?.cssTokens.first?.name, "--color-primary")
        XCTAssertEqual(context?.buttons.first?.text, "Start")
    }
}
