import SidebarIconCore
import SwiftUI

@main
struct SidebarIconsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // Single-instance windows sharing one model, so there is one ledger writer
        // (contracts/ui.md).
        Window("Sidebar Icons", id: "main") {
            MainView(model: model)
                .task { await model.start() }
        }
        .defaultSize(width: 640, height: 400)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
            CommandGroup(before: .toolbar) {
                WindowMenuItems()
                Divider()
            }
        }

        Window("Glyph Library", id: "library") {
            GlyphLibraryView(model: model)
                .task { await model.start() }
        }
        .defaultSize(width: 560, height: 460)

        Window("About Sidebar Icons", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// View › Main and View › Glyph Library: open the window, or bring it to the front.
struct WindowMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Main") { openWindow(id: "main") }
            .keyboardShortcut("1")
        Button("Glyph Library") { openWindow(id: "library") }
            .keyboardShortcut("2")
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingRefresh = false
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 0) {
            BannerView(model: model)
            MappingListView(model: model)
            Divider()
            HStack {
                Button("Add Folder…", systemImage: "plus") {
                    AddMappingFlow.run(model: model)
                }
                .disabled(!model.canChange)
                Button("Glyph Library", systemImage: "square.stack") {
                    openWindow(id: "library")
                }
                Spacer()
                if model.busy {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh Finder…") { confirmingRefresh = true }
                    .disabled(!model.canReset)
                Button("Reset All…", role: .destructive) { confirmingReset = true }
                    .disabled(!model.canReset)
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 6)
            Text(model.statusLine.isEmpty ? " " : model.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom], 12)
                .textSelection(.enabled)
        }
        .frame(minWidth: 520, minHeight: 300)
        .confirmationDialog("Restart Finder?", isPresented: $confirmingRefresh) {
            Button("Restart Finder") { model.refreshFinder() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder windows close and reopen; a copy in progress may be interrupted.")
        }
        .confirmationDialog("Reset All?", isPresented: $confirmingReset) {
            Button("Reset All", role: .destructive) { model.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if model.folderIconsRecorded || model.rows.contains(where: \.hasFolderIcon) {
                Text("Remove all custom sidebar icons and delete this app's mappings and copied images? Folder icons set by this app are put back as they were; the rest of your folders stays as it is.")
            } else {
                Text("Remove all custom sidebar icons and delete this app's mappings and copied images? Your folders stay as they are.")
            }
        }
        .sheet(item: $model.styleRequest) { request in
            StylePickerView(request: request, model: model, apply: model.applyStyle, cancel: model.cancelStyle)
        }
        .sheet(item: $model.folderArtRequest) { request in
            FolderArtOptInView(request: request, model: model, close: model.closeFolderIcon)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
            presenting: model.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

/// Non-blocking notices (research D3, D8).
struct BannerView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.startupError {
                banner(error, symbol: "xmark.octagon.fill", tint: .red)
            }
            if let reason = model.readOnlyReason {
                banner(reason, symbol: "lock.fill", tint: .orange)
            }
            if model.favoritesUnavailable {
                banner("Finder's sidebar Favorites can't be read; Add and Apply wait until they can. Reset All works.",
                       symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if model.unverifiedBuild {
                banner("Sidebar Icons is verified on macOS \(SidebarIconCoreInfo.verifiedBuilds.sorted().joined(separator: ", ")); this Mac runs \(SystemInfo.macOSBuild). Check that icons appear after Apply; Reset All undoes every change.",
                       symbol: "info.circle.fill", tint: .yellow)
            }
        }
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12))
    }
}
