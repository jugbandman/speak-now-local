import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @AppStorage(Constants.keySelectedModel) private var selectedModel = Constants.defaultModel

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 16)

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                permissionsStep.tag(1)
                modelStep.tag(2)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 440, height: 400)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Speak Now Local")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Press a hotkey, speak, and get a transcription in your clipboard. Fully local, no cloud, no subscription.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Set your recording hotkey")
                    .font(.headline)
                KeyboardShortcuts.Recorder(for: .toggleRecording)
            }
            .padding(.top, 8)

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
                .font(.title)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required to record your voice",
                    isGranted: AudioRecorder.hasPermission,
                    action: {
                        Task { _ = await AudioRecorder.requestPermission() }
                    }
                )

                PermissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility (Optional)",
                    description: "Enables auto-paste into active text fields",
                    isGranted: AccessibilityChecker.isTrusted(),
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
