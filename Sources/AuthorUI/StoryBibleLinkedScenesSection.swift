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
        .accessibilityValue("\(scene.mentionCount) mentions")
        .accessibilityAddTraits(.isButton)

        if let hint = accessibilityHint(for: scene) {
            button.accessibilityHint(hint)
        } else {
            button
        }
    }

    private func accessibilityHint(for scene: SceneEntityLinkSummary) -> String? {
        guard !scene.matchedTexts.isEmpty else { return nil }
        return "Mentions: \(scene.matchedTexts.joined(separator: ", "))"
    }
}
