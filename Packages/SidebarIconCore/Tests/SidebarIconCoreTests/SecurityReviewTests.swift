import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T044: the final security review's findings (research.md, "T044 final reviews").
@Suite struct SecurityReviewTests {
    let dir: TemporaryDirectory

    init() throws {
        dir = try TemporaryDirectory()
    }

    // MARK: - M1: the data folder reached through a link

    @Test func aLinkBetweenTheGroupContainerAndTheRootIsRefused() throws {
        let group = dir.url.appending(path: "group", directoryHint: .isDirectory)
        let elsewhere = dir.url.appending(path: "elsewhere/Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere.appending(path: "Application Support/SidebarIcons"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: group.appending(path: "Library"), withDestinationURL: elsewhere)
        let locator = ContainerLocator(root: group.appending(path: "Library/Application Support/SidebarIcons"), groupContainer: group)

        #expect(throws: ContainerError.self) { try locator.requireRealRoot() }
    }

    @Test func aLinkedRootIsRefusedAndARealOrMissingOneIsFine() throws {
        let target = dir.url.appending(path: "user-folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let linked = dir.url.appending(path: "SidebarIcons")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target)

        #expect(throws: ContainerError.self) { try ContainerLocator(root: linked).requireRealRoot() }
        try ContainerLocator(root: target).requireRealRoot()
        try ContainerLocator(root: dir.url.appending(path: "not-yet")).requireRealRoot()
    }

    @Test func theManagerRefusesALinkedDataFolderAndDeletesNothing() async throws {
        let userFolder = dir.url.appending(path: "Work", directoryHint: .isDirectory)
        let icons = userFolder.appending(path: "Icons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: icons.appending(path: "mine.png"))
        let root = dir.url.appending(path: "SidebarIcons")
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: userFolder)
        let manager = MappingManager(container: ContainerLocator(root: root), system: FakeLaunchServices(favoritePaths: []),
                                     restartFinder: {}, folderIconWriter: FakeFolderIcons())

        await #expect(throws: ManagerError.containerLinked(root.path)) { try await manager.load() }
        await #expect(throws: ManagerError.containerLinked(root.path)) { try await manager.resetAll() }
        #expect(FileManager.default.fileExists(atPath: icons.appending(path: "mine.png").path))
    }

    // MARK: - L1: asset file names

    @Test func assetFileNamesMustBeDerivedFromTheID() {
        let id = UUID()
        #expect(AppConfiguration(mappings: [], assets: [IconAsset(id: id, sourceFormat: .png)]).problems.isEmpty)
        let escaping = IconAsset(id: id, sourceFormat: .pdf, fileName: "../../Documents/scan.pdf")
        #expect(!AppConfiguration(mappings: [], assets: [escaping]).problems.isEmpty)
        let otherIcns = IconAsset(id: id, sourceFormat: .png, icnsFileName: "Assets.car")
        #expect(!AppConfiguration(mappings: [], assets: [otherIcns]).problems.isEmpty)
    }

    // MARK: - L3: ledger codes outside the utility's range

    @Test func applyNeverClearsAnOverrideCodeOutsideItsRange() async throws {
        let setup = try ManagerFixture()
        let ledger = LedgerStore(url: setup.container.ledgerURL)
        try ledger.record(OutsideChange(kind: .sidebarOverride, target: "/elsewhere", osType: "ABCD")) {}
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {},
                                     isValidSystemSymbol: { $0 == "folder" }, glyphTool: FakeActool().runner(),
                                     folderIconWriter: FakeFolderIcons())
        try await manager.load()

        _ = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .systemSymbol(name: "folder"))

        #expect(!setup.system.calls.contains("clear ABCD"))
    }

    // MARK: - L5: bounded container reads

    @Test func containerFilesAreRegularFilesWithinTheLimit() throws {
        let plain = dir.url.appending(path: "plain.json")
        try Data("{}".utf8).write(to: plain)
        #expect(try ContainerFile.read(plain) == Data("{}".utf8))

        let link = dir.url.appending(path: "link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plain)
        #expect(throws: CocoaError.self) { try ContainerFile.read(link) }

        let fifo = dir.url.appending(path: "fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: CocoaError.self) { try ContainerFile.read(fifo) }

        #expect(throws: CocoaError.self) { try ContainerFile.read(plain, limit: 1) }
        let missing = #expect(throws: CocoaError.self) { try ContainerFile.read(dir.url.appending(path: "missing")) }
        #expect(missing?.code == .fileReadNoSuchFile)
    }

    // MARK: - L6: folder art size

    @Test func aHugeMasterIsRefusedBeforeDecoding() throws {
        let big = dir.url.appending(path: "big.png")
        #expect(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(FolderArtBuilder.maximumFileSize + 1))
        try handle.close()

        #expect(throws: FolderArtError.masterTooLarge(name: "big.png")) { try FolderArtBuilder.checkMaster(big) }
    }

    // MARK: - L7: the ledger's temporary file

    @Test func aPlantedLedgerTempLinkIsNeverWrittenThrough() throws {
        let victim = dir.url.appending(path: "victim.txt")
        try Data("keep".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: dir.url.appending(path: "ledger.json.tmp"), withDestinationURL: victim)
        let ledger = LedgerStore(url: dir.url.appending(path: "ledger.json"))

        try ledger.record(OutsideChange(kind: .folderIcon, target: "/x")) {}

        #expect(try String(contentsOf: victim, encoding: .utf8) == "keep")
        #expect(try ledger.entries().count == 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).filter { $0.hasPrefix(".ledger.json.") }
        #expect(leftovers.isEmpty)
    }

    // MARK: - Info and open questions

    @Test func aRegistryBundleWithExtraFilesIsNotIntact() throws {
        let bundle = dir.url.appending(path: "IconRegistry-abcd1234.app", directoryHint: .isDirectory)
        let entries = [IconRegistryBundle.Entry(osType: "S001", style: .systemSymbol(name: "folder"))]
        try IconRegistryBundle.write(entries, assetsCarData: nil, hash: "abcd1234", to: bundle)
        #expect(IconRegistryBundle.isIntact(entries, assetsCarData: nil, hash: "abcd1234", at: bundle))

        let plugIns = bundle.appending(path: "Contents/PlugIns", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plugIns, withIntermediateDirectories: true)
        try Data().write(to: plugIns.appending(path: "Planted.appex"))
        #expect(!IconRegistryBundle.isIntact(entries, assetsCarData: nil, hash: "abcd1234", at: bundle))
    }

    @Test func entityDeclarationsAreRefused() throws {
        let svg = """
        <?xml version="1.0"?>
        <!DOCTYPE svg [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0h10v10z" id="&b;"/></svg>
        """
        #expect(throws: SVGReadError.unsupportedSVG(SVGShapeReader.entityGuidance)) { try SVGShapeReader.read(Data(svg.utf8)) }
        #expect(SymbolTemplatePreview.svg(fromTemplate: svg) == nil)

        // A DOCTYPE without entities, as editors write it, is still fine.
        let plain = """
        <?xml version="1.0"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0h10v10z"/></svg>
        """
        #expect(throws: Never.self) { try SVGShapeReader.read(Data(plain.utf8)) }

        // UTF-16 would hide the declaration from a byte search, so it is refused (re-review 3).
        let utf16 = try #require(svg.data(using: .utf16))
        #expect(throws: SVGReadError.self) { try SVGShapeReader.read(utf16) }
    }
}
