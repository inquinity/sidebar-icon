import Foundation
import SidebarIconCore

/// The manual process's helper (004 research D4b, contracts/glyph-builder.md): turns a plain SVG
/// drawn with filled shapes into an SF Symbols custom-symbol template for Import Glyph….
///
/// Exit codes: 0 written; 64 usage error; 65 the drawing was refused; 73 the output can't be written.

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let usage = """
    usage: swift run make-symbol-template <input.svg> <output.svg>

    Reads a drawing made of filled shapes (path, rect, circle, ellipse, polygon) and writes a
    symbol template with Ultralight-M, Regular-M and Black-M glyphs, sized like the system
    glyphs. Then use Import Glyph… in Sidebar Icons.
    """

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(0)
}
guard arguments.count == 2 else { fail(usage, code: 64) }

let input = URL(fileURLWithPath: arguments[0])
let output = URL(fileURLWithPath: arguments[1])
guard input.standardizedFileURL != output.standardizedFileURL else {
    fail("The output must be a different file from the input.", code: 64)
}

let drawing: SVGShapes
do {
    drawing = try SVGShapeReader.read(contentsOf: input)
} catch let error as SVGReadError {
    fail("\(input.lastPathComponent): \(error.message)", code: 65)
} catch {
    fail("\(input.lastPathComponent): \(error.localizedDescription)", code: 65)
}

do {
    try Data(SymbolTemplateWriter.template(for: drawing).utf8).write(to: output, options: .atomic)
} catch {
    fail("Can't write \(output.path): \(error.localizedDescription)", code: 73)
}

print("Wrote \(output.path): \(drawing.shapes.count) shape(s), width ratio \(String(format: "%.2f", drawing.widthRatio)).")
for warning in drawing.warnings {
    print("Warning: \(warning)")
}
