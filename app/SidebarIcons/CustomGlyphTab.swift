import AppKit
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// The Custom glyph tab (contracts/ui.md, 004 Story 2): the owner's glyphs with tinted previews,
/// Import Glyph… (name and template) and Delete…. Shows why when Xcode's asset tool is missing.
struct CustomGlyphTab: View {
    let model: AppModel
    let folderName: String
    @Binding var selection: UUID?

    @State private var importing = false
    @State private var newName = ""
    @State private var template: URL?
    @State private var pendingDelete: CustomGlyph?

    private var toolUnavailableReason: String? {
        if case .unavailable(let reason)? = model.glyphToolStatus { reason } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let reason = toolUnavailableReason {
                Label(reason, systemImage: "hammer.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.glyphs.isEmpty {
                Text("No custom glyphs yet. Make a template with make-symbol-template (see icon-specification.md, Manual process), then import it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(model.glyphs, id: \.id, selection: $selection) { glyph in
                    HStack(spacing: 10) {
                        GlyphImage(template: model.templateURL(for: glyph)).frame(width: 20, height: 20)
                        Text(glyph.name)
                        Spacer()
                        let count = model.folderCount(using: glyph)
                        if count > 0 {
                            Text(count == 1 ? "1 folder" : "\(count) folders").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(glyph.id)
                    .contextMenu { Button("Delete…", role: .destructive) { pendingDelete = glyph } }
                }
                .frame(height: 120)
                if let glyph = model.glyphs.first(where: { $0.id == selection }) {
                    HStack(spacing: 12) {
                        ForEach([false, true], id: \.self) { dark in
                            VStack(alignment: .leading, spacing: 6) {
                                TemplateSample(template: model.templateURL(for: glyph), name: folderName, size: 16, dark: dark)
                                TemplateSample(template: model.templateURL(for: glyph), name: folderName, size: 20, dark: dark)
                            }
                            .padding(10)
                            .frame(width: 200, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(SidebarSwatch.fill(dark: dark)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                            .environment(\.colorScheme, dark ? .dark : .light)
                        }
                    }
                }
            }

            if importing {
                importForm
            } else {
                HStack {
                    Button("Import Glyph…") {
                        importing = true
                        newName = ""
                        template = nil
                    }
                    .disabled(toolUnavailableReason != nil || !model.canChange)
                    if let glyph = model.glyphs.first(where: { $0.id == selection }) {
                        Button("Delete…", role: .destructive) { pendingDelete = glyph }
                            .disabled(!model.canChange)
                    }
                }
            }
        }
        .task { if model.glyphToolStatus == nil { await model.checkGlyphTool() } }
        .onChange(of: model.glyphs) { _, glyphs in
            // Select a glyph just imported under the typed name.
            if let imported = glyphs.first(where: { $0.name == newName.trimmingCharacters(in: .whitespaces) }) {
                selection = imported.id
                importing = false
            }
        }
        .confirmationDialog("Delete glyph?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { glyph in
            Button("Delete", role: .destructive) {
                if selection == glyph.id { selection = nil }
                model.deleteGlyph(glyph)
            }
            Button("Cancel", role: .cancel) {}
        } message: { glyph in
            let count = model.folderCount(using: glyph)
            Text(count == 0
                 ? "Delete the glyph \(glyph.name)?"
                 : "\(count == 1 ? "1 folder uses" : "\(count) folders use") \(glyph.name); they will show the system folder glyph instead.")
        }
    }

    private var importForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Glyph name, for example git-repo", text: $newName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            HStack {
                Button(template == nil ? "Choose Template…" : "Choose Another Template…") {
                    template = Self.chooseTemplate()
                }
                if let template {
                    Text(template.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            if !newName.isEmpty, !CustomGlyph.isValidName(newName.trimmingCharacters(in: .whitespaces)) {
                Text("Use lowercase letters, digits, dots and hyphens, starting with a letter or digit.")
                    .font(.caption).foregroundStyle(.red)
            } else if model.glyphs.contains(where: { $0.name == newName.trimmingCharacters(in: .whitespaces) }) {
                Text("This replaces the existing glyph with a new version.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { importing = false }
                Button("Import") {
                    if let template { model.importGlyph(name: newName, template: template) }
                }
                .disabled(template == nil || !CustomGlyph.isValidName(newName.trimmingCharacters(in: .whitespaces)) || !model.canChange)
                if model.busy { ProgressView().controlSize(.small) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
    }

    static func chooseTemplate() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Symbol Template"
        panel.message = "Choose a template from make-symbol-template or the SF Symbols app (it needs a Regular-M glyph)."
        panel.prompt = "Choose Template"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.svg]
        return panel.runModal() == .OK ? panel.url : nil
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

private struct TemplateSample: View {
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
        guard let text = try? String(contentsOf: template, encoding: .utf8),
              let svg = SymbolTemplatePreview.svg(fromTemplate: text),
              let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: template as NSURL)
        return image
    }
}
