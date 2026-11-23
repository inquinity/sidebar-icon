import Foundation
import Testing
@testable import SidebarIconCore

func fixture(_ name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}

/// 004 T018: contracts/glyph-builder.md, SVGShapeReader.
@Suite struct SVGShapeReaderTests {
    private func refusal(_ name: String) throws -> SVGReadError? {
        do {
            _ = try SVGShapeReader.read(contentsOf: try fixture(name))
            return nil
        } catch let error as SVGReadError {
            return error
        }
    }

    @Test func readsFilledPathsWithFillRules() throws {
        let drawing = try SVGShapeReader.read(contentsOf: try fixture("layers-filled.svg"))
        #expect(drawing.shapes.map(\.fillRule) == ["evenodd", "nonzero"])
        #expect(drawing.viewBox == .init(x: 0, y: 0, width: 100, height: 100))
        #expect(drawing.widthRatio == 1)
        #expect(drawing.warnings.isEmpty)
    }

    @Test func convertsShapesInsideAPlainGroup() throws {
        let drawing = try SVGShapeReader.read(contentsOf: try fixture("shapes.svg"))
        #expect(drawing.shapes.count == 4)
        #expect(drawing.shapes[0].d == "M14 10 H36 A4 4 0 0 1 40 14 V26 A4 4 0 0 1 36 30 H14 A4 4 0 0 1 10 26 V14 A4 4 0 0 1 14 10 Z")
        #expect(drawing.shapes[1].d == "M60 20 A10 10 0 1 0 80 20 A10 10 0 1 0 60 20 Z")
        #expect(drawing.shapes[2].d == "M10 70 A15 8 0 1 0 40 70 A15 8 0 1 0 10 70 Z")
        #expect(drawing.shapes[3].d == "M60 90 L80 60 L95 90 Z")
    }

    @Test func refusesStrokesWithOutlineGuidance() throws {
        let error = try #require(try refusal("stroked.svg"))
        #expect(error.message.contains("Outline Stroke"))
    }

    @Test func refusesTextTransformsAndMissingViewBox() throws {
        #expect(try refusal("text.svg")?.message.contains("outlines") == true)
        #expect(try refusal("transform.svg")?.message.contains("transforms flattened") == true)
        #expect(try refusal("no-viewbox.svg") == .missingViewBox)
        #expect(try refusal("empty.svg") == .emptySVG)
    }

    @Test func refusesOtherUnsupportedContent() {
        let cases = [
            ##"<svg viewBox="0 0 10 10"><line x1="0" y1="0" x2="9" y2="9" stroke="#000"/></svg>"##: "Outline Stroke",
            ##"<svg viewBox="0 0 10 10"><image href="a.png"/></svg>"##: "Flatten",
            ##"<svg viewBox="0 0 10 10"><defs><linearGradient id="g"/></defs></svg>"##: "Flatten",
            ##"<svg viewBox="0 0 10 10"><path d="M0 0H9V9Z" fill="url(#g)"/></svg>"##: "Flatten",
            ##"<svg viewBox="0 0 10 10"><style>.a{fill:red}</style></svg>"##: "presentation attributes",
            ##"<svg viewBox="0 0 10 10"><path class="a" d="M0 0H9V9Z"/></svg>"##: "presentation attributes",
            ##"<svg viewBox="0 0 10 10"><g style="fill:none;stroke:#000"><rect width="5" height="5"/></g></svg>"##: "Outline Stroke",
        ]
        for (svg, guidance) in cases {
            #expect(throws: SVGReadError.self) { try SVGShapeReader.read(Data(svg.utf8)) }
            do {
                _ = try SVGShapeReader.read(Data(svg.utf8))
            } catch let error as SVGReadError {
                #expect(error.message.contains(guidance), "\(svg)")
            } catch {
                Issue.record("unexpected \(error)")
            }
        }
    }

    @Test func ignoresTitlesAndEditorMetadata() throws {
        let svg = #"""
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:sodipodi="x" viewBox="0 0 20 10">
          <sodipodi:namedview><inner/></sodipodi:namedview>
          <metadata><rdf/></metadata>
          <path d="M0 0H20V10Z" stroke="#000"/>
        </svg>
        """#
        let drawing = try SVGShapeReader.read(Data(svg.utf8))
        #expect(drawing.shapes.count == 1)
        #expect(drawing.widthRatio == 2)
        #expect(drawing.warnings.contains { $0.contains("wider") })
        #expect(drawing.warnings.contains { $0.contains("Strokes") })
    }

    @Test func refusesLargeAndUnreadableFiles() {
        #expect(throws: SVGReadError.tooLarge) { try SVGShapeReader.read(Data(count: 1_000_001)) }
        #expect(throws: SVGReadError.self) { try SVGShapeReader.read(Data("not xml".utf8)) }
        #expect(throws: SVGReadError.self) { try SVGShapeReader.read(Data("<html/>".utf8)) }
    }
}
