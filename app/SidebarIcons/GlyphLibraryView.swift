import AppKit
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// A wizard to open: a new glyph, or a new drawing for `updating`.
struct GlyphWizardRequest: Identifiable {
    let id = UUID()
    let updating: CustomGlyph?
}

/// Shown instead of the wizard or Import when Xcode's asset tool isn't ready: what to do, and Close.
struct XcodeNeededAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Custom Glyphs Use Xcode",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { _ in
            Button("Close", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

extension View {
    func xcodeNeededAlert(_ message: Binding<String?>) -> some View {
        modifier(XcodeNeededAlert(message: message))
    }
}

/// The Glyph Library window (contracts/ui.md): every custom glyph, with sidebar previews and how
/// many folders use it. New Glyph… opens the wizard, Import Glyph… takes a symbol template,
/// New Drawing… gives the selected glyph a new version, and Delete… removes it.
struct GlyphLibraryView: View {
    @Bindable var model: AppModel

    @State private var selection: UUID?
    @State private var wizard: GlyphWizardRequest?
    @State private var importing = false
    @State private var pendingDelete: CustomGlyph?
    @State private var xcodeProblem: String?
    /// Why the last delete failed; this window's own message (import and the wizard show theirs).
    @State private var deleteError: String?

    private var selected: CustomGlyph? { model.glyphs.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            // The same notices as the main window, so disabled buttons are explained here too.
            BannerView(model: model)
            if let error = deleteError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.red.opacity(0.08))
            }
            if model.glyphs.isEmpty {
                ContentUnavailableView {
                    Label("No glyphs yet", systemImage: "square.stack")
                } description: {
                    Text("New Glyph… turns an SVG drawing into a glyph that any folder can use.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.glyphs, id: \.id, selection: $selection) { glyph in
                    HStack(spacing: 10) {
                        GlyphImage(template: model.templateURL(for: glyph)).frame(width: 20, height: 20)
                        Text(glyph.name)
                        Spacer()
                        let count = model.folderCount(using: glyph)
                        Text(count == 1 ? "1 folder" : "\(count) folders").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(glyph.id)
                    .contextMenu {
                        Group {
                            Button("New Drawing…") { openWizard(updating: glyph) }
                            Button("Delete…", role: .destructive) { pendingDelete = glyph }
                        }
                        .disabled(!model.canChange)
                    }
                }
                if let selected {
                    GlyphPreviewPair(template: model.templateURL(for: selected), name: selected.name)
                        .padding(12)
                }
            }
            Divider()
            HStack {
                Button("New Glyph…", systemImage: "plus") { openWizard(updating: nil) }
                Button("Import Glyph…") { openImport() }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("New Drawing…") { if let selected { openWizard(updating: selected) } }
                    .disabled(selected == nil)
                Button("Delete…", role: .destructive) { pendingDelete = selected }
                    .disabled(selected == nil)
            }
            .disabled(!model.canChange)
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 360)
        .sheet(item: $wizard) { request in
            GlyphWizard(model: model, folderName: nil, updating: request.updating,
                        finished: { id in
                            selection = id
                            wizard = nil
                        },
                        cancel: {
                            wizard = nil
                            model.clearLastError()
                        })
        }
        .sheet(isPresented: $importing) {
            ImportGlyphSheet(model: model) { id in
                importing = false
                if let id { selection = id }
            }
        }
        .confirmationDialog(
            "Delete glyph?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { glyph in
            Button("Delete", role: .destructive) {
                model.clearLastError()
                deleteError = nil
                model.deleteGlyph(glyph) { succeeded in
                    if succeeded {
                        if selection == glyph.id { selection = nil }
                    } else {
                        deleteError = model.lastError ?? "\(glyph.name) wasn't deleted; another action was running. Try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { glyph in
            let count = model.folderCount(using: glyph)
            Text(count == 0
                 ? "Delete the glyph \(glyph.name) from the library?"
                 : "\(count == 1 ? "1 folder uses" : "\(count) folders use") \(glyph.name). Deleting it gives \(count == 1 ? "that folder" : "them") the standard folder glyph.")
        }
        .xcodeNeededAlert($xcodeProblem)
    }

    private func openWizard(updating: CustomGlyph?) {
        model.clearLastError()
        deleteError = nil
        Task {
            if let problem = await model.glyphToolProblem() {
                xcodeProblem = problem
            } else {
                wizard = GlyphWizardRequest(updating: updating)
            }
        }
    }

    private func openImport() {
        model.clearLastError()
        deleteError = nil
        Task {
            if let problem = await model.glyphToolProblem() {
                xcodeProblem = problem
            } else {
                importing = true
            }
        }
    }
}

/// Import Glyph…: a name and a symbol template from make-symbol-template or the SF Symbols app
/// (icon-specification.md, Manual process).
private struct ImportGlyphSheet: View {
    let model: AppModel
    /// The imported glyph's id, or nil when cancelled.
    let done: (UUID?) -> Void

    @State private var name = ""
    @State private var template: URL?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Glyph").font(.headline)
            Text("A symbol template from make-symbol-template or the SF Symbols app, with a Regular-M glyph.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Glyph name, for example git-repo", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if !trimmedName.isEmpty, !CustomGlyph.isValidName(trimmedName) {
                Text("Use lowercase letters, digits, dots and hyphens, starting with a letter or digit.")
                    .font(.caption).foregroundStyle(.red)
            } else if model.glyphs.contains(where: { $0.name == trimmedName }) {
                Text("Importing gives \(trimmedName) a new version; every folder that uses it shows the new drawing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(template == nil ? "Choose Template…" : "Change Template…") {
                    if let url = Self.chooseTemplate() { template = url }
                }
                if let template {
                    Text(template.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    model.clearLastError()
                    done(nil)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Import") { importTemplate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(template == nil || !CustomGlyph.isValidName(trimmedName) || !model.canChange)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func importTemplate() {
        guard let template else { return }
        let name = trimmedName
        let before = Set(model.glyphs.map(\.versionID))
        model.clearLastError()
        model.importGlyph(name: name, template: template) { succeeded in
            guard succeeded else { return }
            done(model.glyphs.first { $0.name == name && !before.contains($0.versionID) }?.id)
        }
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

/// A glyph on a light and a dark sidebar swatch, at 16 and 20 pt.
struct GlyphPreviewPair: View {
    let template: URL?
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach([false, true], id: \.self) { dark in
                VStack(alignment: .leading, spacing: 6) {
                    TemplateSample(template: template, name: name, size: 16, dark: dark)
                    TemplateSample(template: template, name: name, size: 20, dark: dark)
                }
                .padding(10)
                .frame(width: 200, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(SidebarSwatch.fill(dark: dark)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .environment(\.colorScheme, dark ? .dark : .light)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(dark ? "Preview on a dark sidebar" : "Preview on a light sidebar")
            }
        }
    }
}
