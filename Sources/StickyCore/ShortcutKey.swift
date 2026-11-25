import Foundation

/// Maps a physical key (ANSI key code) to the Latin letter printed on it.
/// Shortcuts must not depend on the active input source: with a Korean keyboard,
/// Cmd+C reports "ㅊ" as its character, so matching on characters misses every shortcut.
public enum ShortcutKey {
    private static let names: [UInt16: String] = [
        0: "a", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 13: "w",
        32: "u", 34: "i", 45: "n", 24: "=", 27: "-",
    ]

    public static func name(forKeyCode code: UInt16) -> String? { names[code] }
}
