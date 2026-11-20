import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct LedgerStoreTests {
    let dir: TemporaryDirectory
    let ledger: LedgerStore

    init() throws {
        dir = try TemporaryDirectory()
        ledger = LedgerStore(url: dir.url.appending(path: "nested/ledger.json"))
    }

    private func change(_ target: String = "/Users/someone/dev", code: String = "S001") -> OutsideChange {
        OutsideChange(kind: .sidebarOverride, target: target, osType: code, macOSBuild: "TEST")
    }

    @Test func missingLedgerIsEmpty() throws {
        #expect(try ledger.entries().isEmpty)
    }

    @Test func emptyFileIsEmpty() throws {
        try FileManager.default.createDirectory(at: ledger.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: ledger.url)
        #expect(try ledger.entries().isEmpty)
    }

    @Test func corruptFileIsReportedNotIgnored() throws {
        try FileManager.default.createDirectory(at: ledger.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: ledger.url)
        #expect(throws: SidebarIconError.self) { try ledger.entries() }
    }

    @Test func entryIsPersistedBeforeApplyRuns() throws {
        let entry = change()
        var seenDuringApply: [OutsideChange] = []
        try ledger.record(entry) {
            seenDuringApply = try ledger.entries()
        }
        #expect(seenDuringApply.map(\.id) == [entry.id])
        #expect(try ledger.entries().map(\.id) == [entry.id])
    }

    @Test func failedApplyDeletesTheEntry() throws {
        #expect(throws: TestError()) {
            try ledger.record(change()) { throw TestError() }
        }
        #expect(try ledger.entries().isEmpty)
    }

    @Test func failedApplyKeepsOtherEntries() throws {
        let first = change("/a")
        try ledger.record(first) {}
        #expect(throws: TestError()) {
            try ledger.record(change("/b")) { throw TestError() }
        }
        #expect(try ledger.entries().map(\.id) == [first.id])
    }

    @Test func reapplyingTheSameEffectDoesNotDuplicate() throws {
        try ledger.record(change()) {}
        var applyRan = false
        try ledger.record(change()) { applyRan = true }
        #expect(applyRan)
        #expect(try ledger.entries().count == 1)
    }

    @Test func failedReapplyKeepsTheOriginalEntry() throws {
        try ledger.record(change()) {}
        #expect(throws: TestError()) {
            try ledger.record(change()) { throw TestError() }
        }
        #expect(try ledger.entries().count == 1)
    }

    @Test func successfulUndoRemovesTheEntry() throws {
        let entry = change()
        try ledger.record(entry) {}
        try ledger.undo(entry) {}
        #expect(try ledger.entries().isEmpty)
    }

    @Test func failedUndoKeepsTheEntry() throws {
        let entry = change()
        try ledger.record(entry) {}
        #expect(throws: TestError()) {
            try ledger.undo(entry) { throw TestError() }
        }
        #expect(try ledger.entries().map(\.id) == [entry.id])
    }

    @Test func datesAndFieldsRoundTrip() throws {
        let entry = OutsideChange(
            kind: .iconRegistration,
            target: "/x/IconRegistry.app",
            appliedAt: Date(timeIntervalSince1970: 1_800_000_000),
            macOSBuild: "26B131"
        )
        try ledger.record(entry) {}
        #expect(try ledger.entries() == [entry])
    }
}
