import AuthorData
import Combine
import SwiftUI

struct ContentMetadataEditor: View {
    @ObservedObject var controller: WorkspaceController
    let target: BinderContentTarget
    @State private var labelIdentifier: String?
    @State private var statusIdentifier: String?
    @State private var isLoaded = false
    @State private var showsPreferences = false
    @State private var ownerSelection: WorkspaceSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Label", selection: labelBinding) {
                    Text("None").tag(String?.none)
                    ForEach(controller.sortedLabelDefinitions, id: \.id) { definition in
                        Text(definition.title).tag(Optional(definition.sourceIdentifier))
                    }
                }
                .accessibilityIdentifier("content.label")
                .accessibilityLabel("Content label")
                Picker("Status", selection: statusBinding) {
                    Text("None").tag(String?.none)
                    ForEach(controller.sortedStatusDefinitions, id: \.id) { definition in
                        Text(definition.title).tag(Optional(definition.sourceIdentifier))
                    }
                }
                .accessibilityIdentifier("content.status")
                .accessibilityLabel("Content status")
            }
            .disabled(!isLoaded)

            if controller.sortedLabelDefinitions.isEmpty || controller.sortedStatusDefinitions.isEmpty {
                Text("No labels or statuses yet? Create definitions in Project Preferences, then assign them here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("content.metadata.empty")
            }
            Button("Manage Labels and Statuses…") { showsPreferences = true }
                .accessibilityIdentifier("content.metadata.manage")
            if !isLoaded {
                Button("Retry Loading Metadata", action: refresh)
                    .accessibilityIdentifier("content.metadata.retry")
            }
        }
        .disabled(isTrashed)
        .task(id: target) {
            ownerSelection = controller.selection
            refresh()
        }
        .onReceive(controller.$binderItems.receive(on: RunLoop.main)) { _ in
            guard ownerSelection != nil, ownerSelection == controller.selection else { return }
            refresh()
        }
        .sheet(isPresented: $showsPreferences, onDismiss: refresh) {
            ProjectPreferencesView(controller: controller)
        }
    }

    private var isTrashed: Bool {
        guard case .document(let id) = target else { return false }
        return controller.isDocumentTrashed(id)
    }

    private var labelBinding: Binding<String?> {
        Binding(get: { labelIdentifier }, set: { identifier in
            do {
                try controller.setContentLabel(identifier, for: target)
                refresh()
            } catch {
                controller.report(error)
            }
        })
    }

    private var statusBinding: Binding<String?> {
        Binding(get: { statusIdentifier }, set: { identifier in
            do {
                try controller.setContentStatus(identifier, for: target)
                refresh()
            } catch {
                controller.report(error)
            }
        })
    }

    private func refresh() {
        do {
            let metadata = try controller.contentMetadata(for: target)
            labelIdentifier = metadata.labelIdentifier
            statusIdentifier = metadata.statusIdentifier
            isLoaded = true
        } catch {
            isLoaded = false
            controller.report(error)
        }
    }
}

struct SemanticEntryDeleteButton: View {
    @ObservedObject var controller: WorkspaceController
    let entity: SemanticEntity

    var body: some View {
        Button(role: .destructive) {
            controller.semanticEntityToDelete = entity.id
        } label: {
            Label("Delete Entry Permanently…", systemImage: "trash.slash")
        }
        .accessibilityIdentifier("storyBible.delete")
        .accessibilityLabel("Delete \(entity.canonicalName) permanently")
        .help("Permanently delete this Story Bible entry after confirmation")
        .disabled(entity.characterProfile?.sourceDocument.map {
            controller.isDocumentTrashed($0.id)
        } ?? false)
    }
}
