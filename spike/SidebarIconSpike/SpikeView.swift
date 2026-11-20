import SwiftUI

/// The spike window: one button per quickstart action and a status log to copy into the findings.
struct SpikeView: View {
    @State private var model = SpikeModel()
    @State private var confirmingRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    action("List Favorites", help: "Read-only: list sidebar Favorites, mapping status, and the ledger (B1)") {
                        await model.listFavorites()
                    }
                    action("Apply (Path A)", help: "Public Finder Sync only; changes nothing (A1)") {
                        await model.applyPathA()
                    }
                    action("Apply (Path B)", help: "Register the icons and set the sidebar override on both Favorites (B2)") {
                        await model.applyPathB()
                    }
                }
                GridRow {
                    action("Use runtime icon for DevDocs…", help: "Choose an image; it is copied into the container and applied (B3)") {
                        await model.useRuntimeIconForDevDocs()
                    }
                    Button("Refresh Finder…") { confirmingRefresh = true }
                        .help("Quit and relaunch Finder so it reloads sidebar icons")
                        .disabled(model.busy)
                    action("Reset", help: "Undo every recorded change: clear overrides, then unregister (B6)") {
                        await model.reset()
                    }
                }
            }
            .controlSize(.large)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                    Color.clear.frame(height: 1).id("end")
                }
                .background(.background.secondary, in: .rect(cornerRadius: 6))
                .onChange(of: model.log.count) { proxy.scrollTo("end", anchor: .bottom) }
            }

            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Copy Log") { model.copyLog() }
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 480)
        .confirmationDialog("Restart Finder?", isPresented: $confirmingRefresh) {
            Button("Restart Finder") { Task { await model.refreshFinder() } }
        } message: {
            Text("Finder quits and relaunches. Open Finder windows close and reopen, and a copy in progress in Finder may be interrupted.")
        }
    }

    private func action(_ title: String, help: String, _ perform: @escaping @MainActor () async -> Void) -> some View {
        Button(title) { Task { await perform() } }
            .help(help)
            .disabled(model.busy)
    }
}

#Preview {
    SpikeView()
}
