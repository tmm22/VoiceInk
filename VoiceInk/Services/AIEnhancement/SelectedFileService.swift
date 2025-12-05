import Foundation
import AppKit
import OSLog

struct FileContext: Codable {
    let filename: String
    let path: String
    let fileSize: Int64
    let creationDate: Date
    let modificationDate: Date
    let fileExtension: String
    
    var formattedDescription: String {
        return "Selected File: \(filename) (Extension: .\(fileExtension))"
    }
}

class SelectedFileService {
    static let shared = SelectedFileService()
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "SelectedFileService")
    
    func getSelectedFinderFiles(timeout: TimeInterval = 2.0) async -> [FileContext] {
        let scriptSource = """
        tell application "Finder"
            set selectedItems to selection
            set fileList to {}
            repeat with itemRef in selectedItems
                set itemPath to POSIX path of (itemRef as alias)
                copy itemPath to end of fileList
            end repeat
            return fileList
        end tell
        """
        
        return await withTaskGroup(of: [FileContext].self) { group in
            group.addTask {
                let task = Task.detached {
                    return self.executeScript(source: scriptSource)
                }
                return await task.value
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return [] // Timeout returns empty list
            }
            
            if let result = await group.next(), !result.isEmpty {
                return result
            }
            return []
        }
    }
    
    private func executeScript(source: String) -> [FileContext] {
        var fileContexts: [FileContext] = []
        
        guard let script = NSAppleScript(source: source) else {
            logger.error("Failed to create AppleScript for Finder selection")
            return []
        }
        
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        
        if let error = errorDict {
            // Log but don't error out - Finder might just not have selection
            return []
        }
        
        // Process the result list
        let descriptor = result
        let count = descriptor.numberOfItems
        
        for i in 1...count {
            if let pathDescriptor = descriptor.atIndex(i),
               let path = pathDescriptor.stringValue {
                if let context = processFile(at: path) {
                    fileContexts.append(context)
                }
            }
        }
        
        return fileContexts
    }
    
    private func processFile(at path: String) -> FileContext? {
        let url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let filename = url.lastPathComponent
            let size = attributes[.size] as? Int64 ?? 0
            let created = attributes[.creationDate] as? Date ?? Date()
            let modified = attributes[.modificationDate] as? Date ?? Date()
            let ext = url.pathExtension
            
            return FileContext(
                filename: filename,
                path: path,
                fileSize: size,
                creationDate: created,
                modificationDate: modified,
                fileExtension: ext
            )
        } catch {
            logger.error("Failed to read attributes for file at \(path): \(error.localizedDescription)")
            return nil
        }
    }
}
