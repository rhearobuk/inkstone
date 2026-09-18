import AuthorData
import SwiftUI

struct StoryBibleRelationshipComposer: View {
    @ObservedObject var controller: WorkspaceController
    let source: SemanticEntity
    var onAdded: (SemanticEntity) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var category: StoryBibleCategory?
    @State private var targetID: UUID?
    @State private var kind = "related to"
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("From", value: source.canonicalName)
                Picker("Story Bible category", selection: Binding(
                    get: { category },
                    set: {
                        category = $0
                        targetID = nil
                    }
                )) {
                    Text("Choose a category").tag(Optional<StoryBibleCategory>.none)
                    ForEach(StoryBibleCategory.murderBoardCategories) { category in
                        Text(category.murderBoardTitle).tag(Optional(category))
                    }
                }
                .accessibilityIdentifier("relationship.category")

                Picker("Related entry", selection: $targetID) {
                    Text("Choose an entry").tag(Optional<UUID>.none)
                    ForEach(targets, id: \.id) { target in
                        Text(target.canonicalName).tag(Optional(target.id))
                    }
                }
                .disabled(category == nil || targets.isEmpty)
                .accessibilityIdentifier("relationship.target")

                TextField("Relationship", text: $kind)
                    .accessibilityIdentifier("relationship.kind")
                TextField("Notes", text: $notes, axis: .vertical)
                if category != nil && targets.isEmpty {
                    Text("No other entries in this category. Add an entry in the Story Bible or choose another category.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Relationship")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let target = targets.first(where: { $0.id == targetID }) else {
                            controller.report(WorkspaceError.invalidMove)
                            return
                        }
                        do {
                            try controller.addStoryBibleRelationship(kind: kind, notes: notes, from: source, to: target)
                            onAdded(target)
                            dismiss()
                        } catch {
                            controller.report(error)
                        }
                    }
                    .disabled(kind.nilIfBlank == nil || !targets.contains { $0.id == targetID })
                    .accessibilityIdentifier("relationship.add")
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var targets: [SemanticEntity] {
        guard let category else { return [] }
        return controller.storyBibleRelationshipTargets(from: source, category: category)
    }
}
