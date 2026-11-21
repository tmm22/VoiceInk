import AppKit
import Foundation
import os

enum BrowserType {
    case safari
    case arc
    case dia
    case chrome
    case comet
    case edge
    case brave
    case opera
    case vivaldi
    case orion
    case yandex

    var scriptName: String {
        switch self {
        case .safari: return "safariURL"
        case .arc: return "arcURL"
        case .dia: return "diaURL"
        case .chrome: return "chromeURL"
        case .comet: return "cometURL"
        case .edge: return "edgeURL"
        case .brave: return "braveURL"
        case .opera: return "operaURL"
        case .vivaldi: return "vivaldiURL"
        case .orion: return "orionURL"
        case .yandex: return "yandexURL"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .arc: return "company.thebrowser.Browser"
        case .dia: return "company.thebrowser.dia"
        case .chrome: return "com.google.Chrome"
        case .comet: return "ai.perplexity.comet"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .opera: return "com.operasoftware.Opera"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .orion: return "com.kagi.kagimacOS"
        case .yandex: return "ru.yandex.desktop.yandex-browser"
        }
    }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .arc: return "Arc"
        case .dia: return "Dia"
        case .chrome: return "Google Chrome"
        case .comet: return "Comet"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .orion: return "Orion"
        case .yandex: return "Yandex Browser"
        }
    }

    static var allCases: [BrowserType] {
        [.safari, .arc, .dia, .chrome, .comet, .edge, .brave, .opera, .vivaldi, .orion, .yandex]
    }

    static var installedBrowsers: [BrowserType] {
        allCases.filter { browser in
            let workspace = NSWorkspace.shared
            return workspace.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil
        }
    }
}

enum BrowserURLError: Error {
    case scriptNotFound
    case executionFailed
    case executionTimedOut
    case browserNotRunning
    case noActiveWindow
    case noActiveTab
}

actor BrowserURLService {
    static let shared = BrowserURLService()

    private let logger = Logger(
        subsystem: AppLogger.subsystem,
        category: "browser.applescript"
    )
    private let scriptTimeout: TimeInterval = 1.5

    private init() {}

    func getCurrentURL(from browser: BrowserType) async throws -> String {
        guard let scriptURL = Bundle.main.url(forResource: browser.scriptName, withExtension: "scpt") else {
            logger.error("❌ AppleScript file not found: \(browser.scriptName, privacy: .public).scpt")
            throw BrowserURLError.scriptNotFound
        }

        logger.debug("🔍 Attempting to execute AppleScript for \(browser.displayName, privacy: .public)")

        // Check if browser is running
        if !isRunning(browser) {
            logger.error("❌ Browser not running: \(browser.displayName, privacy: .public)")
            throw BrowserURLError.browserNotRunning
        }

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = [scriptURL.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        // Process only reports an exit to a handler that was installed before launch.
        let exitWaiter = BrowserURLScriptWaiter()
        task.terminationHandler = { _ in
            exitWaiter.resolve(.exited)
        }

        do {
            logger.debug("▶️ Executing AppleScript for \(browser.displayName, privacy: .public)")
            try task.run()
            try await waitUntilExit(task, waiter: exitWaiter, browser: browser)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if output.isEmpty {
                    logger.error("❌ Empty output from AppleScript for \(browser.displayName, privacy: .public)")
                    throw BrowserURLError.noActiveTab
                }

                // Check if output contains error messages
                if output.lowercased().contains("error") {
                    logger.error(
                        "AppleScript reported an error for \(browser.displayName, privacy: .public); outputBytes=\(data.count, privacy: .public)"
                    )
                    throw BrowserURLError.executionFailed
                }

                logger.debug(
                    "Retrieved browser URL for \(browser.displayName, privacy: .public); characterCount=\(output.count, privacy: .public)"
                )
                return output
            } else {
                logger.error("❌ Failed to decode output from AppleScript for \(browser.displayName, privacy: .public)")
                throw BrowserURLError.executionFailed
            }
        } catch let error as BrowserURLError {
            throw error
        } catch is CancellationError {
            if task.isRunning {
                task.terminate()
            }
            throw CancellationError()
        } catch {
            let errorType = String(describing: type(of: error))
            logger.error(
                "AppleScript execution failed for \(browser.displayName, privacy: .public); type=\(errorType, privacy: .public)"
            )
            throw BrowserURLError.executionFailed
        }
    }

    /// Returns as soon as the script exits. Throws `executionTimedOut` after terminating a script
    /// that is still running at the timeout, and `CancellationError` when the lookup is cancelled
    /// first; the caller terminates the script in that case.
    private func waitUntilExit(
        _ task: Process,
        waiter: BrowserURLScriptWaiter,
        browser: BrowserType
    ) async throws {
        let timeout = scriptTimeout
        let timeoutTask = Task.detached(priority: Task.currentPriority) {
            do {
                try await Task.sleep(for: .seconds(timeout), tolerance: .milliseconds(10), clock: .continuous)
            } catch {
                // Cancelled below: the script exited or the lookup was cancelled first.
                return
            }
            waiter.resolve(.timedOut)
        }
        defer { timeoutTask.cancel() }

        let outcome = await withTaskCancellationHandler {
            await waiter.wait()
        } onCancel: {
            waiter.resolve(.cancelled)
        }

        switch outcome {
        case .exited:
            return
        case .timedOut:
            // The exit notice can trail the exit itself. A script that finished in time counts.
            guard task.isRunning else { return }
            task.terminate()
            logger.error("❌ AppleScript timed out for \(browser.displayName, privacy: .public)")
            throw BrowserURLError.executionTimedOut
        case .cancelled:
            throw CancellationError()
        }
    }

    private func isRunning(_ browser: BrowserType) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == browser.bundleIdentifier }
        logger.debug("\(browser.displayName, privacy: .public) running status: \(isRunning, privacy: .public)")
        return isRunning
    }
}

/// Delivers the first of a script's possible endings (exit, timeout or cancellation) to whoever
/// waits for it. Later endings are ignored, so every party can report without coordinating.
final class BrowserURLScriptWaiter: Sendable {
    enum Outcome: Sendable {
        case exited
        case timedOut
        case cancelled
    }

    private struct State {
        var outcome: Outcome?
        var continuations: [CheckedContinuation<Outcome, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func resolve(_ outcome: Outcome) {
        let continuations: [CheckedContinuation<Outcome, Never>] = state.withLock { state in
            guard state.outcome == nil else { return [] }
            state.outcome = outcome
            let continuations = state.continuations
            state.continuations = []
            return continuations
        }

        for continuation in continuations {
            continuation.resume(returning: outcome)
        }
    }

    func wait() async -> Outcome {
        await withCheckedContinuation { continuation in
            let resolved: Outcome? = state.withLock { state in
                if let outcome = state.outcome {
                    return outcome
                }
                state.continuations.append(continuation)
                return nil
            }

            if let resolved {
                continuation.resume(returning: resolved)
            }
        }
    }
}
