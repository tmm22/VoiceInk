import Foundation
import OSLog

private let logger = Logger(subsystem: "com.tmm22.voicelinkcommunity", category: "OnnxModelFileLocator")

enum OnnxModelFileLocator {
    private static let preferredFilenames = ["model.int8.onnx", "model.onnx"]
    private static let excludedFilenames: Set<String> = ["decoder.onnx", "encoder.onnx", "joiner.onnx"]
    
    static func findModelFile(in directory: URL) -> URL? {
        for preferredName in preferredFilenames {
            let candidatePath = directory.appendingPathComponent(preferredName)
            if isRegularFile(at: candidatePath) {
                return candidatePath
            }
            if let caseInsensitiveMatch = findCaseInsensitiveMatch(for: preferredName, in: directory) {
                return caseInsensitiveMatch
            }
        }
        
        guard let contents = listOnnxFiles(in: directory) else {
            logger.debug("Failed to read ONNX directory contents")
            return nil
        }
        
        let primaryFiles = contents
            .filter { !excludedFilenames.contains($0.lastPathComponent.lowercased()) }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        
        if let primary = primaryFiles.first {
            if primaryFiles.count > 1 {
                logger.debug("Multiple ONNX files found, selecting the primary candidate")
            }
            return primary
        }
        
        let fallbackFiles = contents.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        if let fallback = fallbackFiles.first {
            logger.debug("No primary ONNX file found, using a fallback candidate")
            return fallback
        }
        
        logger.debug("No ONNX model files found in directory")
        return nil
    }
    
    static func modelExists(in directory: URL) -> Bool {
        findModelFile(in: directory) != nil
    }
    
    private static func isRegularFile(at url: URL) -> Bool {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              let isRegular = resourceValues.isRegularFile else {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return false
            }
            return !isDirectory.boolValue
        }
        return isRegular
    }
    
    private static func listOnnxFiles(in directory: URL) -> [URL]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }
        
        return contents.filter { url in
            guard url.pathExtension.lowercased() == "onnx" else { return false }
            return isRegularFile(at: url)
        }
    }
    
    private static func findCaseInsensitiveMatch(for filename: String, in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }
        return contents.first { 
            $0.lastPathComponent.lowercased() == filename.lowercased() && isRegularFile(at: $0)
        }
    }
}
