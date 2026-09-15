import AuthorData
import SwiftUI

struct StoryBibleRelationshipsSection: View {
    let entity: SemanticEntity
    @ObservedObject var controller: WorkspaceController
    @State private var showsNewRelationship = false
    @State private var targetID: UUID?
    @State private var kind = "related to"
    @State private var notes = ""

    var body: some View {
        Section("Relationships") {
            ForEach(outgoing, id: \.id) { relationship in
                relationshipEditor(relationship, other: relationship.targetEntity)
            }
            ForEach(incoming, id: \.id) { relationship in
                HStack {
                    Text(relationship.sourceEntity.canonicalName)
                    Spacer()
                    Text(relationship.kind)
                        .foregroundStyle(.secondary)
                    deleteButton { controller.deleteStoryBibleRelationship(relationship) }
                }
                if let notes = relationship.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Add Relationship") {
                targetID = targets.first?.id
                showsNewRelationship = true
            }
            .disabled(targets.isEmpty)
        }
        .sheet(isPresented: $showsNewRelationship) {
            NavigationStack {
                Form {
                    Picker("Related entry", selection: $targetID) {
                        ForEach(targets, id: \.id) { target in
                            Text(target.canonicalName).tag(Optional(target.id))
                        }
                    }
                    TextField("Relationship", text: $kind)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                .navigationTitle("New Relationship")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { resetEditor() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            guard let target = targets.first(where: { $0.id == targetID }) else { return }
                            do {
                                try controller.addStoryBibleRelationship(
                                    kind: kind,
                                    notes: notes,
                                    from: entity,
                                    to: target
                                )
                                resetEditor()
                            } catch {
                                controller.report(error)
                            }
                        }
                        .disabled(targetID == nil || kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var outgoing: [StoryBibleRelationship] {
        entity.outgoingStoryBibleRelationships.sorted {
            $0.targetEntity.canonicalName.localizedCaseInsensitiveCompare(
                $1.targetEntity.canonicalName
            ) == .orderedAscending
        }
    }

    private var incoming: [StoryBibleRelationship] {
        entity.incomingStoryBibleRelationships.sorted {
            $0.sourceEntity.canonicalName.localizedCaseInsensitiveCompare(
                $1.sourceEntity.canonicalName
            ) == .orderedAscending
        }
    }

    private var targets: [SemanticEntity] {
        controller.storyBibleRelationshipTargets.filter { $0.id != entity.id }
    }

    private func relationshipEditor(_ relationship: StoryBibleRelationship, other: SemanticEntity) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(other.canonicalName)
                TextField(
                    "Relationship",
                    text: Binding(
                        get: { relationship.kind },
                        set: {
                            relationship.kind = $0
                            controller.saveStoryBibleRelationship(relationship)
                        }
                    )
                )
                deleteButton { controller.deleteStoryBibleRelationship(relationship) }
            }
            TextField(
                "Relationship notes",
                text: Binding(
                    get: { relationship.notes ?? "" },
                    set: {
                        relationship.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                        controller.saveStoryBibleRelationship(relationship)
                    }
                ),
                axis: .vertical
            )
        }
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
    }

    private func resetEditor() {
        targetID = nil
        kind = "related to"
        notes = ""
        showsNewRelationship = false
    }
}
