import XCTest
@testable import ezclip

final class ContextParsingTests: XCTestCase {
    func testExtractURLTrimsTrailingPunctuation() {
        let text = "Look at https://example.com/path?q=1)."
        XCTAssertEqual(ContextResolverEngine.shared.extractURL(from: text), "https://example.com/path?q=1")
    }

    func testExtractURLFromPercentEncodedTitle() {
        let text = "redirect=https%3A%2F%2Fexample.com%2Fdesign"
        XCTAssertEqual(ContextResolverEngine.shared.extractURL(from: text), "https://example.com/design")
    }

    func testSessionstoreActiveURLUsesMostRecentTab() {
        let json: [String: Any] = [
            "windows": [[
                "tabs": [
                    [
                        "lastAccessed": 10.0,
                        "index": 1,
                        "entries": [["url": "https://older.example"]]
                    ],
                    [
                        "lastAccessed": 20.0,
                        "index": 1,
                        "entries": [["url": "https://newer.example"]]
                    ]
                ]
            ]]
        ]

        XCTAssertEqual(SessionstoreUtils.extractActiveURL(from: json), "https://newer.example")
    }

    func testSessionstoreActiveURLPrefersSelectedTab() {
        let json: [String: Any] = [
            "windows": [[
                "selected": 1,
                "tabs": [
                    [
                        "lastAccessed": 10.0,
                        "index": 1,
                        "entries": [["url": "https://selected.example"]]
                    ],
                    [
                        "lastAccessed": 20.0,
                        "index": 1,
                        "entries": [["url": "https://newer-background.example"]]
                    ]
                ]
            ]]
        ]

        XCTAssertEqual(SessionstoreUtils.extractActiveURL(from: json), "https://selected.example")
    }

    func testSessionstoreActiveURLMatchesCapturedWindowTitleBeforeFirstWindow() {
        let json: [String: Any] = [
            "windows": [
                [
                    "selected": 1,
                    "tabs": [[
                        "lastAccessed": 30.0,
                        "index": 1,
                        "entries": [[
                            "url": "https://youtube.com/watch?v=music",
                            "title": "lofi music - YouTube"
                        ]]
                    ]]
                ],
                [
                    "selected": 1,
                    "tabs": [[
                        "lastAccessed": 20.0,
                        "index": 1,
                        "entries": [[
                            "url": "https://example.com/product",
                            "title": "Product Design System"
                        ]]
                    ]]
                ]
            ]
        ]

        XCTAssertEqual(
            SessionstoreUtils.extractActiveURL(from: json, matchingWindowTitle: "Product Design System — Zen"),
            "https://example.com/product"
        )
    }

    func testZenRecoveryFileUsesLockedProfilesINIProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ezclip-tests-\(UUID().uuidString)")
        let emptyProfile = root.appendingPathComponent("Profiles/yxzfgojp.Default Profile")
        let activeProfile = root.appendingPathComponent("Profiles/npidzgrp.Default (release)")
        let backups = activeProfile.appendingPathComponent("sessionstore-backups")
        try FileManager.default.createDirectory(at: emptyProfile, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profilesINI = """
        [Install6ED35B3CA1B5D3AF]
        Default=Profiles/npidzgrp.Default (release)
        Locked=1

        [Profile1]
        Name=Default Profile
        IsRelative=1
        Path=Profiles/yxzfgojp.Default Profile
        Default=1

        [Profile0]
        Name=Default (release)
        IsRelative=1
        Path=Profiles/npidzgrp.Default (release)
        """
        try profilesINI.data(using: .utf8)!.write(to: root.appendingPathComponent("profiles.ini"))
        let recovery = backups.appendingPathComponent("recovery.jsonlz4")
        try Data("fake".utf8).write(to: recovery)

        XCTAssertEqual(
            SessionstoreUtils.findRecoveryFile(appSupportURL: root)?.standardizedFileURL,
            recovery.standardizedFileURL
        )
    }

    func testChromiumSessionReaderUsesLatestSessionURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ezclip-tests-\(UUID().uuidString)")
        let profile = root.appendingPathComponent("Default")
        let sessions = profile.appendingPathComponent("Sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try #"{"profile":{"last_used":"Default"}}"#.data(using: .utf8)!
            .write(to: root.appendingPathComponent("Local State"))
        try "noise https://example.com/old".data(using: .utf8)!
            .write(to: sessions.appendingPathComponent("Tabs_1"))
        try "noise https://example.com/current".data(using: .utf8)!
            .write(to: sessions.appendingPathComponent("Tabs_2"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)],
            ofItemAtPath: sessions.appendingPathComponent("Tabs_1").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)],
            ofItemAtPath: sessions.appendingPathComponent("Tabs_2").path
        )

        let reader = ChromiumSessionReader(profileRoot: root)
        XCTAssertEqual(reader.readMostRecentURL()?.url, "https://example.com/current")
    }
}
