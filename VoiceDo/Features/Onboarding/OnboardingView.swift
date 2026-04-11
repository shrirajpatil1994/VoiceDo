import AVFoundation
import Speech
import SwiftUI
import UserNotifications

/// Three-step onboarding: mic → speech → notifications → done.
/// Shown only on first launch, controlled by AppStorage.
struct OnboardingView: View {

    @AppStorage("voicedo.hasCompletedOnboarding") private var hasCompleted = false
    @State private var currentStep = 0
    @State private var micGranted = false
    @State private var speechGranted = false
    @State private var notifGranted = false

    private let steps = ["Microphone", "Speech", "Notifications", "Ready"]

    var body: some View {
        ZStack {
            Color.vdBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step dots
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index <= currentStep ? Color.vdInk : Color.vdBorder)
                            .frame(width: index == currentStep ? 24 : 6, height: 6)
                            .animation(.spring(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.top, 52)

                Spacer()

                // Step content
                Group {
                    switch currentStep {
                    case 0: stepView(
                        icon: "mic",
                        title: "Microphone Access",
                        description: "VoiceDo needs your microphone to capture voice notes. " +
                            "Your audio is processed on-device."
                    )
                    case 1: stepView(
                        icon: "waveform",
                        title: "Speech Recognition",
                        description: "We use Apple's on-device speech recognition. " +
                            "This works offline and keeps your data private."
                    )
                    case 2: stepView(
                        icon: "bell",
                        title: "Notifications",
                        description: "VoiceDo notifies you when a reminder is due. " +
                            "You can always adjust this in Settings."
                    )
                    default: doneView
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: currentStep)

                Spacer()

                // CTA
                if currentStep < 3 {
                    VStack(spacing: 12) {
                        Button {
                            Task { await handleStepAction() }
                        } label: {
                            Text(ctaLabel)
                                .vdPrimaryButton()
                        }
                        .padding(.horizontal, 28)

                        Button("Skip") { currentStep += 1 }
                            .font(.subheadline)
                            .foregroundStyle(Color.vdMuted)
                    }
                    .padding(.bottom, 48)
                }
            }
        }
    }

    // MARK: - Step View

    @ViewBuilder
    private func stepView(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.vdCard)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.vdBorder, lineWidth: 0.5))
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.vdInk)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.vdInk)
                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.vdMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 36)
        }
    }

    // MARK: - Done View

    private var doneView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.vdInk)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text("You're all set")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.vdInk)
                Text(
                    "Add VoiceDo to your homescreen and tap " +
                    "the mic button to capture your first task."
                )
                .font(.system(size: 15))
                .foregroundStyle(Color.vdMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)
            }

            Button {
                hasCompleted = true
            } label: {
                Text("Start Using VoiceDo")
                    .vdPrimaryButton()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
        }
    }

    // MARK: - CTA Label

    private var ctaLabel: String {
        switch currentStep {
        case 0: return micGranted ? "Continue" : "Allow Microphone"
        case 1: return speechGranted ? "Continue" : "Allow Speech Recognition"
        case 2: return notifGranted ? "Continue" : "Allow Notifications"
        default: return "Continue"
        }
    }

    // MARK: - Actions

    private func handleStepAction() async {
        switch currentStep {
        case 0:
            micGranted = await AVAudioApplication.requestRecordPermission()
            currentStep = 1
        case 1:
            let status = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            speechGranted = (status == .authorized)
            currentStep = 2
        case 2:
            notifGranted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            currentStep = 3
        default:
            break
        }
    }
}

// MARK: - StepView (kept for backwards compat)

struct StepView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.vdInk)
            Text(title).font(.title.bold()).foregroundStyle(Color.vdInk)
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.vdMuted)
                .padding(.horizontal, 32)
        }
    }
}
