import Foundation

/// Resolves context from Spotify using window title only.
///
/// AppleScript doesn't work with Spotify Premium (Apple dropped scripting
/// support in modern Spotify). Even if it did, it would return now-playing
/// info — not what the user is actually LOOKING at (browsing a playlist,
/// searching, etc.).
///
/// Window title reflects what's on screen:
///   "Song Name – Artist Name"     → playing/selected track
///   "Playlist Name"               → browsing a playlist
///   "Search"                      → searching
///   "Spotify Free" / "Spotify Premium" → home screen
struct SpotifyResolver: AppContextResolver {
    let supportedBundleIds = ["com.spotify.client"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        parseWindowTitle(windowTitle)
    }

    /// Parses Spotify's window title for song/artist/context info.
    /// Spotify appends " - Spotify" or " — Spotify" to the title on
    /// some versions.
    private func parseWindowTitle(_ title: String) -> ResolvedContext {
        // Strip Spotify branding suffix
        let cleaned = title
            .replacingOccurrences(of: " — Spotify", with: "")
            .replacingOccurrences(of: " - Spotify", with: "")
            .replacingOccurrences(of: " | Spotify", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Empty / generic
        if cleaned.isEmpty {
            return ResolvedContext(contextType: .music)
        }

        // Detect non-song views
        let lower = cleaned.lowercased()
        let nonSongViews = [
            "spotify free", "spotify premium", "spotify",
            "home", "search", "browse", "library",
            "now playing", "mini player", "miniplayer",
            "made for you", "recommended", "recently played",
            "your library", "liked songs"
        ]
        if nonSongViews.contains(lower) || cleaned.count < 3 {
            return ResolvedContext(
                contextType: .music,
                songName: cleaned,
                artistName: nil,
                albumName: nil,
                albumArtData: nil
            )
        }

        // Try "Song – Artist" or "Song — Artist" patterns
        // Spotify uses em-dash or en-dash between song and artist
        let separators = [" — ", " – ", " - "]

        for sep in separators {
            let parts = cleaned.components(separatedBy: sep)
            if parts.count >= 2 {
                let first = parts[0].trimmingCharacters(in: .whitespaces)
                let second = parts[1].trimmingCharacters(in: .whitespaces)

                // Both parts must be meaningful
                guard !first.isEmpty, !second.isEmpty else { continue }
                guard first.count > 1, second.count > 1 else { continue }

                // Second part shouldn't look like a Spotify UI label
                let uiLabels = ["spotify", "premium", "free", "mini player",
                               "miniplayer", "home", "browse", "search", "library"]
                if uiLabels.contains(where: { second.lowercased().contains($0) }) {
                    continue
                }

                // "Song – Artist"
                return ResolvedContext(
                    contextType: .music,
                    songName: first,
                    artistName: second,
                    albumName: nil,
                    albumArtData: nil
                )
            }
        }

        // No separator found — it's a playlist name or other context
        return ResolvedContext(
            contextType: .music,
            songName: cleaned,
            artistName: nil,
            albumName: nil,
            albumArtData: nil
        )
    }
}
