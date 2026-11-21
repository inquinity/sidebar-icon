import Testing
@testable import SidebarIconCore

@Suite struct AllocatorClaimsTests {
    @Test func skipsCodesInUseAndClaimedElsewhere() throws {
        // S001 is in the config, S002 in the ledger, S003 claimed by another bundle.
        let codes = try OSTypeAllocator.allocate(1, excluding: ["S001", "S002"]) { $0 == "S003" }
        #expect(codes == ["S004"])
    }

    @Test func claimedCodeIsSkippedNotFatal() throws {
        #expect(try OSTypeAllocator.allocate(1, excluding: []) { $0 == "S001" } == ["S002"])
        #expect(try OSTypeAllocator.allocate(2, excluding: []) { $0 == "S002" } == ["S001", "S003"])
    }

    @Test func failsOnlyWhenTheRangeIsExhausted() {
        #expect(throws: OSTypeAllocationError.exhausted) {
            try OSTypeAllocator.allocate(1, excluding: []) { _ in true }
        }
    }

    @Test func claimCheckErrorsPropagate() {
        #expect(throws: TestError.self) {
            try OSTypeAllocator.allocate(1, excluding: []) { _ in throw TestError() }
        }
    }
}
