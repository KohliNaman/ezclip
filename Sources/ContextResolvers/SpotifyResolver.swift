import Foundation

/// Resolves context from Spotify — captures what's ON SCREEN, not what's playing.
///
/// Primary: AppleScript (works on older Spotify versions)
/// Fallback: window title parsing (works on all versions, captures displayed song)
///
/// Why window title matters: if the user is browsing a different song/playlist
/// than what's currently playing, we want to capture what they're LOOKING at,
/// not what's in their ears.
struct SpotifyResolver: AppContextResolver {
    let supportedBundleIds = ["com.spotify.client"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        // ── Try AppleScript first (now-playing info) ──
        let scriptResult = engine.runAppleScript("""
            tell application "Spotify"
                if player state is playing then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    try
                        set artURL to artwork url of current track
                    on error
                        set artURL to ""
                    end try
                    return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & artURL
                else
                    return ""
                end if
            end tell
            """)

        if let info = scriptResult, !info.isEmpty {
            let parts = info.components(separatedBy: "||")
            let song = parts[safe: 0].flatMap { $0.isEmpty ? nil : $0 }
            let artist = parts[safe: 1].flatMap { $0.isEmpty ? nil : $0 }
            let album = parts[safe: 2].flatMap { $0.isEmpty ? nil : $0 }
            let artURL = parts[safe: 3].flatMap { $0.isEmpty ? nil : $0 }

            let artData: Data?
            if let artURL = artURL, let url = URL(string: artURL) {
                artData = try? Data(contentsOf: url)
            } else {
                artData = nil
            }

            return ResolvedContext(
                contextType: .music,
                songName: song,
                artistName: artist,
                albumName: album,
                albumArtData: artData
            )
        }

        // ── Fallback: parse window title ──
        // Spotify window titles: "Song Name — Artist Name"
        // or when browsing: "Playlist Name — Spotify", "Search results", etc.
        return parseWindowTitle(windowTitle)
    }

    /// Parses Spotify's window title for song/artist info.
    /// Spotify free tier and newer versions don't expose AppleScript,
    /// but the window title always reflects what's on screen.
    private func parseWindowTitle(_ title: String) -> ResolvedContext {
        // Clean up: Spotify appends " - Spotify" or " — Spotify" to the title
        var cleaned = title
            .replacingOccurrences(of: " — Spotify", with: "")
            .replacingOccurrences(of: " - Spotify", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Patterns to try:
        // "Song Name — Artist Name" (most common)
        // "Artist Name – Song Name" (sometimes reversed)
        // For browsing: "Playlist Name", "Search", etc.

        let separators = [" — ", " – ", " - ", "–", "—"]

        for sep in separators {
            let parts = cleaned.components(separatedBy: sep)
            if parts.count == 2 {
                let first = parts[0].trimmingCharacters(in: .whitespaces)
                let second = parts[1].trimmingCharacters(in: .whitespaces)

                // Heuristic: if second part looks like an artist (not "Spotify", "Premium", etc.)
                let nonArtist = ["spotify", "premium", "free", "mini player", "now playing"]
                if !nonArtist.contains(where: { second.lowercased().contains($0) })
                    && !first.isEmpty && !second.isEmpty {

                    // Most Spotify window titles show "Song — Artist"
                    return ResolvedContext(
                        contextType: .music,
                        songName: first,
                        artistName: second,
                        albumName: nil,
                        albumArtData: nil
                    )
                }
            }
        }

        // If no clear song/artist separation, treat the whole thing as context
        if !cleaned.isEmpty && cleaned.lowercased() != "spotify" {
            return ResolvedContext(
                contextType: .music,
                songName: cleaned,
                artistName: nil,
                albumName: nil,
                albumArtData: nil
            )
        }

        // Nothing useful
        return ResolvedContext(contextType: .music)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
