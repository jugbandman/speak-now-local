import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var micGranted = AudioRecorder.hasPermission
    @State private var accessibilityGranted = AccessibilityChecker.isTrusted()
    @AppStorage(Constants.keySelectedModel) private var selectedModel = Constants.defaultModel

    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<5) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                permissionsStep.tag(1)
                howItWorksStep.tag(2)
                voiceModesStep.tag(3)
                modelStep.tag(4)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 480, height: 440)
        .onReceive(permissionTimer) { _ in
            micGranted = AudioRecorder.hasPermission
            accessibilityGranted = AccessibilityChecker.isTrusted()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🫶")
                .font(.system(size: 64))

            Text("Speak Now Local")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .italic()

            Text("Voice to text, fully local. No cloud, no subscription, no data leaves your Mac.")
                .font(.system(.body, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Set your recording hotkey")
                    .font(.system(.headline, design: .serif))
                KeyboardShortcuts.Recorder(for: .toggleRecording)
            }
            .padding(.top, 8)

            Text("This hotkey toggles recording from anywhere. You can also hold the right Option key for push-to-talk, or double-tap it for hands-free mode.")
                .font(.system(.caption, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            Button("Next") { currentStep = 1 }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Permissions")
                .font(.system(.title, design: .serif))
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to record your voice",
                    isGranted: micGranted,
                    action: {
                        Task {
                            let granted = await AudioRecorder.requestPermission()
                            await MainActor.run { micGranted = granted }
                        }
                    }
                )

                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility (Optional)",
                    description: "Enables auto-paste into active text fields",
                    isGranted: accessibilityGranted,
                    action: {
                        AccessibilityChecker.requestAccess()
                    }
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            Button("Next") { currentStep = 2 }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var howItWorksStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("How It Works")
                .font(.system(.title, design: .serif))
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 14) {
                OnboardingFlowRow(icon: "mic.fill", number: 1,
                    text: "Trigger recording with your hotkey, Option key, or a click")
                OnboardingFlowRow(icon: "circle.circle", number: 2,
                    text: "A floating mic appears on your desktop")
                OnboardingFlowRow(icon: "waveform", number: 3,
                    text: "Speak naturally, the mic vibrates with your voice")
                OnboardingFlowRow(icon: "stop.fill", number: 4,
                    text: "Stop recording to transcribe")
                OnboardingFlowRow(icon: "doc.on.clipboard", number: 5,
                    text: "Text is copied to your clipboard automatically")
            }
            .padding(.horizontal, 36)

            Text("You can also type quick notes in the menu bar for instant capture.")
                .font(.system(.caption, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            Button("Next") { currentStep = 3 }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var voiceModesStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Voice Modes")
                .font(.system(.title, design: .serif))
                .fontWeight(.semibold)

            Text("Start your recording with a keyword to tell the app what kind of content you're capturing.")
                .font(.system(.caption, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 36)

            VStack(alignment: .leading, spacing: 8) {
                VoiceModeRow(name: "Dump", color: .brown,
                    description: "Brain dump. Say everything, AI captures all of it. This is the default.")
                VoiceModeRow(name: "Task", color: .green,
                    description: "Quick task or action item")
                VoiceModeRow(name: "Idea", color: .purple,
                    description: "An idea worth keeping")
                VoiceModeRow(name: "Email", color: .blue,
                    description: "Draft an email from your voice")
                VoiceModeRow(name: "Text", color: .cyan,
                    description: "Compose a text message")
                VoiceModeRow(name: "Code", color: .orange,
                    description: "Technical instruction or spec")
                VoiceModeRow(name: "Note", color: .indigo,
                    description: "A note or reflection")
            }
            .padding(.horizontal, 36)

            VStack(spacing: 4) {
                Text("No keyword? Everything defaults to Dump mode, so nothing gets lost.")
                    .font(.system(.caption, design: .serif))
                    .foregroundColor(.secondary)
                Text("You can also pick a mode from the toolbar before recording.")
                    .font(.system(.caption, design: .serif))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)

            Spacer()

            Button("Next") { currentStep = 4 }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 20)
        }
        .padding()
    }

    private var modelStep: some View {
        VStack(spacing: 16) {
            ModelPickerView(
                selectedModel: $selectedModel,
                modelManager: appState.modelManager,
                onComplete: {
                    appState.hasCompletedOnboarding = true
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
    }
}

struct OnboardingFlowRow: View {
    let icon: String
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(.system(size: 13, design: .serif))
        }
    }
}

struct VoiceModeRow: View {
    let name: String
    let color: Color
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 6, height: 20)
            Text(name)
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .frame(width: 44, alignment: .leading)
            Text(description)
                .font(.system(.caption, design: .serif))
                .foregroundColor(.secondary)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") { action() }
                    .font(.caption)
            }
        }
    }
}
