import Foundation

struct AudioFileCandidate: Sendable {
    let id: UUID
    let url: URL
}

enum AudioFileInspection: Sendable {
    case present(size: Int64)
    case missing
    case failed(message: String)
}

struct AudioFileInspectionResult: Sendable {
    let candidate: AudioFileCandidate
    let inspection: AudioFileInspection
}

enum AudioFileDeletion: Sendable {
    case deleted
    case missing
    case failed(message: String)
}

struct AudioFileDeletionResult: Sendable {
    let candidate: AudioFileCandidate
    let deletion: AudioFileDeletion
}

struct OrphanAudioCleanupResult: Sendable {
    let deletedCount: Int
    let failureCount: Int
}

actor AudioFileCleanupWorker {
    func inspect(_ candidates: [AudioFileCandidate]) -> [AudioFileInspectionResult] {
        return candidates.map { candidate in
            do {
                let values = try candidate.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else {
                    return AudioFileInspectionResult(candidate: candidate, inspection: .missing)
                }
                return AudioFileInspectionResult(
                    candidate: candidate,
                    inspection: .present(size: Int64(values.fileSize ?? 0))
                )
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return AudioFileInspectionResult(candidate: candidate, inspection: .missing)
            } catch {
                return AudioFileInspectionResult(candidate: candidate, inspection: .failed(message: error.localizedDescription))
            }
        }
    }

    func delete(_ candidates: [AudioFileCandidate], allowedRoot: URL) -> [AudioFileDeletionResult] {
        let resolvedRoot = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        return candidates.map { candidate in
            guard candidate.url.isFileURL else {
                return AudioFileDeletionResult(candidate: candidate, deletion: .failed(message: "Not a file URL"))
            }
            let resolvedURL = candidate.url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedURL.path.hasPrefix(rootPrefix) else {
                return AudioFileDeletionResult(candidate: candidate, deletion: .failed(message: "Audio path is outside the recordings directory"))
            }
            do {
                try FileManager.default.removeItem(at: resolvedURL)
                return AudioFileDeletionResult(candidate: candidate, deletion: .deleted)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return AudioFileDeletionResult(candidate: candidate, deletion: .missing)
            } catch {
                return AudioFileDeletionResult(candidate: candidate, deletion: .failed(message: error.localizedDescription))
            }
        }
    }

    func deleteOrphans(referencedFileNames: Set<String>, allowedRoot: URL) -> OrphanAudioCleanupResult {
        let resolvedRoot = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: resolvedRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            var deletedCount = 0
            var failureCount = 0

            for fileURL in files where !referencedFileNames.contains(fileURL.lastPathComponent) {
                let resolvedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
                guard resolvedURL.path.hasPrefix(rootPrefix) else {
                    failureCount += 1
                    continue
                }

                do {
                    let values = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { continue }
                    try FileManager.default.removeItem(at: resolvedURL)
                    deletedCount += 1
                } catch let error as CocoaError where error.code == .fileNoSuchFile {
                    continue
                } catch {
                    failureCount += 1
                }
            }

            return OrphanAudioCleanupResult(deletedCount: deletedCount, failureCount: failureCount)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return OrphanAudioCleanupResult(deletedCount: 0, failureCount: 0)
        } catch {
            return OrphanAudioCleanupResult(deletedCount: 0, failureCount: 1)
        }
    }
}
