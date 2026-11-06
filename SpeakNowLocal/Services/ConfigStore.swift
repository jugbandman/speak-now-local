import Foundation
import os

/// `~/.speaknow/config.json` is the source of truth for settings.
///
/// The app keeps using UserDefaults (and @AppStorage) internally, and this
/// store keeps the two in step:
/// - On launch, values in the file are applied to UserDefaults. With no file,
///   one is written from the current settings, so existing users migrate.
/// - When the file changes on disk (an edit by hand, by Claude, or by the
///   `speaknow` CLI) the new values are applied live, no restart.
/// - When a setting changes in the app, the file is rewritten. Keys the app
///   does not know are kept, so nothing a person adds is lost.
final class ConfigStore {
    static let shared = ConfigStore()

    enum Kind { case string, bool, stringArray }

    struct Field {
        let json: String        // key in config.json
        let defaultsKey: String // key in UserDefaults
        let kind: Kind
        let defaultValue: Any
    }

    static let fields: [Field] = [
        Field(json: "model", defaultsKey: Constants.keySelectedModel, kind: .string, defaultValue: Constants.defaultModel),
        Field(json: "whisperPath", defaultsKey: Constants.keyWhisperPath, kind: .string, defaultValue: Constants.defaultWhisperPath),
        Field(json: "warmEngine", defaultsKey: Constants.keyWarmEngine, kind: .bool, defaultValue: true),
        Field(json: "transcriptFolder", defaultsKey: Constants.keyOutputDirectory, kind: .string, defaultValue: Constants.defaultOutputDirectory),
        Field(json: "autoPaste", defaultsKey: Constants.keyAutoPaste, kind: .bool, defaultValue: false),
        Field(json: "sounds", defaultsKey: Constants.keySoundEffects, kind: .bool, defaultValue: true),
        Field(json: "captureMode", defaultsKey: Constants.keyCaptureMode, kind: .string, defaultValue: CaptureMode.micOnly.rawValue),
        Field(json: "inputDevice", defaultsKey: Constants.keyInputDeviceUID, kind: .string, defaultValue: ""),
        Field(json: "keepAudio", defaultsKey: Constants.keyRetainAudio, kind: .bool, defaultValue: false),
        Field(json: "theme", defaultsKey: Constants.keyTheme, kind: .string, defaultValue: Constants.defaultTheme),
        Field(json: "menuBarIcon", defaultsKey: Constants.keyMenuBarIcon, kind: .string, defaultValue: Constants.defaultMenuBarIcon),
        Field(json: "ollamaModel", defaultsKey: Constants.keyOllamaModel, kind: .string, defaultValue: ""),
        Field(json: "promptTarget", defaultsKey: Constants.keyPromptTarget, kind: .string, defaultValue: "claude-opus"),
        Field(json: "promptAsk", defaultsKey: Constants.keyPromptAsk, kind: .string, defaultValue: "general"),
        Field(json: "vaultInbox", defaultsKey: Constants.keyVaultInbox, kind: .string, defaultValue: ""),
        Field(json: "terminalApp", defaultsKey: Constants.keyTerminalApp, kind: .string, defaultValue: "auto"),
        Field(json: "claudeFolders", defaultsKey: Constants.keyClaudeFolders, kind: .stringArray, defaultValue: [String]()),
        Field(json: "ideaBoard", defaultsKey: Constants.keyIdeaBoard, kind: .bool, defaultValue: true),
    ]

    var fileURL: URL { TemplateStore.rootURL.appendingPathComponent("config.json") }

    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.speaknow.local", category: "ConfigStore")
    private var pollTimer: Timer?
    private var lastSeenModified: Date?
    private var pendingWrite: DispatchWorkItem?
    private var isApplying = false

    func start() {
        TemplateStore.ensureSeeded()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            applyFileToDefaults()
        } else {
            writeFile()
        }
        lastSeenModified = modifiedDate()

        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil)

        // A cheap stat every two seconds catches every kind of edit, in place or
        // an editor's save-by-rename, which a file descriptor watch can miss.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForFileChange()
        }
    }

    // MARK: - Reading values (for code outside SwiftUI)

    private func field(_ key: String) -> Field? {
        Self.fields.first(where: { $0.defaultsKey == key })
    }

    func string(_ key: String) -> String {
        if let s = defaults.string(forKey: key) { return s }
        return (field(key)?.defaultValue as? String) ?? ""
    }

    func bool(_ key: String) -> Bool {
        if defaults.object(forKey: key) == nil {
            return (field(key)?.defaultValue as? Bool) ?? false
        }
        return defaults.bool(forKey: key)
    }

    func stringArray(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    // MARK: - File to defaults

    private func checkForFileChange() {
        let modified = modifiedDate()
        guard modified != lastSeenModified else { return }
        lastSeenModified = modified
        applyFileToDefaults()
    }

    private func modifiedDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    private func readFile() -> [String: Any]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("config.json is not valid JSON, ignoring it until it is fixed")
            return nil
        }
        return obj
    }

    private func applyFileToDefaults() {
        guard let json = readFile() else { return }
        isApplying = true
        defer { isApplying = false }
        for field in Self.fields {
            guard let value = json[field.json] else { continue }
            switch field.kind {
            case .string:
                if let s = value as? String, defaults.string(forKey: field.defaultsKey) != s {
                    defaults.set(s, forKey: field.defaultsKey)
                }
            case .bool:
                if let b = value as? Bool,
                   defaults.object(forKey: field.defaultsKey) == nil || defaults.bool(forKey: field.defaultsKey) != b {
                    defaults.set(b, forKey: field.defaultsKey)
                }
            case .stringArray:
                if let a = value as? [String], defaults.stringArray(forKey: field.defaultsKey) != a {
                    defaults.set(a, forKey: field.defaultsKey)
                }
            }
        }
    }

    // MARK: - Defaults to file

    @objc private func defaultsChanged() {
        // UserDefaults can post from any thread. Keep all state on main.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.defaultsChanged() }
            return
        }
        guard !isApplying else { return }
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeFileIfChanged() }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func currentValues() -> [String: Any] {
        var values: [String: Any] = [:]
        for field in Self.fields {
            switch field.kind {
            case .string:
                if let s = defaults.string(forKey: field.defaultsKey) {
                    values[field.json] = s
                } else {
                    values[field.json] = field.defaultValue
                }
            case .bool:
                if defaults.object(forKey: field.defaultsKey) == nil {
                    values[field.json] = field.defaultValue
                } else {
                    values[field.json] = defaults.bool(forKey: field.defaultsKey)
                }
            case .stringArray:
                if let a = defaults.stringArray(forKey: field.defaultsKey) {
                    values[field.json] = a
                } else {
                    values[field.json] = field.defaultValue
                }
            }
        }
        return values
    }

    private func writeFileIfChanged() {
        let existing = readFile() ?? [:]
        var merged = existing
        for (k, v) in currentValues() { merged[k] = v }
        guard !NSDictionary(dictionary: existing).isEqual(to: merged) else { return }
        write(merged)
    }

    private func writeFile() {
        var merged = readFile() ?? [:]
        for (k, v) in currentValues() { merged[k] = v }
        write(merged)
    }

    private func write(_ dict: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            lastSeenModified = modifiedDate()
        } catch {
            logger.warning("Could not write config.json: \(error.localizedDescription)")
        }
    }
}
