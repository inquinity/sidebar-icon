import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T019: contracts/glyph-builder.md, SymbolTemplateWriter.
@Suite struct SymbolTemplateWriterTests {
    private func layers() throws -> SVGShapes {
        try SVGShapeReader.read(contentsOf: try fixture("layers-filled.svg"))
    }

    @Test func isDeterministic() throws {
        #expect(SymbolTemplateWriter.template(for: try layers()) == SymbolTemplateWriter.template(for: try layers()))
    }

    @Test func hasGlyphsGuidesAndMargins() throws {
        let template = SymbolTemplateWriter.template(for: try layers())
        for id in ["Ultralight-M", "Regular-M", "Black-M", "Baseline-S", "Baseline-M", "Baseline-L",
                   "Capline-S", "Capline-M", "Capline-L", "left-margin-Regular-M", "right-margin-Regular-M"] {
            #expect(template.contains(#"id="\#(id)""#), "\(id)")
        }
        #expect(SymbolTemplateWriter.hasRequiredGlyph(template))
        #expect(!SymbolTemplateWriter.hasRequiredGlyph(try String(contentsOf: try fixture("template-s-only.svg"), encoding: .utf8)))
        #expect(SymbolTemplateWriter.hasRequiredGlyph(try String(contentsOf: try fixture("template-regular-m.svg"), encoding: .utf8)))
        // Well-formed XML.
        #expect(XMLParser(data: Data(template.utf8)).parse())
    }

    @Test func scalesTheViewBoxHeightToTheBox() throws {
        // viewBox 10 20 50 200: scale 0.75; the top edge (y 20) lands 120 above the baseline.
        let drawing = SVGShapes(shapes: [.init(d: "M10 20H60V220Z", fillRule: "nonzero")],
                                viewBox: .init(x: 10, y: 20, width: 50, height: 200), commandCount: 4, warnings: [])
        let template = SymbolTemplateWriter.template(for: drawing)
        #expect(template.contains(#"transform="matrix(0.750000 0 0 0.750000 -7.5000 -135.0000)""#))
        // Top: 20 × 0.75 − 135 = −120; bottom: 220 × 0.75 − 135 = 30.
        #expect(20 * 0.75 - 135 == SymbolTemplateWriter.boxTop)
        #expect(220 * 0.75 - 135 == SymbolTemplateWriter.boxTop + SymbolTemplateWriter.boxHeight)
        // Right margin = left + width × scale.
        #expect(template.contains(#"id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="1433.500""#))
    }

    @Test func escapesPathData() {
        let drawing = SVGShapes(shapes: [.init(d: #"M0 0 "&<"#, fillRule: "nonzero")],
                                viewBox: .init(x: 0, y: 0, width: 1, height: 1), commandCount: 1, warnings: [])
        #expect(SymbolTemplateWriter.template(for: drawing).contains(#"d="M0 0 &quot;&amp;&lt;""#))
    }
}

@Suite struct SymbolTemplatePreviewTests {
    @Test func cropsTheRegularGlyph() throws {
        let template = SymbolTemplateWriter.template(for: try SVGShapeReader.read(contentsOf: try fixture("layers-filled.svg")))
        let preview = try #require(SymbolTemplatePreview.svg(fromTemplate: template))
        #expect(preview.contains(#"viewBox="1396 1006 150 150""#))
        #expect(preview.components(separatedBy: "<path ").count - 1 == 2)
        #expect(preview.contains(#"<g transform="matrix(1 0 0 1 1396.000 1126.000)">"#))
        #expect(XMLParser(data: Data(preview.utf8)).parse())
    }

    @Test func noRegularGlyphNoPreview() throws {
        #expect(SymbolTemplatePreview.svg(fromTemplate: try String(contentsOf: try fixture("template-s-only.svg"), encoding: .utf8)) == nil)
    }
}
