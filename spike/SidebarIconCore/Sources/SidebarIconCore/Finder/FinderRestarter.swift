import AppKit

public enum FinderRestartError: Error, Sendable, Equatable {
    case finderDidNotQuit
    case finderDidNotRelaunch
}

/// Restarts Finder so it reloads sidebar icons. Called only from an explicit user action, never from
/// `apply` or `reset` (Constitution V, research R8). Replaces `killall Finder`.
@MainActor
public enum FinderRestarter {
    public static let finderBundleID = "com.apple.finder"

    /// Asks Finder to quit, then sends SIGTERM (what `killall Finder` sends) if it is still running
    /// after `quitTimeout`. It never sends SIGKILL. Waits for Finder to come back and launches it if
    /// it does not come back by itself. Returns the time from the request to the new Finder
    /// process finishing launch.
    public static func restart(
        quitTimeout: Duration = .seconds(5),
        relaunchTimeout: Duration = .seconds(20)
    ) async throws -> Duration {
        let clock = ContinuousClock()
        let start = clock.now
        let old = NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID)
        let oldPIDs = Set(old.map(\.processIdentifier))

        for app in old { app.terminate() }
        if !(await waitUntil(timeout: quitTimeout) { old.allSatisfy(\.isTerminated) }) {
            for app in old where !app.isTerminated { kill(app.processIdentifier, SIGTERM) }
            guard await waitUntil(timeout: quitTimeout, { old.allSatisfy(\.isTerminated) }) else {
                throw FinderRestartError.finderDidNotQuit
            }
        }

        func newFinder() -> NSRunningApplication? {
            NSRunningApplication.runningApplications(withBundleIdentifier: finderBundleID)
                .first { !oldPIDs.contains($0.processIdentifier) && $0.isFinishedLaunching }
        }

        // A Finder that quits normally is not always relaunched by the system; launch it after a
        // short grace period if it has not reappeared.
        if !(await waitUntil(timeout: .seconds(3)) { newFinder() != nil }) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderBundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
        guard await waitUntil(timeout: relaunchTimeout, { newFinder() != nil }) else {
            throw FinderRestartError.finderDidNotRelaunch
        }
        return clock.now - start
    }

    private static func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }
}
