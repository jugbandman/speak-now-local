import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.command, .shift]))
    /// Opens or closes the Prompt window. No default, set it in Settings.
    static let openPrompt = Self("openPrompt")
}
