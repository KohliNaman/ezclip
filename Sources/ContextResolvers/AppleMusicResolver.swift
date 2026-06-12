import Foundation

struct AppleMusicResolver: AppContextResolver {
    let supportedBundleIds = ["com.apple.Music"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        let info = engine.runAppleScript("""
            tell application "Music"
                if player state is playing then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & "||" & trackArtist & "||" & trackAlbum
                else
                    return ""
                end if
            end tell
            """, label: "apple_music_track")

        guard let info = info, !info.isEmpty else {
            return ResolvedContext(contextType: .music)
        }

        let parts = info.components(separatedBy: "||")
        let song = parts[safe: 0].flatMap { $0.isEmpty ? nil : $0 }
        let artist = parts[safe: 1].flatMap { $0.isEmpty ? nil : $0 }
        let album = parts[safe: 2].flatMap { $0.isEmpty ? nil : $0 }

        // Apple Music doesn't expose artwork URL easily via AppleScript
        // We'll skip album art for now, future: MediaPlayer framework

        return ResolvedContext(
            contextType: .music,
            songName: song,
            artistName: artist,
            albumName: album
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
