import Foundation

/// The single seam between configuration/GUI code and the mechanism that puts an icon in the
/// sidebar (Constitution II, contracts/sidebar-icon-provider.md).
public protocol SidebarIconProvider: Sendable {
    /// Short identifier written to the findings record, e.g. "finder-sync" or "ls-override".
    var mechanism: String { get }

    /// Read-only. Reports, per mapping, whether its folder is currently in Favorites,
    /// whether an override is active, and which code/icon is in effect.
    func status(for mappings: [SidebarMapping]) async throws -> [MappingStatus]

    /// Makes the sidebar match `mappings` (enabled ones applied, others cleared).
    /// Must write ledger entries before each outside change. Idempotent.
    func apply(_ mappings: [SidebarMapping], assets: [IconAsset]) async throws -> ApplyReport

    /// Undoes every ledger entry this provider owns. Idempotent; safe with an empty ledger.
    func reset() async throws -> ResetReport
}

public struct MappingStatus: Sendable, Equatable {
    public var mappingID: UUID
    public var folderPath: String
    public var folderExists: Bool
    /// How many Favorites resolve to `folderPath`: 0 means not in Favorites, more than 1 is a
    /// duplicate (reported, never changed).
    public var favoriteCount: Int?
    /// The type code currently set on the Favorite, if the mechanism can read it.
    public var activeOverride: String?
    public var note: String?

    public init(
        mappingID: UUID,
        folderPath: String,
        folderExists: Bool,
        favoriteCount: Int? = nil,
        activeOverride: String? = nil,
        note: String? = nil
    ) {
        self.mappingID = mappingID
        self.folderPath = folderPath
        self.folderExists = folderExists
        self.favoriteCount = favoriteCount
        self.activeOverride = activeOverride
        self.note = note
    }
}

public struct ApplyReport: Sendable, Equatable {
    public struct Skip: Sendable, Equatable {
        public var mappingID: UUID
        public var reason: SidebarIconError
    }

    /// Mappings whose override was set.
    public var applied: [UUID] = []
    /// Mappings left unchanged, with the reason.
    public var skipped: [Skip] = []
    /// Overrides removed because their mapping is disabled or gone.
    public var cleared: [String] = []
    public var notes: [String] = []

    public init() {}
}

public struct ResetReport: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public var change: OutsideChange
        public var reason: SidebarIconError
    }

    public var undone: [OutsideChange] = []
    /// Entries that could not be undone; they stay in the ledger.
    public var failed: [Failure] = []
    public var notes: [String] = []

    public init() {}

    public var succeeded: Bool { failed.isEmpty }
}

public enum SidebarIconError: Error, Sendable, Equatable {
    /// Experiment B1 fails: the Favorites list cannot be read.
    case favoritesUnavailable
    case folderNotInFavorites(String)
    /// Spec edge case: the folder is in Favorites more than once, so it is left alone.
    case folderInFavoritesMoreThanOnce(String)
    case folderMissing(String)
    case registrationFailed(Int32)
    case propertyRejected(String, Int32)
    /// The clear call succeeded but the Favorite still carries the code when read back.
    case overrideNotCleared(path: String, code: String)
    case assetConversionFailed(UUID)
    case ledgerIOFailed(String)
    /// Research R7: another registered bundle already claims one of the codes.
    case codeClaimedElsewhere(code: String, owners: [String])
    case invalidMapping(String)
    /// The Favorite already carries an override this utility did not set; it is left alone.
    case foreignOverride(path: String, code: String)
    /// A ledger entry names something other than this utility's own change; it is left alone.
    case unexpectedLedgerTarget(String)
    case toolFailed(String)

    /// Plain-language message for the spike UI.
    public var message: String {
        switch self {
        case .favoritesUnavailable:
            "The Finder sidebar Favorites list could not be read."
        case .folderNotInFavorites(let path):
            "\(path) is not in the Finder sidebar Favorites. Drag it into the sidebar first."
        case .folderInFavoritesMoreThanOnce(let path):
            "\(path) is in Favorites more than once; it was left unchanged."
        case .folderMissing(let path):
            "\(path) does not exist; it was not created."
        case .registrationFailed(let status):
            "Launch Services did not accept the icon registration bundle (OSStatus \(status))."
        case .propertyRejected(let path, let status):
            "The sidebar refused the icon override for \(path) (OSStatus \(status))."
        case .overrideNotCleared(let path, let code):
            "The sidebar override \(code) on \(path) could not be removed; it is still recorded."
        case .assetConversionFailed(let id):
            "The image for asset \(id) could not be converted to an icon."
        case .ledgerIOFailed(let detail):
            "The change ledger could not be read or written: \(detail)"
        case .codeClaimedElsewhere(let code, let owners):
            "Type code \(code) is already claimed by: \(owners.joined(separator: ", ")); that mapping was not applied."
        case .invalidMapping(let detail):
            "The mappings are invalid (\(detail)); nothing was changed."
        case .foreignOverride(let path, let code):
            "\(path) already has sidebar override \(code), set by something else; it was left unchanged."
        case .unexpectedLedgerTarget(let target):
            "The ledger names \(target), which is not this utility's own change; it was left untouched."
        case .toolFailed(let detail):
            "A system tool failed: \(detail)"
        }
    }
}
