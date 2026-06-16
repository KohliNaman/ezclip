import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("ezclip.hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("ezclip.showNotifications") private var showNotifications = true
    @AppStorage("ezclip.autoLaunch") private var autoLaunch = false
    @AppStorage("ezclip.ai.provider") private var aiProvider = AITaggingProviderKind.off.rawValue
    @AppStorage("ezclip.ai.autoTagNewCaptures") private var autoTagNewCaptures = false
    @AppStorage("ezclip.ai.bypassRateLimit") private var bypassAIRateLimit = false
    @AppStorage("ezclip.ai.maxTagsPerRun") private var maxTagsPerRun = 12
    @AppStorage("ezclip.ai.delayBetweenRequests") private var delayBetweenRequests = 8.0
    @AppStorage("ezclip.ai.geminiModel") private var geminiModel = "gemini-3.1-flash-lite"
    @State private var permissionsOK = false
    @State private var geminiAPIKey = ""
    @State private var isBackfillingAITags = false
    @State private var aiBackfillMessage: String?
    @State private var appleLocalAvailability = AppleFoundationTaggingProvider.availability()

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

            aiTab
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 390)
        .task {
            checkPermissions()
            geminiAPIKey = KeychainStore.string(for: "geminiAPIKey")
                ?? UserDefaults.standard.string(forKey: "ezclip.ai.geminiAPIKey")
                ?? ""
            refreshAppleLocalAvailability()
        }
    }

    // MARK: - AI

    private var aiTab: some View {
        Form {
            Section("Provider") {
                Picker("AI tagging", selection: $aiProvider) {
                    ForEach(AITaggingProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Auto-tag new captures", isOn: $autoTagNewCaptures)
                    .disabled(aiProvider == AITaggingProviderKind.off.rawValue)
            }

            if aiProvider == AITaggingProviderKind.gemini.rawValue {
                Section("Gemini") {
                    SecureField("API key", text: $geminiAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: geminiAPIKey) { _, newValue in
                            KeychainStore.setString(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "geminiAPIKey")
                            UserDefaults.standard.removeObject(forKey: "ezclip.ai.geminiAPIKey")
                        }
                    TextField("Model", text: $geminiModel)
                        .textFieldStyle(.roundedBorder)
                    Text("Default: gemini-3.1-flash-lite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if aiProvider == AITaggingProviderKind.appleLocal.rawValue {
                Section("Apple Local") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appleLocalAvailabilityColor)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(appleLocalAvailabilityLabel)
                        Text(appleLocalAvailabilityLabel)
                        Spacer()
                        Button {
                            refreshAppleLocalAvailability()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Apple Local availability")
                    }

                    Text(appleLocalAvailability.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("This local path currently uses capture metadata/design context. Gemini is still required for full screenshot vision tagging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Battery") {
                Toggle("Bypass AI rate limit", isOn: $bypassAIRateLimit)

                Stepper("Max per run: \(maxTagsPerRun)", value: $maxTagsPerRun, in: 1...200)
                    .disabled(bypassAIRateLimit)

                Stepper("Delay: \(Int(delayBetweenRequests))s", value: $delayBetweenRequests, in: 0...60, step: 1)
                    .disabled(bypassAIRateLimit)
            }

            Section("Existing Captures") {
                Button {
                    backfillExistingCaptures()
                } label: {
                    if isBackfillingAITags {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.65)
                            Text("Tagging Previous Captures")
                        }
                    } else {
                        Label("AI Tag Previous Captures", systemImage: "clock.arrow.circlepath")
                    }
                }
                .disabled(isBackfillingAITags || aiProvider == AITaggingProviderKind.off.rawValue)

                if let aiBackfillMessage {
                    Text(aiBackfillMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(10)
        .onChange(of: aiProvider) { _, newValue in
            if newValue == AITaggingProviderKind.appleLocal.rawValue {
                refreshAppleLocalAvailability()
            }
        }
    }

    private var appleLocalAvailabilityColor: Color {
        switch appleLocalAvailability.state {
        case .available: .green
        case .unavailable: .red
        case .unknown: .yellow
        }
    }

    private var appleLocalAvailabilityLabel: String {
        switch appleLocalAvailability.state {
        case .available: "Available on this Mac"
        case .unavailable: "Unavailable on this Mac"
        case .unknown: "Availability unknown"
        }
    }

    private func refreshAppleLocalAvailability() {
        appleLocalAvailability = AppleFoundationTaggingProvider.availability()
    }

    private func backfillExistingCaptures() {
        isBackfillingAITags = true
        aiBackfillMessage = nil
        Task {
            do {
                let limit = bypassAIRateLimit ? nil : maxTagsPerRun
                let captures = try await DatabaseManager.shared.capturesNeedingAITags(limit: limit)
                await AITaggingService.shared.generateTags(for: captures, isUserInitiated: true)
                aiBackfillMessage = captures.isEmpty
                    ? "No previous captures need AI tags."
                    : "Queued \(captures.count) previous captures."
            } catch {
                aiBackfillMessage = error.localizedDescription
            }
            isBackfillingAITags = false
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Enable hotkey (⌘⌘)", isOn: $hotkeyEnabled)
                    .onChange(of: hotkeyEnabled) { _, enabled in
                        if enabled {
                            _ = HotkeyManager.shared.register {
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
