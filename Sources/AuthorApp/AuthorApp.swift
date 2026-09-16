import AuthorData
import AuthorUI
import SwiftUI

@main
@MainActor
struct InkstoneApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var startup: InkstoneStartup
    @StateObject private var aiSettings = AISettingsStore()
    @StateObject private var authorInformation = AuthorInformationSettings()

    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif

        _startup = StateObject(wrappedValue: InkstoneStartup())
    }

    var body: some Scene {
        WindowGroup {
            if let controller = startup.controller {
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
            } else {
                StoreStartupErrorView(message: startup.errorMessage)
            }
        }
        .commands {
            #if os(macOS)
            InkstoneHelpCommands()
            #endif
        }

        #if os(macOS)
        Window("Inkstone Help", id: "inkstone-help") {
            HelpInstructionsView()
        }
        .defaultSize(width: 760, height: 760)

        Settings {
            AppPreferencesView(settings: aiSettings, authorInformation: authorInformation)
        }
        #endif
    }

}

#if os(macOS)
private struct InkstoneHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Inkstone Help") {
                openWindow(id: "inkstone-help")
            }
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}
#endif

@MainActor
private final class InkstoneStartup: ObservableObject {
    let controller: WorkspaceController?
    let errorMessage: String

    init() {
        do {
            #if DEBUG
            let preview = ProcessInfo.processInfo.arguments.contains("--editor-preview")
            let store = try preview
                ? AuthorDataStore(inMemory: true)
                : AuthorDataStore.open(storeURL: Self.storeURL())
            #else
            let store = try AuthorDataStore.open(storeURL: Self.storeURL())
            #endif
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
            controller = workspace
            errorMessage = ""
        } catch {
            controller = nil
            errorMessage = error.localizedDescription
        }
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

private struct StoreStartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Inkstone Could Not Open Your Library")
                .font(.title2.weight(.semibold))
            Text(
                "Your existing writing has not been changed. Close Inkstone and try again. "
                    + "If the problem persists, contact support and include this error: \(message)"
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
