import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct PathStandardizerTests {
    @Test func expandsTildeFromGivenHome() {
        #expect(PathStandardizer.standardize("~/dev", home: "/Users/someone") == "/Users/someone/dev")
        #expect(PathStandardizer.standardize("~", home: "/Users/someone") == "/Users/someone")
    }

    @Test func removesTrailingSlashAndDotSegments() {
        #expect(PathStandardizer.standardize("/Users/someone/dev/") == "/Users/someone/dev")
        #expect(PathStandardizer.standardize("/Users/someone/./x/../dev//") == "/Users/someone/dev")
        #expect(PathStandardizer.standardize("/") == "/")
    }

    @Test func resolvesSymlinks() throws {
        let dir = try TemporaryDirectory()
        let real = dir.url.appending(path: "real", directoryHint: .isDirectory)
        let link = dir.url.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(PathStandardizer.standardize(link.path) == PathStandardizer.standardize(real.path))
    }

    @Test func realHomeIsAbsolute() {
        #expect(PathStandardizer.realHomeDirectory.hasPrefix("/"))
    }
}

@Suite struct OSTypeTests {
    @Test(arguments: ["S001", "S000", "SZZZ", "S0A9"])
    func validCodes(_ code: String) {
        #expect(OSTypeCode.isValid(code))
    }

    @Test(arguments: ["D001", "S01", "S0001", "s001", "S00a", "S00-", "", "SÄ00"])
    func invalidCodes(_ code: String) {
        #expect(!OSTypeCode.isValid(code))
    }

    @Test func allocatesFromS001InOrder() throws {
        #expect(try OSTypeAllocator.allocate(3, excluding: []) == ["S001", "S002", "S003"])
    }

    @Test func rollsOverIntoLetters() throws {
        let codes = try OSTypeAllocator.allocate(11, excluding: [])
        #expect(codes[8] == "S009")
        #expect(codes[9] == "S00A")
        #expect(codes[10] == "S00B")
    }

    @Test func skipsCodesStillInUse() throws {
        #expect(try OSTypeAllocator.allocate(2, excluding: ["S001", "S003"]) == ["S002", "S004"])
    }

    @Test func everyAllocatedCodeIsValid() throws {
        let codes = try OSTypeAllocator.allocate(100, excluding: [])
        #expect(codes.allSatisfy(OSTypeCode.isValid))
        #expect(Set(codes).count == 100)
    }

    @Test func reportsExhaustion() {
        #expect(throws: OSTypeAllocationError.exhausted) {
            try OSTypeAllocator.allocate(OSTypeCode.capacity, excluding: [])
        }
    }
}

@Suite struct MappingValidationTests {
    private func mapping(_ path: String, _ code: String) -> SidebarMapping {
        SidebarMapping(folderPath: path, iconAssetID: UUID(), osType: code)
    }

    @Test func acceptsWellFormedMappings() {
        let mappings = [mapping("/Users/someone/dev", "S001"), mapping("/Users/someone/DevDocs", "S002")]
        #expect(SidebarMapping.validate(mappings).isEmpty)
    }

    @Test func rejectsUnstandardizedPath() {
        let problems = SidebarMapping.validate([mapping("/Users/someone/dev/", "S001")])
        #expect(problems == [.pathNotStandardized("/Users/someone/dev/")])
    }

    @Test func rejectsTildePath() {
        let problems = SidebarMapping.validate([mapping("~/dev", "S001")])
        #expect(problems.contains(.pathNotStandardized("~/dev")))
    }

    @Test func rejectsDuplicatePath() {
        let problems = SidebarMapping.validate([mapping("/Users/someone/dev", "S001"), mapping("/Users/someone/dev", "S002")])
        #expect(problems == [.duplicatePath("/Users/someone/dev")])
    }

    @Test func rejectsBadAndDuplicateCodes() {
        let problems = SidebarMapping.validate([
            mapping("/Users/someone/a", "D001"),
            mapping("/Users/someone/b", "S002"),
            mapping("/Users/someone/c", "S002"),
        ])
        #expect(problems == [.invalidOSType("D001"), .duplicateOSType("S002")])
    }

    @Test func modelRoundTripsThroughJSON() throws {
        let original = mapping("/Users/someone/dev", "S001")
        let decoded = try JSONDecoder().decode(SidebarMapping.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func assetFileNameDefaultsToIDAndFormat() {
        let id = UUID()
        #expect(IconAsset(id: id, sourceFormat: .png).fileName == "\(id.uuidString).png")
    }
}
