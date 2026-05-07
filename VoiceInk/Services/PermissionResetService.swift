import Foundation

enum PermissionResetService {
    private static let fallbackBundleIdentifier = "com.tmm22.VoiceLinkCommunity"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
    }

    static var resetCommand: String {
        "tccutil reset All \(shellEscaped(bundleIdentifier))"
    }

    static func resetCurrentBundlePermissions() async -> PermissionResetOutcome {
        let bundleIdentifier = self.bundleIdentifier
        let result = await Task.detached {
            runTCCReset(for: bundleIdentifier)
        }.value

        switch result {
        case .success:
            AppLogger.app.info("Reset macOS privacy permissions for \(bundleIdentifier, privacy: .public)")
            return .succeeded(bundleIdentifier: bundleIdentifier)
        case .failure(let error):
            AppLogger.app.error("Failed to reset macOS privacy permissions for \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(
                bundleIdentifier: bundleIdentifier,
                command: resetCommand,
                errorDescription: error.localizedDescription
            )
        }
    }

    private static func runTCCReset(for bundleIdentifier: String) -> Result<Void, PermissionResetError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleIdentifier]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.commandFailed(status: process.terminationStatus, output: output))
        }

        return .success(())
    }

    private static func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum PermissionResetOutcome: Equatable {
    case succeeded(bundleIdentifier: String)
    case failed(bundleIdentifier: String, command: String, errorDescription: String)

    var message: String {
        switch self {
        case .succeeded:
            return "Permission records were reset. Quit and reopen VoiceInk, then grant permissions again when macOS prompts."
        case .failed(_, let command, let errorDescription):
            return "VoiceInk could not reset permission records automatically: \(errorDescription). The Terminal command has been copied: \(command)"
        }
    }
}

enum PermissionResetError: Error, LocalizedError {
    case launchFailed(String)
    case commandFailed(status: Int32, output: String?)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .commandFailed(let status, let output):
            if let output, !output.isEmpty {
                return "tccutil exited with status \(status): \(output)"
            }
            return "tccutil exited with status \(status)"
        }
    }
}
