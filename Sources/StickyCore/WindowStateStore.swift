import Foundation
import CoreGraphics

public enum NoteColor: String, Codable, Sendable { case yellow, blue }

/// Per-note window state. Holds no note text.
public struct NoteWindowState: Codable, Equatable, Sendable {
    public var noteID: UUID
    public var isSecure: Bool
    public var frame: CGRect
    public var colorName: NoteColor
    public var backgroundImageFile: String?
    public var isPinnedHere: Bool
    public var floatsOnTop: Bool
    /// false = window closed with ⌘W; the note still exists and is listed in the menu.
    public var isOpen: Bool

    public init(noteID: UUID, isSecure: Bool, frame: CGRect, colorName: NoteColor,
                backgroundImageFile: String?, isPinnedHere: Bool, floatsOnTop: Bool, isOpen: Bool = true) {
        self.isOpen = isOpen
        self.noteID = noteID; self.isSecure = isSecure; self.frame = frame; self.colorName = colorName
        self.backgroundImageFile = backgroundImageFile; self.isPinnedHere = isPinnedHere
        self.floatsOnTop = floatsOnTop
    }
}

extension NoteWindowState {
    enum CodingKeys: String, CodingKey {
        case noteID, isSecure, frame, colorName, backgroundImageFile, isPinnedHere, floatsOnTop, isOpen
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(noteID: try c.decode(UUID.self, forKey: .noteID),
                  isSecure: try c.decode(Bool.self, forKey: .isSecure),
                  frame: try c.decode(CGRect.self, forKey: .frame),
                  colorName: try c.decode(NoteColor.self, forKey: .colorName),
                  backgroundImageFile: try c.decodeIfPresent(String.self, forKey: .backgroundImageFile),
                  isPinnedHere: try c.decode(Bool.self, forKey: .isPinnedHere),
                  floatsOnTop: try c.decode(Bool.self, forKey: .floatsOnTop),
                  isOpen: try c.decodeIfPresent(Bool.self, forKey: .isOpen) ?? true)
    }
}

public final class WindowStateStore {
    private let fileURL: URL
    private var states: [UUID: NoteWindowState] = [:]
    private var order: [UUID] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public func all() -> [NoteWindowState] { order.compactMap { states[$0] } }

    public func update(_ s: NoteWindowState) {
        if states[s.noteID] == nil { order.append(s.noteID) }
        states[s.noteID] = s
        flush()
    }

    public func remove(noteID: UUID) {
        states[noteID] = nil
        order.removeAll { $0 == noteID }
        flush()
    }

    public func flush() {
        guard let data = try? JSONEncoder().encode(all()) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let list = try? JSONDecoder().decode([NoteWindowState].self, from: data) {
            for s in list { states[s.noteID] = s; order.append(s.noteID) }
        } else {
            let bak = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: bak)
            try? FileManager.default.moveItem(at: fileURL, to: bak)
        }
    }
}
