import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct MappingStateTests {
    let mapping = SidebarMapping(folderPath: "/Users/x/dev", iconAssetID: UUID(), osType: "S001")

    func status(exists: Bool = true, count: Int? = 1, active: String? = nil) -> MappingStatus {
        MappingStatus(mappingID: mapping.id, folderPath: mapping.folderPath, folderExists: exists,
                      favoriteCount: count, activeOverride: active)
    }

    func state(_ status: MappingStatus, enabled: Bool = true, registered: Bool = true, failure: String? = nil) -> MappingState {
        var mapping = mapping
        mapping.enabled = enabled
        return MappingState.state(for: mapping, status: status, bundleRegistered: registered, lastFailure: failure)
    }

    @Test func applied() {
        #expect(state(status(active: "S001")) == .applied)
    }

    @Test func off() {
        #expect(state(status(active: "S001"), enabled: false) == .off)
    }

    @Test func notInSidebar() {
        #expect(state(status(count: 0)) == .notInSidebar)
    }

    @Test func folderMissing() {
        #expect(state(status(exists: false, count: 1, active: "S001")) == .folderMissing)
    }

    @Test func notAppliedWhenOverrideAbsentOrBundleUnregistered() {
        #expect(state(status(active: nil)) == .notApplied)
        #expect(state(status(active: "S001"), registered: false) == .notApplied)
    }

    @Test func errors() {
        guard case .error = state(status(count: 2)) else { Issue.record("duplicate Favorite"); return }
        guard case .error = state(status(active: "ABCD")) else { Issue.record("foreign override"); return }
        guard case .error = state(status(count: nil)) else { Issue.record("Favorites unreadable"); return }
        #expect(state(status(active: nil), failure: "Type code S001 is claimed") == .error("Type code S001 is claimed"))
    }

    @Test func lastApplyFailureOutranksAStillSetOverride() {
        #expect(state(status(active: "S001"), failure: "claimed") == .error("claimed"))
    }
}
