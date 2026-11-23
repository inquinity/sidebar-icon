import SidebarIconCore
import SwiftUI

@main
struct SidebarIconsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // One window, so there is one model and one ledger writer (contracts/ui.md).
        Window("Sidebar Icons", id: "main") {
            MainView(model: model)
                .task { await model.start() }
        }
        .defaultSize(width: 640, height: 400)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
        }

        Window("About Sidebar Icons", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

struct MainView: View {
    @Bindable var model: AppModel
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
            Text("Remove all custom sidebar icons and delete this app's mappings and copied images? Your folders are not changed.")
        }
        .sheet(item: $model.styleRequest) { request in
            StylePickerView(request: request, model: model, apply: model.applyStyle, cancel: model.cancelStyle)
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
                banner("Finder's sidebar Favorites can't be read, so Add and Apply are off. Reset All still works.",
                       symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if model.unverifiedBuild {
                banner("Not yet verified on this macOS build (\(SystemInfo.macOSBuild)); icons may not appear. Reset All always works.",
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
