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
                    linkedSceneButton(for: scene)
                }
            }
        }
    }

    private var linkedScenes: [SceneEntityLinkSummary] {
        controller.linkedScenes(for: entity)
    }

    @ViewBuilder
    private func linkedSceneButton(for scene: SceneEntityLinkSummary) -> some View {
        let button = Button {
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(scene.documentTitle)
        .accessibilityValue(accessibilityValue(for: scene))
        .accessibilityAddTraits(.isButton)
        button
    }

    private func accessibilityValue(for scene: SceneEntityLinkSummary) -> String {
        let matchedText = scene.matchedTexts.isEmpty ? "" : ". Mentions: \(scene.matchedTexts.joined(separator: ", "))"
        let mentionLabel = scene.mentionCount == 1 ? "mention" : "mentions"
        return "\(scene.mentionCount) \(mentionLabel)\(matchedText)"
    }
}
