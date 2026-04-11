import SwiftUI
import VoiceDoShared

struct SettingsView: View {

    @State private var apiKeyInput: String = ""
    @State private var hasStoredKey: Bool = false
    @State private var aiEnabled: Bool = true
    @State private var showAPIKeyField: Bool = false
    @State private var keySaved: Bool = false
    @State private var alertError: VoiceDoError?
    @State private var notificationStatus: String = "Checking…"

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // AI Section
                    settingsSection(label: "Claude AI") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("AI Refinement")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.vdInk)
                                Spacer()
                                Toggle("", isOn: $aiEnabled)
                                    .labelsHidden()
                                    .tint(Color.vdInk)
                                    .onChange(of: aiEnabled) { _, enabled in
                                        UserDefaults.standard.set(enabled, forKey: "voicedo.aiEnabled")
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)

                            if hasStoredKey {
                                HStack {
                                    Text("API Key")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdInk)
                                    Spacer()
                                    Text("Configured")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.vdMuted)
                                    Button("Remove") { removeAPIKey() }
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(white: 0.35))
                                        .padding(.leading, 8)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            } else {
                                Button {
                                    withAnimation { showAPIKeyField.toggle() }
                                } label: {
                                    HStack {
                                        Text("Add API Key")
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.vdInk)
                                        Spacer()
                                        Image(systemName: showAPIKeyField ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.vdMuted)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                if showAPIKeyField {
                                    Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)
                                    VStack(alignment: .leading, spacing: 10) {
                                        SecureField("sk-ant-…", text: $apiKeyInput)
                                            .textContentType(.password)
                                            .autocorrectionDisabled()
                                            .font(.system(size: 15, design: .monospaced))
                                            .accessibilityLabel("Claude API key")

                                        if keySaved {
                                            Text("Saved")
                                                .font(.caption)
                                                .foregroundStyle(Color.vdMuted)
                                        } else {
                                            Button("Save Key") { saveAPIKey() }
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(Color.vdInk)
                                                .disabled(apiKeyInput.count < 10)
                                                .opacity(apiKeyInput.count < 10 ? 0.4 : 1)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                            }
                        }
                        .vdCard()

                        Text(
                            "Your API key is stored securely in the iOS Keychain " +
                            "and never leaves your device."
                        )
                        .font(.caption)
                        .foregroundStyle(Color.vdMuted)
                        .padding(.horizontal, 4)
                    }

                    // Notifications Section
                    settingsSection(label: "Notifications") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Status")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.vdInk)
                                Spacer()
                                Text(notificationStatus)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.vdMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider().padding(.leading, 16).foregroundStyle(Color.vdBorder)

                            Button {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Text("Open Settings")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color.vdInk)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.vdMuted)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .vdCard()
                    }

                    // About Section
                    settingsSection(label: "About") {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.vdInk)
                                Spacer()
                                Text(appVersion)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.vdMuted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .vdCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert(error: $alertError)
        .task {
            loadInitialState()
            await checkNotificationStatus()
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func settingsSection<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.vdMuted)
                .kerning(0.8)
            content()
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func loadInitialState() {
        hasStoredKey = APIKeyManager.hasKey()
        aiEnabled = UserDefaults.standard.bool(forKey: "voicedo.aiEnabled")
    }

    private func saveAPIKey() {
        do {
            try APIKeyManager.save(apiKeyInput)
            apiKeyInput = ""
            hasStoredKey = true
            showAPIKeyField = false
            keySaved = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                keySaved = false
            }
        } catch {
            alertError = .generic("Failed to save API key: \(error.localizedDescription)")
        }
    }

    private func removeAPIKey() {
        do {
            try APIKeyManager.delete()
            hasStoredKey = false
        } catch {
            alertError = .generic("Failed to remove API key: \(error.localizedDescription)")
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: notificationStatus = "Enabled"
        case .denied: notificationStatus = "Disabled"
        case .notDetermined: notificationStatus = "Not requested"
        case .provisional: notificationStatus = "Provisional"
        case .ephemeral: notificationStatus = "Ephemeral"
        @unknown default: notificationStatus = "Unknown"
        }
    }
}
