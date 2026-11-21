import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

/// Regression tests for the 002 starter review findings.
@Suite struct ReviewFixTests {
    @Test func storedFormIsCheckedWithoutTheFilesystem() {
        #expect(PathStandardizer.isStoredForm("/Users/x/dev"))
        #expect(PathStandardizer.isStoredForm("/"))
        for bad in ["~/dev", "dev", "/Users/x/dev/", "/Users//dev", "/Users/./dev", "/Users/../dev"] {
            #expect(!PathStandardizer.isStoredForm(bad), "\(bad)")
        }
    }

    // Finding 1
    @Test func folderReplacedByALinkDoesNotMakeTheConfigUnreadable() async throws {
        let fixture = try ManagerFixture()
        _ = try await fixture.manager().add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let moved = fixture.dir.url.appending(path: "elsewhere-dev").path
        try FileManager.default.moveItem(atPath: fixture.dev, toPath: moved)
        try FileManager.default.createSymbolicLink(atPath: fixture.dev, withDestinationPath: moved)

        let manager = try await fixture.manager()

        #expect(await manager.readOnlyReason == nil)
        let rows = await manager.rows()
        guard case .error(let reason) = rows.first?.state else {
            Issue.record("expected an error row, got \(String(describing: rows.first?.state))"); return
        }
        #expect(reason.contains("now resolves to"))
        // Other actions still work.
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)
    }

    // Finding 2
    @Test func aSecondActionIsRefusedWhileOneRuns() async throws {
        let fixture = try ManagerFixture()
        let started = Mutex(false)
        let manager = MappingManager(container: fixture.container, system: fixture.system) {
            started.withLock { $0 = true }
            try await Task.sleep(for: .milliseconds(300))
        }
        try await manager.load()
        let refresh = Task { try await manager.refreshFinder() }
        while !started.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }

        await #expect(throws: ManagerError.busy) { try await manager.resetAll() }
        await #expect(throws: ManagerError.busy) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        }
        _ = try await refresh.value
        _ = try await manager.resetAll()
    }

    // Finding 3
    @Test func aClaimedCodeSkipsOnlyItsMapping() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        fixture.system.state.withLock {
            $0.claims["S001"] = [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]
        }

        let result = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)

        let states = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.folderPath, $0.state) })
        #expect(states[fixture.docs] == .applied)
        guard case .error(let reason) = states[fixture.dev] else { Issue.record("dev should show the claim"); return }
        #expect(reason.contains("S001"))
    }

    // Finding 4
    @Test func allocatorChecksTheNextWindowWhenAWholeWindowIsClaimed() async throws {
        let fixture = try ManagerFixture()
        let other = [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]
        fixture.system.state.withLock { state in
            for index in 1...40 { state.claims[OSTypeCode.code(at: index)] = other }
        }
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        #expect(try ConfigStore(container: fixture.container).load().mappings.map(\.osType) == [OSTypeCode.code(at: 41)])
    }

    // Finding 8
    @Test func aLinkedIconsFolderIsRefused() async throws {
        let fixture = try ManagerFixture()
        let target = fixture.dir.url.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.container.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.container.iconsDirectory, withDestinationURL: target)
        let manager = try await fixture.manager()

        await #expect(throws: ManagerError.self) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    // Finding 9
    @Test func resetRemovesStagingFoldersAndAnUnrecordedBundle() async throws {
        let fixture = try ManagerFixture()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fixture.container.registryBundleURL, withIntermediateDirectories: true)
        let staging = fixture.container.root.appending(path: ".IconRegistry.app.staging-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let manager = try await fixture.manager()

        _ = try await manager.resetAll()

        #expect(!fileManager.fileExists(atPath: fixture.container.registryBundleURL.path))
        #expect(!fileManager.fileExists(atPath: staging.path))
        #expect(fixture.system.calls == ["unregister"])
    }

    // Finding 10
    @Test func reapplyingWithoutAChangeDoesNotAskForARefresh() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        #expect(try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png).needsRefresh)
        #expect(try await manager.applyNow().needsRefresh == false)
    }
}
