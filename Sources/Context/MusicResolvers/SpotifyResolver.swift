import Foundation

struct SpotifyResolver: AppContextResolver {
    let supportedBundleIds = ["com.spotify.client"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        // Fetch song info and artwork URL concurrently
        let info = engine.runAppleScript("""
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

        guard let info = info, !info.isEmpty else {
            return ResolvedContext(contextType: .music)
        }

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
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
