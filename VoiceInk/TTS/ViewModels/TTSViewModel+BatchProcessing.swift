import Foundation

// MARK: - Batch and Text Processing Helpers
extension TTSViewModel {
    func shouldAllowCharacterOverflow(for text: String) -> Bool {
        let limit = characterLimit(for: settings.selectedProvider)
        let segments = batchSegments(from: text)
        guard !segments.isEmpty else { return false }
        guard segments.count > 1 else { return false }
        return segments.allSatisfy { $0.count <= limit }
    }

    func batchSegments(from text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var segments: [String] = []
        var currentLines: [String] = []

        func flushCurrentSegment() {
            let segment = currentLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == Self.batchDelimiterToken {
                flushCurrentSegment()
            } else {
                currentLines.append(line)
            }
        }

        flushCurrentSegment()
        return segments
    }

    func stripBatchDelimiters(from text: String) -> String {
        guard !text.isEmpty else { return text }

        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        let filteredLines = normalized
            .components(separatedBy: "\n")
            .filter { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines) != Self.batchDelimiterToken
            }
        let joined = filteredLines.joined(separator: "\n")
        return joined
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyPronunciationRules(to text: String, provider: TTSProviderType) -> String {
        settings.applyPronunciationRules(to: text, provider: provider)
    }
}
