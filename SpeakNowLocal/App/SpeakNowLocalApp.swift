import SwiftUI
import KeyboardShortcuts

@main
struct SpeakNowLocalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .environmentObject(appState)
            } else {
                MenuBarView()
                    .environmentObject(appState)
            }
        } label: {
            StatusIcon(state: appState.recordingState)
        }
        .menuBarExtraStyle(.window)
    }
}
