import AppKit
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// The Custom glyph tab of the style picker (contracts/ui.md): choose a glyph from the Glyph
/// Library for this folder, or make one with New Custom Glyph… (the wizard, with this folder's
/// art step); the new glyph is applied when the wizard finishes. The library window imports,
/// redraws and deletes glyphs.
struct CustomGlyphTab: View {
    let model: AppModel
    let folderName: String
    @Binding var selection: UUID?
    /// The wizard built a new glyph: use it for the folder.
    let created: (UUID) -> Void

    @State private var wizard: GlyphWizardRequest?
    @State private var xcodeProblem: String?
    /// A glyph the wizard just created, used once its sheet has closed: closing the picker in
    /// the same update as the wizard can leave a sheet stuck (review finding 3).
    @State private var createdGlyph: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.glyphs.isEmpty {
                Text("The Glyph Library is empty. New Custom Glyph… turns an SVG drawing into a glyph for \(folderName).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(model.glyphs, id: \.id, selection: $selection) { glyph in
                    HStack(spacing: 10) {
                        GlyphImage(template: model.templateURL(for: glyph)).frame(width: 20, height: 20)
                        Text(glyph.name)
                    }
                    .tag(glyph.id)
                }
                .frame(height: 120)
                if let glyph = model.glyphs.first(where: { $0.id == selection }) {
                    GlyphPreviewPair(template: model.templateURL(for: glyph), name: folderName)
                }
            }
            Button("New Custom Glyph…") {
                model.clearLastError()
                Task {
                    if let problem = await model.glyphToolProblem() {
                        xcodeProblem = problem
                    } else {
                        wizard = GlyphWizardRequest(updating: nil)
                    }
                }
            }
            .disabled(!model.canChange)
        }
        .sheet(item: $wizard, onDismiss: {
            if let id = createdGlyph {
                createdGlyph = nil
                created(id)
            }
        }) { _ in
            GlyphWizard(model: model, folderName: folderName, updating: nil,
                        finished: { id in
                            selection = id
                            createdGlyph = id
                            wizard = nil
                        },
                        cancel: {
                            wizard = nil
                            model.clearLastError()
                        })
        }
        .xcodeNeededAlert($xcodeProblem)
    }
}

/// A custom glyph drawn from its template's Regular-M glyph, tinted like the sidebar.
struct GlyphImage: View {
    let template: URL?

    var body: some View {
        if let template, let image = GlyphPreviewCache.image(for: template) {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().foregroundStyle(.tint)
        } else {
            Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

struct TemplateSample: View {
    let template: URL?
    let name: String
    let size: CGFloat
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            GlyphImage(template: template).frame(width: size, height: size)
            Text(name).font(.system(size: 13)).foregroundStyle(SidebarSwatch.text(dark: dark)).lineLimit(1)
            Text("\(Int(size)) pt").font(.caption2).foregroundStyle(SidebarSwatch.secondaryText(dark: dark))
        }
    }
}

/// Templates are stored per version and never change, so caching by path is safe.
@MainActor
enum GlyphPreviewCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for template: URL) -> NSImage? {
        if let cached = cache.object(forKey: template as NSURL) { return cached }
        guard let data = try? ContainerFile.read(template, limit: SVGShapeReader.maximumFileSize),
              let text = String(data: data, encoding: .utf8),
              let svg = SymbolTemplatePreview.svg(fromTemplate: text),
              let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: template as NSURL)
        return image
    }
}
