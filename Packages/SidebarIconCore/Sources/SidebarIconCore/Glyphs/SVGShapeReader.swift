import Foundation

/// The filled shapes of a plain SVG drawing, ready for a symbol template (004 research D4,
/// contracts/glyph-builder.md).
public struct SVGShapes: Sendable, Equatable {
    public struct Shape: Sendable, Equatable {
        /// Path data in the drawing's own coordinates.
        public var d: String
        /// `nonzero` or `evenodd`.
        public var fillRule: String
    }

    public struct ViewBox: Sendable, Equatable {
        public var x, y, width, height: Double
    }

    public var shapes: [Shape]
    public var viewBox: ViewBox
    /// The number of path commands, a rough measure of detail.
    public var commandCount: Int
    /// Things that won't stop a build but may look poor in the sidebar.
    public var warnings: [String]

    /// Width over height of the drawing; the sidebar slot is about square.
    public var widthRatio: Double { viewBox.width / viewBox.height }
}

/// Why a drawing can't become a glyph. Each message says what to change.
public enum SVGReadError: Error, Equatable, Sendable {
    case unsupportedSVG(String)
    case emptySVG
    case missingViewBox
    case unreadable(String)
    case tooLarge

    public static let strokeGuidance = "Convert strokes to shapes: Outline Stroke / Stroke to Path in your drawing app."
    public static let textGuidance = "Convert text to outlines."
    public static let flattenGuidance = "Flatten to plain filled shapes."
    public static let transformGuidance = "Export with transforms flattened."
    public static let cssGuidance = "Export with presentation attributes instead of CSS styles."

    public var message: String {
        switch self {
        case .unsupportedSVG(let detail): detail
        case .emptySVG: "The drawing has no filled shapes."
        case .missingViewBox: "The drawing needs a viewBox on its <svg> element (most editors add one with \"Responsive\" or \"viewBox\" export options)."
        case .unreadable(let detail): "The file isn't a readable SVG: \(detail)."
        case .tooLarge: "The file is larger than 1 MB; a glyph drawing should be much smaller."
        }
    }
}

/// Reads the owner's SVG into filled path data, refusing anything a symbol template can't hold.
public enum SVGShapeReader {
    public static let maximumFileSize = 1_000_000
    static let detailWarningCommands = 400

    public static func read(contentsOf url: URL) throws -> SVGShapes {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SVGReadError.unreadable(error.localizedDescription)
        }
        return try read(data)
    }

    public static func read(_ data: Data) throws -> SVGShapes {
        guard data.count <= maximumFileSize else { throw SVGReadError.tooLarge }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        let collector = Collector()
        parser.delegate = collector
        let parsed = parser.parse()
        if let refusal = collector.refusal { throw refusal }
        guard parsed else {
            throw SVGReadError.unreadable(parser.parserError?.localizedDescription ?? "parse error")
        }
        guard collector.sawRoot else { throw SVGReadError.unreadable("no <svg> element") }
        guard let viewBox = collector.viewBox else { throw SVGReadError.missingViewBox }
        guard !collector.shapes.isEmpty else { throw SVGReadError.emptySVG }

        let commands = collector.shapes.reduce(0) { $0 + commandCount($1.d) }
        var result = SVGShapes(shapes: collector.shapes, viewBox: viewBox, commandCount: commands, warnings: [])
        if result.widthRatio > 1.25 {
            result.warnings.append("The drawing is much wider than tall, so it will look small in the sidebar.")
        } else if result.widthRatio < 0.8 {
            result.warnings.append("The drawing is much taller than wide, so it will look narrow in the sidebar.")
        }
        if commands > detailWarningCommands {
            result.warnings.append("The drawing is very detailed; fine detail blurs at 16 pt.")
        }
        if collector.ignoredStrokes {
            result.warnings.append("Strokes on filled shapes are ignored; only fills are used.")
        }
        return result
    }

    static func commandCount(_ d: String) -> Int {
        d.reduce(0) { $0 + ("MmLlHhVvCcSsQqTtAaZz".contains($1) ? 1 : 0) }
    }

    /// Formats a number compactly and deterministically (no exponent, at most 4 decimals).
    static func format(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// XMLParser delegate that collects shapes and the first refusal.
    private final class Collector: NSObject, XMLParserDelegate {
        struct Paint { var fill: String?; var stroke: String?; var fillRule: String?; var hidden = false }

        var shapes: [SVGShapes.Shape] = []
        var viewBox: SVGShapes.ViewBox?
        var refusal: SVGReadError?
        var sawRoot = false
        var ignoredStrokes = false
        /// Inherited presentation attributes, one entry per open element.
        private var paintStack: [Paint] = []
        /// Depth inside an ignored element (`title`, `desc`, `metadata`, editor namespaces).
        private var ignoredDepth = 0

        /// Never drawn, so their contents are skipped (a gradient in `defs` is refused only when a
        /// shape is filled with it).
        private static let ignoredElements: Set<String> = ["title", "desc", "metadata", "defs"]
        private static let flattenElements: Set<String> = [
            "image", "use", "pattern", "linearGradient", "radialGradient", "mask", "clipPath", "filter",
            "symbol", "foreignObject", "marker", "switch", "a", "svg-nested",
        ]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard refusal == nil else { return }
            if ignoredDepth > 0 || Self.ignoredElements.contains(name) || name.contains(":") {
                ignoredDepth += 1
                return
            }
            if !sawRoot {
                guard name == "svg" else { return refuse(parser, .unreadable("the root element is <\(name)>, not <svg>")) }
                sawRoot = true
                viewBox = Self.parseViewBox(attributes["viewBox"])
            } else if name == "svg" {
                return refuse(parser, .unsupportedSVG("A nested <svg> element isn't supported. \(SVGReadError.flattenGuidance)"))
            }
            if attributes["transform"] != nil || attributes["style"]?.contains("transform") == true {
                return refuse(parser, .unsupportedSVG("<\(name)> has a transform. \(SVGReadError.transformGuidance)"))
            }
            if attributes["class"] != nil {
                return refuse(parser, .unsupportedSVG("<\(name)> is styled with a CSS class. \(SVGReadError.cssGuidance)"))
            }
            var paint = paintStack.last ?? Paint()
            Self.apply(attributes, to: &paint)
            paintStack.append(paint)

            switch name {
            case "svg", "g":
                return
            case "line", "polyline":
                return refuse(parser, .unsupportedSVG("<\(name)> is a stroke. \(SVGReadError.strokeGuidance)"))
            case "text", "tspan", "textPath":
                return refuse(parser, .unsupportedSVG("The drawing contains text. \(SVGReadError.textGuidance)"))
            case "style":
                return refuse(parser, .unsupportedSVG("The drawing uses a <style> element. \(SVGReadError.cssGuidance)"))
            case "path", "rect", "circle", "ellipse", "polygon":
                addShape(parser, name: name, attributes: attributes, paint: paint)
            default:
                if Self.flattenElements.contains(name) {
                    return refuse(parser, .unsupportedSVG("<\(name)> isn't supported. \(SVGReadError.flattenGuidance)"))
                }
                return refuse(parser, .unsupportedSVG("<\(name)> isn't supported. \(SVGReadError.flattenGuidance)"))
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if ignoredDepth > 0 {
                ignoredDepth -= 1
            } else if !paintStack.isEmpty {
                paintStack.removeLast()
            }
        }

        private func refuse(_ parser: XMLParser, _ error: SVGReadError) {
            if refusal == nil { refusal = error }
            parser.abortParsing()
        }

        private func addShape(_ parser: XMLParser, name: String, attributes: [String: String], paint: Paint) {
            if paint.hidden { return }  // display="none", hidden or fully transparent: not drawn.
            let fill = (paint.fill ?? "black").trimmingCharacters(in: .whitespaces)
            let stroke = (paint.stroke ?? "none").trimmingCharacters(in: .whitespaces)
            let hasStroke = stroke != "none" && stroke != "transparent"
            if fill == "none" || fill == "transparent" {
                if hasStroke {
                    refuse(parser, .unsupportedSVG("<\(name)> is drawn with a stroke and no fill. \(SVGReadError.strokeGuidance)"))
                }
                return  // Invisible: nothing to draw.
            }
            if fill.hasPrefix("url(") {
                return refuse(parser, .unsupportedSVG("<\(name)> is filled with a gradient or pattern. \(SVGReadError.flattenGuidance)"))
            }
            if hasStroke { ignoredStrokes = true }
            guard let d = Self.pathData(name, attributes), !d.isEmpty else {
                return refuse(parser, .unsupportedSVG("<\(name)> is missing its size or points. \(SVGReadError.flattenGuidance)"))
            }
            let rule = paint.fillRule == "evenodd" ? "evenodd" : "nonzero"
            shapes.append(.init(d: d, fillRule: rule))
        }

        /// Presentation attributes and the inline `style` declarations that matter here.
        private static func apply(_ attributes: [String: String], to paint: inout Paint) {
            var values = attributes
            if let style = attributes["style"] {
                for declaration in style.split(separator: ";") {
                    let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 { values[parts[0]] = parts[1] }
                }
            }
            if let fill = values["fill"] { paint.fill = fill }
            if values["display"] == "none" || ["hidden", "collapse"].contains(values["visibility"] ?? "")
                || values["opacity"].flatMap(Double.init) == 0 || values["fill-opacity"].flatMap(Double.init) == 0 {
                paint.hidden = true
            } else if values["visibility"] == "visible" {
                paint.hidden = false
            }
            if let stroke = values["stroke"] { paint.stroke = stroke }
            if let rule = values["fill-rule"] { paint.fillRule = rule }
        }

        static func parseViewBox(_ text: String?) -> SVGShapes.ViewBox? {
            guard let text else { return nil }
            let numbers = SVGShapeReader.numbers(in: text)
            guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
            return .init(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }

        static func pathData(_ name: String, _ a: [String: String]) -> String? {
            // Plain numbers or pixels; other units can't be placed in the viewBox.
            func number(_ key: String) -> Double? {
                guard var text = a[key]?.trimmingCharacters(in: .whitespaces) else { return nil }
                if text.hasSuffix("px") { text.removeLast(2) }
                return Double(text).flatMap { $0.isFinite ? $0 : nil }
            }
            let f = SVGShapeReader.format
            switch name {
            case "path":
                return a["d"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            case "rect":
                guard let width = number("width"), let height = number("height"), width > 0, height > 0 else { return nil }
                let x = number("x") ?? 0, y = number("y") ?? 0
                var rx = number("rx"), ry = number("ry")
                if rx == nil { rx = ry }
                if ry == nil { ry = rx }
                let cornerX = min(max(rx ?? 0, 0), width / 2), cornerY = min(max(ry ?? 0, 0), height / 2)
                if cornerX == 0 || cornerY == 0 {
                    return "M\(f(x)) \(f(y)) H\(f(x + width)) V\(f(y + height)) H\(f(x)) Z"
                }
                let arc = "A\(f(cornerX)) \(f(cornerY)) 0 0 1"
                return "M\(f(x + cornerX)) \(f(y)) H\(f(x + width - cornerX)) \(arc) \(f(x + width)) \(f(y + cornerY)) "
                    + "V\(f(y + height - cornerY)) \(arc) \(f(x + width - cornerX)) \(f(y + height)) "
                    + "H\(f(x + cornerX)) \(arc) \(f(x)) \(f(y + height - cornerY)) "
                    + "V\(f(y + cornerY)) \(arc) \(f(x + cornerX)) \(f(y)) Z"
            case "circle":
                guard let r = number("r"), r > 0 else { return nil }
                return ellipse(cx: number("cx") ?? 0, cy: number("cy") ?? 0, rx: r, ry: r)
            case "ellipse":
                guard let rx = number("rx"), let ry = number("ry"), rx > 0, ry > 0 else { return nil }
                return ellipse(cx: number("cx") ?? 0, cy: number("cy") ?? 0, rx: rx, ry: ry)
            case "polygon":
                let values = SVGShapeReader.numbers(in: a["points"] ?? "")
                guard values.count >= 6, values.count.isMultiple(of: 2) else { return nil }
                var d = "M\(f(values[0])) \(f(values[1]))"
                for index in stride(from: 2, to: values.count, by: 2) {
                    d += " L\(f(values[index])) \(f(values[index + 1]))"
                }
                return d + " Z"
            default:
                return nil
            }
        }

        static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> String {
            let f = SVGShapeReader.format
            let arc = "A\(f(rx)) \(f(ry)) 0 1 0"
            return "M\(f(cx - rx)) \(f(cy)) \(arc) \(f(cx + rx)) \(f(cy)) \(arc) \(f(cx - rx)) \(f(cy)) Z"
        }
    }

    /// The numbers in an SVG list (`points`, `viewBox`), including compact forms such as
    /// `10-5` or `.5.5`.
    static func numbers(in text: String) -> [Double] {
        text.matches(of: /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/).compactMap { Double(text[$0.range]) }
    }
}
