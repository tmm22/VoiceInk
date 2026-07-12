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
}
