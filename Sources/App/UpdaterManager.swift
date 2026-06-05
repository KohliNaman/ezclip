import Combine
import Sparkle

/// Thin wrapper around Sparkle's SPUStandardUpdaterController.
/// Manages update checking lifecycle and exposes bindable state for Settings UI.
///
/// Updates are disabled in DEBUG builds so you don't get prompted
/// during development.
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    @Published private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        // startingUpdater: false — we start explicitly after the app is ready
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Call once in applicationDidFinishLaunching. No-op in DEBUG builds.
    func start() {
        #if DEBUG
        print("⚠️ Sparkle: update checking disabled in DEBUG builds")
        return
        #endif

        controller.startUpdater()
        canCheckForUpdates = true

        // Mirror Sparkle's KVO-driven state into our @Published
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)

        print("✅ Sparkle updater started")
    }

    /// Opens the standard Sparkle update window. No-op in DEBUG.
    func checkForUpdates() {
        #if DEBUG
        print("⚠️ Sparkle: checkForUpdates ignored in DEBUG")
        return
        #endif

        controller.checkForUpdates(nil)
    }
}
