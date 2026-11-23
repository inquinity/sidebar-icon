import SidebarIconCore

/// Curated SF Symbol names that suit folders (research D6). Suggestions only: any name that
/// exists on this Mac is accepted, and names missing on this Mac are filtered out.
enum SymbolCatalog {
    static let names: [String] = [
        // Folders and files
        "folder", "folder.fill", "folder.badge.gearshape", "folder.badge.person.crop",
        "doc", "doc.text", "doc.richtext", "doc.on.doc", "tray", "tray.full", "archivebox",
        "shippingbox", "books.vertical", "book", "book.closed", "bookmark", "paperclip", "note.text",
        // Development
        "hammer", "wrench.and.screwdriver", "terminal", "chevron.left.forwardslash.chevron.right",
        "curlybraces", "apple.terminal", "cpu", "memorychip", "server.rack", "gearshape",
        "gearshape.2", "puzzlepiece", "ladybug", "ant", "flask", "testtube.2", "cube", "square.stack.3d.up",
        "point.3.connected.trianglepath.dotted", "arrow.triangle.branch", "cloud", "icloud",
        // Storage and network
        "externaldrive", "internaldrive", "opticaldiscdrive", "network", "globe", "link", "lock",
        "key", "shield",
        // Media
        "photo", "photo.on.rectangle", "camera", "music.note", "music.note.list", "film", "video",
        "mic", "headphones", "paintbrush", "paintpalette", "pencil", "scribble", "scissors",
        // Work and life
        "briefcase", "building.2", "house", "person", "person.2", "graduationcap", "cart",
        "creditcard", "banknote", "chart.bar", "chart.pie", "calendar", "clock", "envelope",
        "tray.and.arrow.down", "arrow.down.circle", "star", "heart", "flag", "tag", "gamecontroller",
        "airplane", "car", "leaf", "sparkles", "trash",
    ]

    /// Unique names, in catalog order, that exist on this Mac.
    static let available: [String] = {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted && MappingManager.systemSymbolExists($0) }
    }()

    static func suggestions(matching query: String) -> [String] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return available }
        return available.filter { $0.contains(query) }
    }
}
