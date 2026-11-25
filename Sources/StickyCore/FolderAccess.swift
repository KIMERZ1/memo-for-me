import Foundation

public enum FolderStatus: Equatable, Sendable { case ok, usingDefault, missing, permissionLost }
public enum FolderAccessError: Error { case unavailable(FolderStatus) }

/// The user-chosen notes folder, persisted as a security-scoped bookmark.
public final class FolderAccess {
    public static let bookmarkKey = "notesFolderBookmark"
    private let defaults: UserDefaults
    private let defaultFolder: URL
    private let fm = FileManager.default

    public init(defaults: UserDefaults, defaultFolder: URL) {
        self.defaults = defaults
        self.defaultFolder = defaultFolder
    }

    private var lastResolveFailedBecauseMissing = false

    private func resolve() -> URL? {
        lastResolveFailedBecauseMissing = false
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                defaults.set(fresh, forKey: Self.bookmarkKey)
            }
            return url
        } catch let e as CocoaError {
            // A bookmark to a deleted folder fails to resolve with "no such file".
            lastResolveFailedBecauseMissing = (e.code == .fileNoSuchFile || e.code == .fileReadNoSuchFile)
            return nil
        } catch { return nil }
    }

    public var currentFolder: URL {
        defaults.data(forKey: Self.bookmarkKey) == nil ? defaultFolder : (resolve() ?? defaultFolder)
    }

    public var status: FolderStatus {
        guard defaults.data(forKey: Self.bookmarkKey) != nil else { return .usingDefault }
        guard let url = resolve() else { return lastResolveFailedBecauseMissing ? .missing : .permissionLost }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? .ok : .missing
    }

    public func setFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope)
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    private var openURL: URL?

    /// Starts security-scoped access and keeps it until `closeFolder()`. Throws if unusable.
    public func openFolder() throws -> URL {
        closeFolder()
        if defaults.data(forKey: Self.bookmarkKey) == nil {
            try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
            return defaultFolder
        }
        let st = status
        guard st == .ok, let url = resolve() else { throw FolderAccessError.unavailable(st) }
        if url.startAccessingSecurityScopedResource() { openURL = url }
        return url
    }

    public func closeFolder() {
        openURL?.stopAccessingSecurityScopedResource()
        openURL = nil
    }

    /// Runs `body` with the notes folder open for access. Throws if the folder is unusable.
    public func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        if defaults.data(forKey: Self.bookmarkKey) == nil {
            try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
            return try body(defaultFolder)
        }
        let st = status
        guard st == .ok, let url = resolve() else { throw FolderAccessError.unavailable(st) }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
