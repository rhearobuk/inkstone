import AuthorData
import SwiftUI

struct StoryBibleRelationshipsSection: View {
    let entity: SemanticEntity
    @ObservedObject var controller: WorkspaceController
    @State private var showsNewRelationship = false

    var body: some View {
        Section("Story Bible Relationships") {
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
            Button("Add Story Bible Relationship") {
                showsNewRelationship = true
            }
            .disabled(controller.storyBibleRelationshipTargets(from: entity).isEmpty)
        }
        .sheet(isPresented: $showsNewRelationship) {
            StoryBibleRelationshipComposer(controller: controller, source: entity)
        }
    }

    private var outgoing: [StoryBibleRelationship] {
        guard entity.managedObjectContext != nil, !entity.isDeleted else { return [] }
        return entity.outgoingStoryBibleRelationships.filter {
            !$0.isDeleted && $0.managedObjectContext != nil
        }.sorted {
            $0.targetEntity.canonicalName.localizedCaseInsensitiveCompare(
                $1.targetEntity.canonicalName
            ) == .orderedAscending
        }
    }

    private var incoming: [StoryBibleRelationship] {
        guard entity.managedObjectContext != nil, !entity.isDeleted else { return [] }
        return entity.incomingStoryBibleRelationships.filter {
            !$0.isDeleted && $0.managedObjectContext != nil
        }.sorted {
            $0.sourceEntity.canonicalName.localizedCaseInsensitiveCompare(
                $1.sourceEntity.canonicalName
            ) == .orderedAscending
        }
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
        .accessibilityLabel("Delete relationship")
        .help("Delete relationship")
    }

}
