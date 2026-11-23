import SidebarIconCore
import SwiftUI

/// What the style picker is for: a new mapping (after the folder pick) or Change Icon….
struct StyleRequest: Identifiable {
    enum Purpose {
        case add(folder: URL)
        case change(MappingRow)
    }

    let id = UUID()
    let purpose: Purpose

    var folderName: String {
        switch purpose {
        case .add(let folder): folder.lastPathComponent
        case .change(let row): row.displayName
        }
    }

    var currentStyle: SidebarStyle? {
        if case .change(let row) = purpose { row.style } else { nil }
    }
}

/// The owner's choice in the picker.
enum StyleChoice {
    case systemSymbol(String)
    case customGlyph(UUID)
    case image(URL)
}

/// The style picker sheet (contracts/ui.md): System glyph, Custom glyph and Full colour tabs,
/// then Cancel or Apply. Nothing is copied or saved until Apply.
struct StylePickerView: View {
    enum Tab: Hashable { case system, custom, fullColour }

    let request: StyleRequest
    let model: AppModel
    let apply: (StyleChoice) -> Void
    let cancel: () -> Void

    @State private var tab: Tab
    @State private var symbolName: String
    @State private var picked: PickedImage?
    @State private var selectedGlyph: UUID?

    init(request: StyleRequest, model: AppModel, apply: @escaping (StyleChoice) -> Void, cancel: @escaping () -> Void) {
        self.request = request
        self.model = model
        self.apply = apply
        self.cancel = cancel
        if case .customGlyph(let id)? = request.currentStyle {
            _selectedGlyph = State(initialValue: id)
        } else {
            _selectedGlyph = State(initialValue: nil)
        }
        switch request.currentStyle {
        case .systemSymbol(let name)?:
            _tab = State(initialValue: .system)
            _symbolName = State(initialValue: name)
        case .fullColour?:
            _tab = State(initialValue: .fullColour)
            _symbolName = State(initialValue: "")
        case .customGlyph?:
            _tab = State(initialValue: .custom)
            _symbolName = State(initialValue: "")
        case nil:
            _tab = State(initialValue: .system)
            _symbolName = State(initialValue: "")
        }
        _picked = State(initialValue: nil)
    }

    private var choice: StyleChoice? {
        switch tab {
        case .system:
            let name = symbolName.trimmingCharacters(in: .whitespaces)
            return MappingManager.systemSymbolExists(name) ? .systemSymbol(name) : nil
        case .custom:
            return selectedGlyph.flatMap { id in model.glyphs.contains { $0.id == id } ? .customGlyph(id) : nil }
        case .fullColour:
            return picked.map { .image($0.url) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sidebar icon for \(request.folderName)").font(.headline)
            Picker("Style", selection: $tab) {
                Text("System glyph").tag(Tab.system)
                Text("Custom glyph").tag(Tab.custom)
                Text("Full colour").tag(Tab.fullColour)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .system:
                    SymbolSearchView(name: $symbolName, folderName: request.folderName)
                case .custom:
                    CustomGlyphTab(model: model, folderName: request.folderName, selection: $selectedGlyph)
                case .fullColour:
                    fullColourTab
                }
            }
            .frame(minHeight: 260, alignment: .top)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { if let choice { apply(choice) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice == nil)
            }
        }
        .padding(20)
        .frame(width: 452)
    }

    @ViewBuilder private var fullColourTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The image is drawn in full colour, as in 0.2.0.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(picked == nil ? "Choose Image…" : "Choose Another Image…") {
                if let url = AddMappingFlow.chooseImage(for: request.folderName) {
                    picked = PickedImage(url: url)
                }
            }
            if let picked {
                ImagePreview(picked: picked, folderName: request.folderName)
            }
        }
    }
}
