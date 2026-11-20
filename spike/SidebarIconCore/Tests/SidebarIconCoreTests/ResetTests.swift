import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct ResetTests {
    private func appliedProvider() async throws -> (ProviderFixture, FakeLaunchServices, LaunchServicesOverrideProvider) {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        system.state.withLock { $0.calls = [] }
        return (fixture, system, provider)
    }

    @Test func clearsOverridesBeforeUnregistering() async throws {
        let (fixture, system, provider) = try await appliedProvider()

        let report = try await provider.reset()

        #expect(report.succeeded)
        #expect(system.calls == ["clear S001", "clear S002", "unregister"])
        #expect(try provider.ledgerEntries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.container.registryBundleURL.path))
        #expect(try system.listFavorites().allSatisfy { $0.overrideIcon == nil })
    }

    @Test func resetTwiceIsANoOp() async throws {
        let (_, system, provider) = try await appliedProvider()
        _ = try await provider.reset()
        system.state.withLock { $0.calls = [] }

        let second = try await provider.reset()

        #expect(second.succeeded)
        #expect(second.undone.isEmpty)
        #expect(system.calls.isEmpty)
    }

    @Test func resetWithEmptyLedgerSucceeds() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [])
        let report = try await LaunchServicesOverrideProvider(container: fixture.container, system: system).reset()
        #expect(report.succeeded && report.undone.isEmpty && system.calls.isEmpty)
    }

    @Test func partialFailureKeepsFailedEntriesAndTheRegistration() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        system.state.withLock { $0.failClearing = ["S002"] }

        let report = try await provider.reset()

        #expect(!report.succeeded)
        #expect(report.failed.map(\.change.target) == [fixture.docs])
        #expect(!system.calls.contains("unregister"))
        let remaining = try provider.ledgerEntries()
        #expect(remaining.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.iconRegistration, .sidebarOverride])
        #expect(remaining.contains { $0.target == fixture.docs })

        // Once the cause is fixed, a second reset finishes the job.
        system.state.withLock { $0.failClearing = [] }
        let retry = try await provider.reset()
        #expect(retry.succeeded)
        #expect(try provider.ledgerEntries().isEmpty)
    }

    @Test func failedUnregisterKeepsTheRegistrationEntry() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        system.state.withLock { $0.failUnregister = true }

        let report = try await provider.reset()

        #expect(report.failed.map(\.change.kind) == [.iconRegistration])
        #expect(try provider.ledgerEntries().map(\.kind) == [.iconRegistration])
        #expect(FileManager.default.fileExists(atPath: fixture.container.registryBundleURL.path))
    }

    @Test func refusesToTouchARegistrationThatIsNotItsOwnBundle() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [])
        let precious = fixture.dir.url.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: precious, withIntermediateDirectories: true)
        try LedgerStore(url: fixture.container.ledgerURL).record(OutsideChange(kind: .iconRegistration, target: precious.path)) {}
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        let report = try await provider.reset()

        #expect(report.failed.map(\.reason) == [.unexpectedLedgerTarget(precious.path)])
        #expect(system.calls.isEmpty)
        #expect(FileManager.default.fileExists(atPath: precious.path))
        #expect(try provider.ledgerEntries().count == 1)
    }

    @Test func leavesAnOverrideSomeoneElseReplaced() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        system.state.withLock { state in
            let index = state.favorites.firstIndex { $0.path == fixture.dev }!
            state.favorites[index].overrideIcon = "D001"
        }
        let report = try await provider.reset()
        #expect(report.succeeded)
        #expect(try system.listFavorites().first { $0.path == fixture.dev }?.overrideIcon == "D001")
        #expect(report.notes.contains { $0.contains("S001") })
        #expect(try provider.ledgerEntries().isEmpty)
    }

    @Test func clearsAnOverrideWhoseFolderWasMoved() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        system.state.withLock { state in
            let index = state.favorites.firstIndex { $0.path == fixture.dev }!
            state.favorites[index].path = fixture.dev + "-renamed"
        }
        let report = try await provider.reset()
        #expect(report.succeeded)
        #expect(try system.listFavorites().allSatisfy { $0.overrideIcon == nil })
    }

    @Test func unregisterFailureForAnAlreadyDeletedBundleIsFineIfNoLongerListed() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        try FileManager.default.removeItem(at: fixture.container.registryBundleURL)
        system.state.withLock { $0.unregisterFailsWhenMissing = true }
        let report = try await provider.reset()
        #expect(report.succeeded)
        #expect(try provider.ledgerEntries().isEmpty)
    }

    @Test func clearingAFavoriteTheUserRemovedSucceeds() async throws {
        let (fixture, system, provider) = try await appliedProvider()
        system.state.withLock { state in state.favorites.removeAll { $0.path == fixture.docs } }
        let report = try await provider.reset()
        #expect(report.succeeded)
        #expect(try provider.ledgerEntries().isEmpty)
    }
}
