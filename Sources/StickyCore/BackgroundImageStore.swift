import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum BackgroundImageError: Error { case notAnImage, writeFailed }

/// Copies user-chosen background images into app storage (long side ≤ 1200px).
public final class BackgroundImageStore {
    public static let maxLongSide = 1200
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// Returns the stored file name.
    public func importImage(from source: URL) throws -> String {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(src) > 0
        else { throw BackgroundImageError.notAnImage }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxLongSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { throw BackgroundImageError.notAnImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).png"
        guard let dest = CGImageDestinationCreateWithURL(url(for: name) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw BackgroundImageError.writeFailed }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw BackgroundImageError.writeFailed }
        return name
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    public func remove(_ name: String) { try? FileManager.default.removeItem(at: url(for: name)) }
}
