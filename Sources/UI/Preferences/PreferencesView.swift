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
    @AppStorage("ezclip.libraryAppearance") private var libraryAppearance = LibraryAppearanceMode.studio.rawValue
    @AppStorage("ezclip.ai.allowCloudVision") private var allowCloudVision = false
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

            browserExtensionsTab
                .tabItem {
                    Label("Browsers", systemImage: "puzzlepiece.extension")
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

    // MARK: - Browser Extensions

    private var browserExtensionsTab: some View {
        BrowserExtensionsSettingsView()
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
                    Toggle("Allow screenshot uploads", isOn: $allowCloudVision)
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
                Picker("Library appearance", selection: $libraryAppearance) {
                    ForEach(LibraryAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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

private struct BrowserExtensionsSettingsView: View {
    @State private var health: [BrowserExtensionHealth] = BrowserExtensionDiagnostics.allHealth()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Browser Design Context")
                    .font(.headline)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh browser extension status")
                Button {
                    copyDiagnostics()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy diagnostics")
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(health) { item in
                        BrowserHealthRow(health: item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        health = BrowserExtensionDiagnostics.allHealth()
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BrowserExtensionDiagnostics.diagnosticsText(), forType: .string)
    }
}

private struct BrowserHealthRow: View {
    let health: BrowserExtensionHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(health.target.displayName)
                    .font(.body.weight(.semibold))
                Text(health.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    revealExtensionFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Show extension folder")
            }

            Text(health.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                BrowserHealthPill(label: "Host", isOK: health.nativeHostInstalled)
                BrowserHealthPill(label: "Bridge", isOK: health.bridgePathValid)
                BrowserHealthPill(label: "Extension", isOK: health.extensionInstalled)
                if let lastPayloadAt = health.lastPayloadAt {
                    Text(lastPayloadAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("No payload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastPayloadURL = health.lastPayloadURL {
                Text(lastPayloadURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let lastPayloadCounts = health.lastPayloadCounts {
                Text(lastPayloadCounts)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusColor: Color {
        switch health.status {
        case .enriched: .green
        case .extensionMissing, .nativeHostMissing, .transportFailed: .red
        case .stalePayload, .urlMismatch, .emptyPayload, .restrictedPage: .yellow
        }
    }

    private func revealExtensionFolder() {
        let folder = health.target.browserFamily == "chromium"
            ? "BrowserExtensions/chromium"
            : "BrowserExtensions/firefox"
        let url = URL(fileURLWithPath: "/Users/namanlol/Development/ezclip").appendingPathComponent(folder)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct BrowserHealthPill: View {
    let label: String
    let isOK: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(isOK ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.06))
        .clipShape(Capsule())
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
