import Foundation

/// A small SVG of a template's `Regular-M` glyph, cropped to its 150-unit box, for previews in
/// the app (drawn as a template image, tinted with the accent colour). Works for templates from
/// `make-symbol-template` and from the SF Symbols app. Nothing here is registered or cached by
/// path, so a new version always previews correctly.
public enum SymbolTemplatePreview {
    public static func svg(fromTemplate template: String) -> String? {
        let collector = Collector()
        let parser = XMLParser(data: Data(template.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        guard parser.parse(), !collector.paths.isEmpty else { return nil }

        let baseline = collector.baselineM ?? 1126
        let left = collector.leftMargin ?? collector.groupX ?? 1396
        let right = collector.rightMargin ?? left + 150
        let width = max(right - left, 1)
        let f = SVGShapeReader.format
        var lines = [#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="\#(f(left)) \#(f(baseline - 120)) \#(f(width)) 150">"#]
        lines.append(#"<g transform="\#(SymbolTemplateWriter.escape(collector.groupTransform ?? ""))">"#)
        for path in collector.paths {
            var attributes = #"d="\#(SymbolTemplateWriter.escape(path.d))""#
            if let transform = path.transform { attributes += #" transform="\#(SymbolTemplateWriter.escape(transform))""# }
            if let rule = path.fillRule { attributes += #" fill-rule="\#(SymbolTemplateWriter.escape(rule))""# }
            lines.append("<path \(attributes)/>")
        }
        lines += ["</g>", "</svg>"]
        return lines.joined(separator: "\n")
    }

    private final class Collector: NSObject, XMLParserDelegate {
        struct Path { var d: String; var transform: String?; var fillRule: String? }
        var paths: [Path] = []
        var groupTransform: String?
        var groupX: Double?
        var baselineM: Double?
        var leftMargin: Double?
        var rightMargin: Double?
        private var depthInGlyph = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let id = attributes["id"]
            if depthInGlyph > 0 {
                depthInGlyph += 1
                if name == "path", let d = attributes["d"] {
                    paths.append(.init(d: d, transform: attributes["transform"], fillRule: attributes["fill-rule"]))
                }
                return
            }
            switch (name, id) {
            case ("g", "Regular-M"?):
                depthInGlyph = 1
                groupTransform = attributes["transform"]
                if let transform = groupTransform, transform.hasPrefix("matrix(") {
                    let numbers = SVGShapeReader.numbers(in: String(transform.dropFirst(7).dropLast()))
                    if numbers.count == 6 { groupX = numbers[4] }
                }
            case ("line", "Baseline-M"?):
                baselineM = attributes["y1"].flatMap(Double.init)
            case ("line", "left-margin-Regular-M"?):
                leftMargin = attributes["x1"].flatMap(Double.init)
            case ("line", "right-margin-Regular-M"?):
                rightMargin = attributes["x1"].flatMap(Double.init)
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if depthInGlyph > 0 { depthInGlyph -= 1 }
        }
    }
}
