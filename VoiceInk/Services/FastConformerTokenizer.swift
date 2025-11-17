import Foundation

struct FastConformerTokenizer {
    private let idToPiece: [Int: String]
    let blankId: Int

    init(tokensFileURL: URL) throws {
        let contents = try String(contentsOf: tokensFileURL, encoding: .utf8)
        var mapping: [Int: String] = [:]
        var detectedBlankId: Int?

        contents.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let components = trimmed.split(separator: " ")
            guard let last = components.last, let id = Int(last) else { return }
            let token = components.dropLast().joined(separator: " ")
            mapping[id] = token

            if token == "<blk>" || token == "<blank>" || token == "[blank]" {
                detectedBlankId = id
            }
        }

        let resolvedBlankId = detectedBlankId ?? 0
        if mapping[resolvedBlankId] == nil {
            mapping[resolvedBlankId] = ""
        }

        self.idToPiece = mapping
        self.blankId = resolvedBlankId
    }

    func decode(ids: [Int]) -> String {
        guard !ids.isEmpty else { return "" }
        var pieces: [String] = []
        var previous = blankId

        for id in ids {
            if id == blankId {
                previous = blankId
                continue
            }
            if id == previous {
                continue
            }
            if let piece = idToPiece[id], !piece.isEmpty {
                pieces.append(piece)
            }
            previous = id
        }

        let joined = pieces.joined()
        return joined
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
