import Foundation

/// Minimal stub: Pill doesn't use KeyboardShortcuts, but SettingsManager.AppSettings
/// references this type for persistence compatibility with FineTune's settings.json.
struct ShortcutCodable: Codable, Equatable, Hashable, Sendable {
    var keyCode: Int
    var modifiers: UInt

    init(keyCode: Int, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
