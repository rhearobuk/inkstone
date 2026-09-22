import AuthorData
import AuthorUI
import CloudKit
import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
@MainActor
struct InkstoneApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(CloudShareAppDelegate.self) private var cloudShareDelegate
    #endif
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
        #if os(macOS)
        workspaceWindow
            .commands {
                InkstoneHelpCommands()
            }

        Window("Inkstone Help", id: "inkstone-help") {
            HelpInstructionsView()
        }
        .defaultSize(width: 760, height: 760)

        Settings {
            AppPreferencesView(settings: aiSettings, authorInformation: authorInformation)
        }
        #else
        workspaceWindow
        #endif
    }

    private var workspaceWindow: some Scene {
        WindowGroup {
            if let controller = startup.controller {
                AuthorWorkspaceView(controller: controller)
                    .environmentObject(aiSettings)
                    .environmentObject(authorInformation)
                    .frame(minWidth: 900, minHeight: 600)
                    .onChange(of: scenePhase) { _, phase in
                        Task { @MainActor in
                            await Task.yield()
                            if phase == .active {
                                controller.refresh()
                            } else {
                                await controller.flushPendingChanges()
                            }
                        }
                    }
            } else {
                StoreStartupErrorView(message: startup.errorMessage)
            }
        }
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
            let managementTests = ProcessInfo.processInfo.arguments.contains("--management-tests")
            let store = try (preview || managementTests)
                ? AuthorDataStore(inMemory: true)
                : AuthorDataStore.open(storeURL: Self.storeURL())
            #else
            let store = try AuthorDataStore.open(storeURL: Self.storeURL())
            #endif
            #if os(macOS)
            CloudShareAppDelegate.configure(store: store)
            #endif
            #if DEBUG
            let preferences: UserDefaults
            if managementTests {
                let suite = "Inkstone.ManagementTests"
                guard let testPreferences = UserDefaults(suiteName: suite) else {
                    throw CocoaError(.fileReadUnknown)
                }
                testPreferences.removePersistentDomain(forName: suite)
                preferences = testPreferences
            } else {
                preferences = .standard
            }
            let workspace = WorkspaceController(store: store, projectListPreferences: preferences)
            #else
            let workspace = WorkspaceController(store: store)
            #endif
            if workspace.projects.isEmpty && !store.cloudKitSyncEnabled {
                try workspace.createProject(title: "My Novel")
            }
            #if DEBUG
            if managementTests {
                _ = workspace.addLabel(title: "QA Label")
                _ = workspace.addStatus(title: "QA Status")
                for category in StoryBibleCategory.allCases where category != .research {
                    _ = try workspace.addStoryBibleEntry(named: "QA \(category.rawValue)", category: category)
                }
                _ = try workspace.addStoryBibleEntry(named: "QA Second Organization", category: .organizations)
                _ = try workspace.addResearchDocument(title: "QA Research")
                if let projectID = workspace.selectedProjectID {
                    workspace.selection = .projectDefinition(projectID)
                }
            }
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

#if os(macOS)
@MainActor
private final class CloudShareAppDelegate: NSObject, NSApplicationDelegate {
    private static let inbox = CloudKitInvitationInbox()
    private static var service: CloudKitSharingService?

    static func configure(store: AuthorDataStore) {
        let service = CloudKitSharingService(dataStore: store)
        self.service = service
        Task { _ = await inbox.drain(using: service) }
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Self.inbox.enqueue(metadata)
        guard let service = Self.service else { return }
        Task { _ = await Self.inbox.drain(using: service) }
    }
}
#endif

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
