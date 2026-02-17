import AppKit

class SoundEffects {
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Constants.keySoundEffects) as? Bool ?? true
    }

    func playStartSound() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    func playStopSound() {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    func playCompleteSound() {
        guard isEnabled else { return }
        NSSound(named: "Glass")?.play()
    }
}
