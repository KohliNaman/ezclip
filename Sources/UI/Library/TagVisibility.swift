import Foundation

enum TagVisibility {
    private static let globalHiddenTags: Set<String> = [
        "website",
        "safari",
        "chrome",
        "google chrome",
        "arc",
        "zen",
        "firefox",
        "helium"
    ]

    static func isHidden(_ tagName: String, for capture: Capture) -> Bool {
        let normalized = normalize(tagName)
        if globalHiddenTags.contains(normalized) { return true }
        if let siteName = siteName(for: capture), normalized == siteName { return true }
        return false
    }

    static func isHiddenInSidebar(_ tagName: String, captures: [Capture]) -> Bool {
        let normalized = normalize(tagName)
        if globalHiddenTags.contains(normalized) { return true }
        return captures.contains { capture in
            siteName(for: capture) == normalized
        }
    }

    static func siteName(for capture: Capture) -> String? {
        guard let url = capture.url,
              let host = URL(string: url)?.host else { return nil }
        let cleanedHost = host.lowercased().replacingOccurrences(of: "www.", with: "")
        let parts = cleanedHost.components(separatedBy: ".").filter { !$0.isEmpty }
        return parts.count >= 2 ? parts[parts.count - 2] : cleanedHost
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
