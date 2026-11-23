import Foundation

/// Writes the temporary asset catalog for a glyph build (004 contracts/glyph-builder.md):
/// `Glyphs.xcassets` with one `<name>.<version>.symbolset` per glyph.
public enum AssetCatalogWriter {
    /// One glyph and the template file it is built from.
    public struct Item: Sendable {
        public var symbolName: String
        public var template: URL

        public init(symbolName: String, template: URL) {
            self.symbolName = symbolName
            self.template = template
        }
    }

    static let catalogContents = #"{"info":{"author":"xcode","version":1}}"#

    /// Checks each template has a `Regular-M` glyph, then writes the catalog at `catalog`.
    public static func write(_ items: [Item], to catalog: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: catalog, withIntermediateDirectories: true)
        try Data(catalogContents.utf8).write(to: catalog.appending(path: "Contents.json"))
        for item in items {
            let template: String
            do {
                template = try String(contentsOf: item.template, encoding: .utf8)
            } catch {
                throw GlyphBuildError.templateUnreadable(item.template.lastPathComponent)
            }
            guard SymbolTemplateWriter.hasRequiredGlyph(template) else {
                throw GlyphBuildError.missingRequiredGlyph(item.symbolName)
            }
            let set = catalog.appending(path: "\(item.symbolName).symbolset", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: set, withIntermediateDirectories: true)
            try Data(template.utf8).write(to: set.appending(path: "\(item.symbolName).svg"))
            let contents: [String: Any] = [
                "info": ["author": "xcode", "version": 1],
                "symbols": [["filename": "\(item.symbolName).svg", "idiom": "universal"]],
                "properties": ["template-rendering-intent": "template"],
            ]
            try JSONSerialization.data(withJSONObject: contents, options: [.sortedKeys])
                .write(to: set.appending(path: "Contents.json"))
        }
    }
}
