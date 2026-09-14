import AuthorData
import AuthorUI
import SwiftUI

@main
@MainActor
struct AuthorApp: App {
    @StateObject private var controller: WorkspaceController
    @StateObject private var aiSettings = AISettingsStore()

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif

        do {
            let storeURL = try Self.storeURL()
            let store = try AuthorDataStore(storeURL: storeURL)
            let workspace = WorkspaceController(store: store)
            if workspace.projects.isEmpty {
                try workspace.createProject(title: "My Novel")
            }
            _controller = StateObject(wrappedValue: workspace)
        } catch {
            fatalError("AuthorApp could not open its data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthorWorkspaceView(controller: controller)
                .environmentObject(aiSettings)
                .frame(minWidth: 900, minHeight: 600)
        }

        #if os(macOS)
        Settings {
            AppPreferencesView(settings: aiSettings)
        }
        #endif
    }

    private static func storeURL() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(
            "AuthorApp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("AuthorData.sqlite")
    }
}
