import Foundation

enum FileCopyUtilities {
    static func cloneOrCopyFile(from sourceURL: URL, to destinationURL: URL, allowLinking: Bool = true) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        if allowLinking, isSameVolume(sourceURL, destinationURL) {
            do {
                try fileManager.linkItem(at: sourceURL, to: destinationURL)
                return
            } catch {
                // Hard link can fail across volumes or unsupported file systems; fall back to copy.
            }
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func isSameVolume(_ sourceURL: URL, _ destinationURL: URL) -> Bool {
        let sourceVolume = volumeIdentifier(for: sourceURL)
        let destinationVolume = volumeIdentifier(for: destinationURL.deletingLastPathComponent())
        return sourceVolume != nil && sourceVolume == destinationVolume
    }

    private static func volumeIdentifier(for url: URL) -> AnyHashable? {
        let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier as? AnyHashable
    }
}
