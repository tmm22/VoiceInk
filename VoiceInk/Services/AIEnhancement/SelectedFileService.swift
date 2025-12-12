import Foundation
import AppKit
import OSLog

// MARK: - FileContext Model

struct FileContext: Codable, Sendable {
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

// MARK: - SelectedFileService Errors

enum SelectedFileServiceError: LocalizedError {
    case scriptCreationFailed
    case scriptExecutionFailed(String)
    case finderNotRunning
    case timeout
    case invalidDescriptor
    
    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Failed to create AppleScript for Finder selection"
        case .scriptExecutionFailed(let message):
            return "AppleScript execution failed: \(message)"
        case .finderNotRunning:
            return "Finder is not running"
        case .timeout:
            return "Request timed out while getting Finder selection"
        case .invalidDescriptor:
            return "Invalid AppleScript result descriptor"
        }
    }
}

// MARK: - SelectedFileService

/// Service for retrieving currently selected files from Finder.
/// 
/// This service uses AppleScript to query Finder for the current selection
/// and returns metadata about the selected files.
///
/// - Important: This service requires Finder to be running and may require
///   accessibility permissions to work correctly.
final class SelectedFileService: Sendable {
    
    // MARK: - Singleton
    
    static let shared = SelectedFileService()
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "SelectedFileService")
    
    /// Maximum number of files to process to prevent performance issues
    private let maxFilesToProcess = 100
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Retrieves the currently selected files in Finder with a timeout.
    ///
    /// - Parameter timeout: Maximum time to wait for Finder response (default: 2 seconds)
    /// - Returns: Array of `FileContext` objects for selected files, empty array if none selected or on error
    ///
    /// - Note: This method is safe to call even when Finder is not running or has no selection.
    ///   It will return an empty array in error cases rather than crashing.
    func getSelectedFinderFiles(timeout: TimeInterval = 2.0) async -> [FileContext] {
        // Validate timeout is reasonable
        let safeTimeout = max(0.5, min(timeout, 10.0))
        
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
        
        return await withTaskGroup(of: [FileContext]?.self) { group in
            // Task 1: Execute the AppleScript
            group.addTask { [weak self] in
                guard let self = self else { return [] }
                return self.executeScriptSafely(source: scriptSource)
            }
            
            // Task 2: Timeout watchdog
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(safeTimeout * 1_000_000_000))
                return nil // nil indicates timeout
            }
            
            // Return first non-nil, non-empty result, or empty array on timeout
            for await result in group {
                if let files = result {
                    // Cancel remaining tasks
                    group.cancelAll()
                    return files
                }
            }
            
            // If we get here, we timed out
            logger.info("Finder selection query timed out after \(safeTimeout) seconds")
            return []
        }
    }
    
    // MARK: - Private Methods
    
    /// Safely executes an AppleScript and returns file contexts.
    ///
    /// This method wraps all AppleScript execution in proper error handling
    /// to prevent crashes from unexpected script results.
    ///
    /// - Parameter source: The AppleScript source code to execute
    /// - Returns: Array of FileContext objects, empty on any error
    private func executeScriptSafely(source: String) -> [FileContext] {
        // Validate input
        guard !source.isEmpty else {
            logger.warning("Empty script source provided")
            return []
        }
        
        // Create the AppleScript object
        guard let script = NSAppleScript(source: source) else {
            logger.error("Failed to create AppleScript object")
            return []
        }
        
        // Execute with error capture
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        
        // Handle execution errors
        if let error = errorDict {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1
            
            // Error -600 means Finder is not running - this is expected in some cases
            if errorNumber == -600 {
                logger.info("Finder is not running, skipping file selection")
            } else {
                logger.warning("AppleScript error (\(errorNumber)): \(errorMessage)")
            }
            return []
        }
        
        // Safely parse the result descriptor
        return parseResultDescriptor(result)
    }
    
    /// Safely parses an AppleScript result descriptor into file contexts.
    ///
    /// - Parameter descriptor: The NSAppleEventDescriptor from script execution
    /// - Returns: Array of FileContext objects
    private func parseResultDescriptor(_ descriptor: NSAppleEventDescriptor) -> [FileContext] {
        var fileContexts: [FileContext] = []
        
        let count = descriptor.numberOfItems
        
        // Safe guard: numberOfItems returns 0 for empty results or non-list types
        // Using 1...0 would crash, so we explicitly check
        guard count > 0 else {
            logger.debug("No files selected in Finder (count: \(count))")
            return []
        }
        
        // Limit processing to prevent performance issues with huge selections
        let maxItems = self.maxFilesToProcess
        let itemsToProcess = min(count, maxItems)
        if count > maxItems {
            logger.warning("Finder selection has \(count) items, limiting to \(maxItems)")
        }
        
        // AppleScript descriptors are 1-indexed
        // Using stride is safer than closed range for edge cases
        for index in stride(from: 1, through: itemsToProcess, by: 1) {
            autoreleasepool {
                guard let pathDescriptor = descriptor.atIndex(index) else {
                    logger.debug("No descriptor at index \(index)")
                    return
                }
                
                guard let path = pathDescriptor.stringValue, !path.isEmpty else {
                    logger.debug("Empty or nil path at index \(index)")
                    return
                }
                
                // Validate path exists before processing
                guard FileManager.default.fileExists(atPath: path) else {
                    logger.debug("File does not exist at path: \(path)")
                    return
                }
                
                if let context = processFileSafely(at: path) {
                    fileContexts.append(context)
                }
            }
        }
        
        logger.debug("Successfully processed \(fileContexts.count) file(s) from Finder selection")
        return fileContexts
    }
    
    /// Safely processes a file path into a FileContext.
    ///
    /// - Parameter path: The POSIX path to the file
    /// - Returns: FileContext if successful, nil otherwise
    private func processFileSafely(at path: String) -> FileContext? {
        // Validate path is not empty or whitespace-only
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            logger.debug("Empty path provided to processFileSafely")
            return nil
        }
        
        let url = URL(fileURLWithPath: trimmedPath)
        let fileManager = FileManager.default
        
        // Check file exists and is accessible
        guard fileManager.isReadableFile(atPath: trimmedPath) else {
            logger.debug("File not readable at path: \(trimmedPath)")
            return nil
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: trimmedPath)
            
            let filename = url.lastPathComponent
            
            // Safely extract attributes with fallbacks
            let size: Int64
            if let sizeNumber = attributes[.size] as? NSNumber {
                size = sizeNumber.int64Value
            } else {
                size = 0
            }
            
            let created = attributes[.creationDate] as? Date ?? Date.distantPast
            let modified = attributes[.modificationDate] as? Date ?? Date.distantPast
            let ext = url.pathExtension
            
            return FileContext(
                filename: filename,
                path: trimmedPath,
                fileSize: size,
                creationDate: created,
                modificationDate: modified,
                fileExtension: ext
            )
        } catch let error as NSError {
            // Log specific error information for debugging
            logger.error("Failed to read file attributes at '\(trimmedPath)': [\(error.domain):\(error.code)] \(error.localizedDescription)")
            return nil
        } catch {
            logger.error("Unexpected error reading file at '\(trimmedPath)': \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension SelectedFileService {
    /// Creates a FileContext for testing purposes
    static func makeTestFileContext(
        filename: String = "test.txt",
        path: String = "/tmp/test.txt",
        fileSize: Int64 = 1024,
        fileExtension: String = "txt"
    ) -> FileContext {
        return FileContext(
            filename: filename,
            path: path,
            fileSize: fileSize,
            creationDate: Date(),
            modificationDate: Date(),
            fileExtension: fileExtension
        )
    }
}
#endif
