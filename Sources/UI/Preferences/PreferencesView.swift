import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("ezclip.hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("ezclip.showNotifications") private var showNotifications = true
    @AppStorage("ezclip.autoLaunch") private var autoLaunch = false
    @State private var permissionsOK = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "hand.raised")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 350)
        .task {
            checkPermissions()
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Enable hotkey (⌘⌘)", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, enabled in
                        if enabled {
                            HotkeyManager.shared.register {
                                Task { await CaptureOrchestrator.shared.capture() }
                            }
                        } else {
                            HotkeyManager.shared.unregister()
                        }
                    }

                Text("Double-press the left Command key to capture the frontmost window.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                Toggle("Show capture notifications", isOn: $showNotifications)

                Toggle("Launch ezclip at login", isOn: $autoLaunch)
                    .onChange(of: autoLaunch) { _, launch in
                        if launch {
                            addLoginItem()
                        } else {
                            removeLoginItem()
                        }
                    }
            }

            Section("Updates") {
                UpdaterSettingsView()
            }

            Section("Storage") {
                HStack {
                    Text("Location")
                    Spacer()
                    Text("~/Library/Application Support/ezclip/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .truncationMode(.middle)
                }

                Button("Open in Finder") {
                    let url = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    ).first!.appendingPathComponent("ezclip")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }

    // MARK: - Permissions

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ezclip needs two permissions to work:")
                .font(.body)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Screen Recording",
                    description: "To capture screenshots of your windows.",
                    icon: "rectangle.on.rectangle",
                    isGranted: permissionsOK
                )
                .onTapGesture {
                    openPermissionPane("Privacy_ScreenCapture")
                }

                PermissionRow(
                    title: "Accessibility",
                    description: "To read window titles and detect the double-Command hotkey.",
                    icon: "accessibility",
                    isGranted: permissionsOK
                )
                .onTapGesture {
                    openPermissionPane("Privacy_Accessibility")
                }
            }

            Text("You'll be prompted when you first use ezclip. Or manage them here:")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue, .secondary)

            Text("ezclip")
                .font(.title)
                .fontWeight(.bold)

            Text("Context-aware screenshot curation for designers.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Version \(appVersion) (Build \(appBuild))")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .padding(.vertical, 8)

            UpdaterSettingsView()

            HStack(spacing: 4) {
                Text("Double-tap")
                Text("⌘⌘")
                    .font(.system(.body, design: .monospaced))
                Text("in any app to capture.")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Permission helpers

    private func checkPermissions() {
        // Check if we can actually capture
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        let hasAccessibility = AXIsProcessTrusted()

        permissionsOK = hasScreenRecording && hasAccessibility
    }

    private func openPermissionPane(_ pane: String) {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        )
    }

    // MARK: - Login item

    private func addLoginItem() {
        // Simplified — in production use SMAppService
        print("Login item registration requested")
    }

    private func removeLoginItem() {
        print("Login item removal requested")
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundColor(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isGranted ? .green : .red)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}

// MARK: - Updater Settings

struct UpdaterSettingsView: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var showInstallPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Current version:")
                Text("\(updater.currentVersion) (build \(updater.currentBuild))")
                    .foregroundColor(.secondary)
            }
            .font(.callout)

            if updater.updateAvailable, let version = updater.remoteVersion {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Version \(version) available")
                        .fontWeight(.medium)
                }

                if let notes = updater.remoteNotes {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                Button("Install Update...") {
                    showInstallPrompt = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if updater.isChecking {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking for updates...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("Check for Updates") {
                    Task { await updater.checkForUpdates() }
                }
                .disabled(updater.isChecking)
            }

            if let error = updater.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            #if DEBUG
            Text("Updates are disabled in debug builds.")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
        }
        .alert("Install Update?", isPresented: $showInstallPrompt) {
            Button("Install & Restart") {
                Task { await updater.downloadAndInstall() }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("ezclip will download the new version, replace the current app, and restart. This takes a few seconds.")
        }
    }
}
