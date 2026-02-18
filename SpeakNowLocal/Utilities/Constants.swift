import Foundation

enum Constants {
    static let defaultWhisperPath = "/opt/homebrew/bin/whisper-cli"
    static let whisperModelsDirectory = "\(NSHomeDirectory())/.cache/whisper"
    static let defaultModel = "medium"
    static let defaultThreads = 4

    static var defaultOutputDirectory: String {
        "\(NSHomeDirectory())/Documents/SpeakNowLocal/Transcripts"
    }

    static var tempRecordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("speak-now-recording.wav")
    }

    // UserDefaults keys
    static let keyWhisperPath = "whisperCliPath"
    static let keyOutputDirectory = "outputDirectory"
    static let keySelectedModel = "selectedModel"
    static let keyAutoPaste = "autoPasteEnabled"
    static let keySoundEffects = "soundEffectsEnabled"
    static let keyHasCompletedOnboarding = "hasCompletedOnboarding"
    static let keyMenuBarIcon = "menuBarIcon"
    static let defaultMenuBarIcon = "sparkles"
    static let keyTheme = "appTheme"
    static let defaultTheme = "taylors"
}
