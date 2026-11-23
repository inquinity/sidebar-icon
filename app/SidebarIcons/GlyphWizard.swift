import AppKit
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// The glyph wizard (contracts/ui.md, 004 Story 3): a plain SVG drawing in, a custom glyph out,
/// without running make-symbol-template. Steps: tool check, name, drawing, folder art (not yet
/// available), preview, build. Nothing is saved until Build, and a failed build saves nothing.
///
/// With `updating`, it gives an existing glyph a new drawing (a new version): the name step is
/// skipped and every folder using the glyph shows the new drawing.
struct GlyphWizard: View {
    enum Step: Int, CaseIterable {
        case check, name, drawing, folderArt, preview, build

        var title: String {
            switch self {
            case .check: "Xcode"
            case .name: "Name"
            case .drawing: "Drawing"
            case .folderArt: "Folder art"
            case .preview: "Preview"
            case .build: "Build"
            }
        }
    }

    let model: AppModel
    let folderName: String
    let updating: CustomGlyph?
    /// Called with the glyph's id after a successful build.
    let finished: (UUID) -> Void
    let useSystemGlyph: () -> Void
    let cancel: () -> Void

    @State private var step: Step = .check
    @State private var name = ""
    @State private var drawingURL: URL?
    @State private var drawing: Result<SVGShapes, SVGReadError>?
    /// The bytes that were read and previewed; Build uses exactly these (review finding 4).
    @State private var drawingData: Data?
    @State private var preview: NSImage?
    @State private var reading = false
    @State private var building = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameProblem: String? {
        if trimmedName.isEmpty { return nil }
        if !CustomGlyph.isValidName(trimmedName) {
            return "Use lowercase letters, digits, dots and hyphens (up to 48), starting with a letter or digit."
        }
        if model.glyphs.contains(where: { $0.name == trimmedName }) {
            return "You already have a glyph named \(trimmedName). Choose another name, or select that glyph and click New Drawing…"
        }
        return nil
    }

    private var shapes: SVGShapes? {
        if case .success(let shapes)? = drawing { shapes } else { nil }
    }

    private var steps: [Step] { updating == nil ? Step.allCases : Step.allCases.filter { $0 != .name } }

    private var canContinue: Bool {
        switch step {
        case .check: if case .available? = model.glyphToolStatus { true } else { false }
        case .name: !trimmedName.isEmpty && nameProblem == nil
        case .drawing: shapes != nil && drawingData != nil && !reading
        case .folderArt, .preview: true
        case .build: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(updating.map { "New drawing for \($0.name)" } ?? "New Custom Glyph").font(.headline)
            stepIndicator
            Group {
                switch step {
                case .check: checkStep
                case .name: nameStep
                case .drawing: drawingStep
                case .folderArt: folderArtStep
                case .preview: previewStep
                case .build: buildStep
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)

            if let error = model.lastError, step == .build || step == .check {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(building)
                Spacer()
                if step != steps.first {
                    Button("Back") { move(by: -1) }.disabled(building)
                }
                if step == .build {
                    Button("Build Glyph", action: build)
                        .keyboardShortcut(.defaultAction)
                        .disabled(building || !model.canChange || shapes == nil)
                } else {
                    Button("Continue") { move(by: 1) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .task { await model.checkGlyphTool() }
    }

    // MARK: - Steps

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, each in
                Text("\(index + 1) \(each.title)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(each == step ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear)))
                    .foregroundStyle(each == step ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count): \(step.title)")
    }

    @ViewBuilder private var checkStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.glyphToolStatus {
            case nil:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for Xcode's asset tool…")
                }
            case .available(let tool)?:
                Label("Xcode's asset tool is available.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(tool.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Next you'll name the glyph and choose an SVG drawing made of filled shapes.")
                    .font(.callout).foregroundStyle(.secondary)
            case .unavailable(let reason)?:
                Label(reason, systemImage: "hammer.circle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Custom glyphs need Xcode. Without it, a system glyph gives the same outline-blue look.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Use a System Glyph Instead", action: useSystemGlyph)
                    Button("Check Again") { Task { await model.checkGlyphTool() } }
                }
                Text("Once Xcode is installed, you can also make a template by hand: see Manual process in icon-specification.md.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The name identifies the glyph in this app; it isn't shown in Finder.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Glyph name, for example git-repo", text: $name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { if canContinue { move(by: 1) } }
            if let nameProblem {
                Text(nameProblem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var drawingStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an SVG made only of filled shapes, about square. Strokes, text, images and transforms are refused, with what to change.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(drawingURL == nil ? "Choose Drawing…" : "Choose Another Drawing…") {
                    if let url = Self.chooseDrawing() { read(url) }
                }
                .disabled(reading)
                if reading { ProgressView().controlSize(.small) }
                if let drawingURL {
                    Text(drawingURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            switch drawing {
            case .failure(let error)?:
                Label(error.message, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .success(let shapes)?:
                Label("\(shapes.shapes.count) filled shape\(shapes.shapes.count == 1 ? "" : "s"), width ratio \(String(format: "%.2f", shapes.widthRatio)).",
                      systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                ForEach(shapes.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case nil:
                EmptyView()
            }
        }
    }

    private var folderArtStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Also use full-colour art for this folder's Finder icon", isOn: .constant(false))
                .disabled(true)
            Text("Not available yet: folder icons come in a later update. The sidebar glyph doesn't need it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var previewStep: some View {
        if shapes != nil {
            let image = preview
            VStack(alignment: .leading, spacing: 10) {
                Text("How it will look in the sidebar, next to a system glyph for size.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach([false, true], id: \.self) { dark in
                        VStack(alignment: .leading, spacing: 6) {
                            DrawingSample(image: image, name: displayName, size: 16, dark: dark)
                            DrawingSample(image: image, name: displayName, size: 20, dark: dark)
                            GlyphSample(symbol: "folder", name: "Documents", size: 20, dark: dark)
                        }
                        .padding(10)
                        .frame(width: 210, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(SidebarSwatch.fill(dark: dark)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(dark ? "Preview on a dark sidebar" : "Preview on a light sidebar")
                    }
                }
            }
        }
    }

    private var buildStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let updating {
                Text("Build the new drawing for \(updating.name). Every folder that uses it shows the new drawing; Finder doesn't need a restart.")
            } else {
                Text("Build the glyph \(trimmedName) and use it for \(folderName).")
            }
            Text("This runs Xcode's asset tool and can take a few seconds. If it fails, nothing is saved.")
                .font(.callout).foregroundStyle(.secondary)
            if building {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Building…")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var displayName: String { folderName }

    private func move(by offset: Int) {
        guard let index = steps.firstIndex(of: step) else { return }
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        model.clearLastError()
        step = steps[target]
    }

    /// Reads off the main actor with the reader's 1 MB bound, so a huge or special file can't
    /// hang the window (review finding 1). The preview image is made once here.
    private func read(_ url: URL) {
        drawingURL = url
        drawing = nil
        drawingData = nil
        preview = nil
        reading = true
        Task {
            let outcome = await Task.detached { () -> Result<(Data, SVGShapes), SVGReadError> in
                do {
                    let data = try SVGShapeReader.boundedData(contentsOf: url)
                    return .success((data, try SVGShapeReader.read(data)))
                } catch let error as SVGReadError {
                    return .failure(error)
                } catch {
                    return .failure(.unreadable(error.localizedDescription))
                }
            }.value
            // A later choice replaces this one.
            guard drawingURL == url else { return }
            reading = false
            switch outcome {
            case .success(let (data, shapes)):
                drawingData = data
                drawing = .success(shapes)
                preview = Self.previewImage(for: shapes)
            case .failure(let error):
                drawing = .failure(error)
            }
        }
    }

    private func build() {
        guard let drawingData else { return }
        building = true
        let completion: @MainActor (UUID?) -> Void = { id in
            building = false
            if let id { finished(id) }
        }
        if let updating {
            model.updateGlyph(updating, drawing: drawingData, completion: completion)
        } else {
            model.createGlyph(name: trimmedName, drawing: drawingData, completion: completion)
        }
    }

    static func chooseDrawing() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Glyph Drawing"
        panel.message = "Choose an SVG drawing made of filled shapes."
        panel.prompt = "Choose Drawing"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.svg]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The drawing as the sidebar will draw it: through the same template the build uses, cropped
    /// to its Regular-M glyph.
    static func previewImage(for shapes: SVGShapes) -> NSImage? {
        guard let svg = SymbolTemplatePreview.svg(fromTemplate: SymbolTemplateWriter.template(for: shapes)),
              let image = NSImage(data: Data(svg.utf8)) else { return nil }
        image.isTemplate = true
        return image
    }
}

private struct DrawingSample: View {
    let image: NSImage?
    let name: String
    let size: CGFloat
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().foregroundStyle(.tint)
                } else {
                    Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            Text(name).font(.system(size: 13)).foregroundStyle(SidebarSwatch.text(dark: dark)).lineLimit(1)
            Text("\(Int(size)) pt").font(.caption2).foregroundStyle(SidebarSwatch.secondaryText(dark: dark))
        }
    }
}
