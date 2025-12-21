import Foundation
import UserNotifications

// MARK: - Batch and Text Processing Helpers
extension TTSViewModel {
    func persistSnippets() {
        do {
            let data = try JSONEncoder().encode(textSnippets)
            UserDefaults.standard.set(data, forKey: snippetsKey)
        } catch {
            // If persistence fails, keep in-memory state for this session
        }
    }

    func persistPronunciationRules() {
        do {
            let data = try JSONEncoder().encode(pronunciationRules)
            UserDefaults.standard.set(data, forKey: pronunciationKey)
        } catch {
            // If persistence fails, keep the in-memory rules this session
        }
    }

    func shouldAllowCharacterOverflow(for text: String) -> Bool {
        let limit = characterLimit(for: selectedProvider)
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
            if line.trimmingCharacters(in: .whitespaces) == batchDelimiterToken {
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
                line.trimmingCharacters(in: .whitespacesAndNewlines) != batchDelimiterToken
            }
        let joined = filteredLines.joined(separator: "\n")
        return joined
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyPronunciationRules(to text: String, provider: TTSProviderType) -> String {
        pronunciationRules.reduce(text) { current, rule in
            guard rule.applies(to: provider) else { return current }
            return replaceOccurrences(in: current, target: rule.displayText, replacement: rule.replacementText)
        }
    }

    func replaceOccurrences(in text: String, target: String, replacement: String) -> String {
        guard !target.isEmpty else { return text }
        var result = text
        var searchRange = result.startIndex..<result.endIndex

        while let range = result.range(of: target, options: [.caseInsensitive], range: searchRange) {
            result.replaceSubrange(range, with: replacement)
            if replacement.isEmpty {
                searchRange = range.lowerBound..<result.endIndex
            } else {
                let nextIndex = result.index(range.lowerBound, offsetBy: replacement.count)
                searchRange = nextIndex..<result.endIndex
            }
        }

        return result
    }

    func sendBatchCompletionNotification(successCount: Int, failureCount: Int) {
        guard notificationsEnabled, successCount + failureCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Batch Generation Complete"

        if failureCount == 0 {
            content.body = "All \(successCount) segment(s) generated successfully."
        } else if successCount == 0 {
            content.body = "Batch generation failed for all \(failureCount) segment(s)."
        } else {
            content.body = "\(successCount) succeeded • \(failureCount) failed."
        }

        let request = UNNotificationRequest(
            identifier: "batch-complete-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        notificationCenter?.add(request)
    }
}
