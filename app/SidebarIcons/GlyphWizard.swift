import AppKit
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// The glyph wizard (contracts/ui.md, 004 Story 3): a plain SVG drawing in, a custom glyph out,
/// without running make-symbol-template. Steps: name, drawing, folder art (only when opened for a
/// folder), preview, build. Nothing is saved until Build, and a failed build saves nothing.
/// Callers open it only once Xcode's asset tool is available (`XcodeNeededAlert`).
///
/// With `updating`, it gives an existing glyph a new drawing (a new version): the name step is
/// skipped and every folder using the glyph shows the new drawing.
struct GlyphWizard: View {
    enum Step: Int, CaseIterable {
        case name, drawing, folderArt, preview, build

        var title: String {
            switch self {
            case .name: "Name"
            case .drawing: "Drawing"
            case .folderArt: "Folder art"
            case .preview: "Preview"
            case .build: "Build"
            }
        }
    }

    let model: AppModel
    /// The folder the glyph is for (from the style picker), or nil from the Glyph Library.
    let folderName: String?
    let updating: CustomGlyph?
    /// Called with the glyph's id after a successful build.
    let finished: (UUID) -> Void
    let cancel: () -> Void

    @State private var step: Step = .name
    @State private var name = ""
    @State private var drawingURL: URL?
    @State private var drawing: Result<SVGShapes, SVGReadError>?
    /// The bytes that were read and previewed; Build uses exactly these (review finding 4).
    @State private var drawingData: Data?
    @State private var preview: NSImage?
    @State private var reading = false
    @State private var building = false
    @State private var folderArt: URL?
    @State private var folderArtProblem: String?
    /// The chosen art is still being checked; Continue waits for it (review 7).
    @State private var checkingArt = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var nameProblem: String? {
        if trimmedName.isEmpty { return nil }
        if !CustomGlyph.isValidName(trimmedName) {
            return "Use lowercase letters, digits, dots and hyphens (up to 48), starting with a letter or digit."
        }
        if model.glyphs.contains(where: { $0.name == trimmedName }) {
            return "The Glyph Library has a glyph named \(trimmedName). Choose another name, or give it a new drawing in the Glyph Library."
        }
        return nil
    }

    private var shapes: SVGShapes? {
        if case .success(let shapes)? = drawing { shapes } else { nil }
    }

    /// A new drawing keeps the glyph's name, and folder art belongs to a folder, not a glyph.
    private var steps: [Step] {
        Step.allCases.filter { each in
            switch each {
            case .name: updating == nil
            case .folderArt: updating == nil && folderName != nil
            default: true
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .name: !trimmedName.isEmpty && nameProblem == nil
        case .drawing: shapes != nil && drawingData != nil && !reading
        case .folderArt: folderArt != nil && folderArtProblem == nil && !checkingArt
        case .preview: true
        case .build: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(updating.map { "New Drawing for \($0.name)" } ?? "New Glyph").font(.headline)
            stepIndicator
            Group {
                switch step {
                case .name: nameStep
                case .drawing: drawingStep
                case .folderArt: folderArtStep
                case .preview: previewStep
                case .build: buildStep
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)

            if let error = model.lastError, step == .build {
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
                } else if step == .folderArt && folderArt == nil {
                    Button("Skip") { move(by: 1) }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { move(by: 1) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
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

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The name identifies the glyph in this app.")
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
            Text("Choose an SVG made only of filled shapes, about square.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(drawingURL == nil ? "Choose Drawing…" : "Change Drawing…") {
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
            Text("Choose full-colour art to use as \(folderName ?? "the folder")'s own icon in Finder windows, or skip this step. The icon is set after the glyph is built; a folder with a custom icon asks before replacing it. Folder Icon… adds hand-tuned small sizes.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(folderArt == nil ? "Choose Art…" : "Change Art…") {
                    if let url = FolderArtOptInView.chooseMaster() { checkFolderArt(url) }
                }
                if let folderArt {
                    Text(folderArt.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Clear") {
                        self.folderArt = nil
                        folderArtProblem = nil
                        checkingArt = false
                    }
                    .buttonStyle(.link)
                }
            }
            if let folderArtProblem {
                Text(folderArtProblem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkFolderArt(_ url: URL) {
        folderArt = url
        folderArtProblem = nil
        checkingArt = true
        Task {
            let problem = await Task.detached { () -> String? in
                do {
                    try FolderArtBuilder.checkMaster(url)
                    return nil
                } catch let error as FolderArtError {
                    return error.message
                } catch {
                    return error.localizedDescription
                }
            }.value
            if folderArt == url {
                folderArtProblem = problem
                checkingArt = false
            }
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
                Text("Build the new drawing for \(updating.name). Every folder that uses it shows the new drawing.")
            } else if let folderName {
                Text("Build the glyph \(trimmedName) and use it for \(folderName).")
            } else {
                Text("Build the glyph \(trimmedName) and add it to the Glyph Library.")
            }
            Text("Xcode's asset tool builds it in a few seconds. The glyph is saved once the build succeeds.")
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

    /// The name beside the preview: the folder's, or the glyph's when there is no folder.
    private var displayName: String { folderName ?? updating?.name ?? trimmedName }

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
        let art = folderArt
        let completion: @MainActor (UUID?) -> Void = { id in
            building = false
            guard let id else { return }
            // Picked up by the picker's Apply, once the mapping exists.
            if let art, updating == nil { model.pendingFolderArt = art }
            finished(id)
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
