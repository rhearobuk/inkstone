import AuthorData
import AuthorUI
import SwiftUI

@main
@MainActor
struct ScribeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: WorkspaceController
    @StateObject private var aiSettings = AISettingsStore()
    @StateObject private var authorInformation = AuthorInformationSettings()

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif

        do {
            #if DEBUG
            let preview = ProcessInfo.processInfo.arguments.contains("--editor-preview")
            #else
            let preview = false
            #endif
            let store = try preview
                ? AuthorDataStore(inMemory: true)
                : AuthorDataStore.open(storeURL: Self.storeURL())
            let workspace = WorkspaceController(store: store)
            if workspace.projects.isEmpty && !store.cloudKitSyncEnabled {
                try workspace.createProject(title: "My Novel")
            }
            #if DEBUG
            if preview, let project = workspace.selectedProject,
               let scene = project.documents.first(where: { $0.kind == DocumentKind.text.rawValue }) {
                scene.title = "The Arrival"
                scene.plainText = "The clock struck noon. Two minutes later, it was midnight. She opened the door."
                workspace.selection = .document(scene.id)
                try store.save()
            }
            #endif
            _controller = StateObject(wrappedValue: workspace)
        } catch {
            fatalError("Scribe could not open its data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthorWorkspaceView(controller: controller)
                .environmentObject(aiSettings)
                .environmentObject(authorInformation)
                .frame(minWidth: 900, minHeight: 600)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        controller.refresh()
                    } else {
                        controller.flushPendingChanges()
                    }
                }
        }

        #if os(macOS)
        Settings {
            AppPreferencesView(settings: aiSettings, authorInformation: authorInformation)
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
