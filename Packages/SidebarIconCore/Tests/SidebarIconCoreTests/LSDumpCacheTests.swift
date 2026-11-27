import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

/// 1.0.0 gate F002: one dump serves the reads of an action.
@Suite struct LSDumpCacheTests {
    @Test func aFreshDumpIsReusedAndAnExpiredOrInvalidatedOneIsReloaded() throws {
        let cache = LSDumpCache(lifetime: 5)
        let loads = Mutex(0)
        let load = { () throws -> String in loads.withLock { $0 += 1 }; return "dump \(loads.withLock { $0 })" }
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(try cache.read(now: start, load: load) == "dump 1")
        #expect(try cache.read(now: start.addingTimeInterval(4), load: load) == "dump 1")
        #expect(try cache.read(now: start.addingTimeInterval(6), load: load) == "dump 2")
        cache.invalidate()
        #expect(try cache.read(now: start.addingTimeInterval(7), load: load) == "dump 3")
        #expect(loads.withLock { $0 } == 3)
    }

    @Test func aFailedLoadIsNotCached() throws {
        let cache = LSDumpCache()
        struct Failure: Error {}
        #expect(throws: Failure.self) { try cache.read { throw Failure() } }
        #expect(try cache.read { "ok" } == "ok")
    }
}
