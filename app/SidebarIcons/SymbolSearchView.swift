import SidebarIconCore
import SwiftUI

/// The System glyph tab (contracts/ui.md): a name field with suggestions, live validation and a
/// preview tinted with the accent colour on light and dark sidebar swatches.
struct SymbolSearchView: View {
    @Binding var name: String
    let folderName: String

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { MappingManager.systemSymbolExists(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Symbol name, for example hammer", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                if !trimmed.isEmpty {
                    if isValid {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not a system glyph on this Mac", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .font(.callout)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                    ForEach(SymbolCatalog.suggestions(matching: trimmed), id: \.self) { symbol in
                        Button {
                            name = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 32)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(symbol == trimmed ? Color.accentColor.opacity(0.2) : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding(4)
            }
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))

            HStack(spacing: 12) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(alignment: .leading, spacing: 6) {
                        GlyphSample(symbol: isValid ? trimmed : nil, name: folderName, size: 16, dark: dark)
                        GlyphSample(symbol: isValid ? trimmed : nil, name: folderName, size: 20, dark: dark)
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
}

/// One sidebar row with a glyph tinted like the system ones, at `size` points.
struct GlyphSample: View {
    let symbol: String?
    let name: String
    let size: CGFloat
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let symbol {
                    Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(.tint)
                } else {
                    Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(SidebarSwatch.text(dark: dark))
                .lineLimit(1)
            Text("\(Int(size)) pt")
                .font(.caption2)
                .foregroundStyle(SidebarSwatch.secondaryText(dark: dark))
        }
    }
}

/// Sidebar-like colours for the previews (research D9).
enum SidebarSwatch {
    static func fill(dark: Bool) -> Color { dark ? Color(white: 0.17) : Color(white: 0.93) }
    static func text(dark: Bool) -> Color { dark ? Color(white: 0.92) : Color(white: 0.1) }
    static func secondaryText(dark: Bool) -> Color { dark ? Color(white: 0.6) : Color(white: 0.45) }
}
