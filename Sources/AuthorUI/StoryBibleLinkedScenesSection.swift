import AuthorData
import SwiftUI

struct StoryBibleLinkedScenesSection: View {
    let entity: SemanticEntity
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        Section("Linked Scenes") {
            if linkedScenes.isEmpty {
                Text("No linked scenes yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedScenes) { scene in
                    Button {
                        controller.selection = .document(scene.documentID)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(scene.documentTitle)
                                Spacer()
                                Text("\(scene.mentionCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !scene.matchedTexts.isEmpty {
                                Text(scene.matchedTexts.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var linkedScenes: [SceneEntityLinkSummary] {
        controller.linkedScenes(for: entity)
    }
}
