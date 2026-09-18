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
                        controller.openDocument(scene.documentID)
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityDescription(for: scene))
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private var linkedScenes: [SceneEntityLinkSummary] {
        controller.linkedScenes(for: entity)
    }

    private func accessibilityDescription(for scene: SceneEntityLinkSummary) -> String {
        let matchedText = scene.matchedTexts.isEmpty ? "" : ". Mentions: \(scene.matchedTexts.joined(separator: ", "))"
        return "\(scene.documentTitle). \(scene.mentionCount) mentions\(matchedText)"
    }
}
