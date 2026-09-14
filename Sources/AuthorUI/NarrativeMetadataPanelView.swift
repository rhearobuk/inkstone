import AuthorData
import SwiftUI

/// Shown above the editor for any document under the Narrative tree. Lets the author mark a
/// folder as a Book, Section, or Chapter (text documents are always Scenes), fill in
/// type-specific metadata, toggle "Do Not Publish" (inheritable down the tree), and see live
/// word-count progress.
struct NarrativeMetadataPanel: View {
    @ObservedObject var controller: WorkspaceController
    let document: Document

    private var narrativeType: NarrativeType? {
        document.narrativeType.flatMap(NarrativeType.init(rawValue:))
    }

    private var isFolder: Bool {
        document.kind == DocumentKind.folder.rawValue || document.kind == DocumentKind.draftFolder.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if isFolder {
                    Picker("Type", selection: typeBinding) {
                        Text("Unspecified").tag(NarrativeType?.none)
                        ForEach([NarrativeType.book, .section, .chapter], id: \.self) { type in
                            Text(type.displayName).tag(NarrativeType?.some(type))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                } else {
                    Label("Scene", systemImage: "doc.text")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let number = controller.computedNarrativeNumber(for: document), let narrativeType {
                    Text("\(narrativeType.displayName) \(number)")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

                Spacer()

                doNotPublishToggle
            }

            if let narrativeType {
                let fields = NarrativeMetadataSchema.fields(for: narrativeType)
                if !fields.isEmpty {
                    Divider()
                    NarrativeFieldsGrid(controller: controller, document: document, fields: fields)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var typeBinding: Binding<NarrativeType?> {
        Binding(
            get: { narrativeType },
            set: { controller.setNarrativeType(document, to: $0) }
        )
    }

    @ViewBuilder
    private var doNotPublishToggle: some View {
        let inheritedSource = document.inheritedPublishingExclusionSource
        VStack(alignment: .trailing, spacing: 2) {
            Toggle(isOn: Binding(
                get: { document.isPublishingExcluded },
                set: { controller.setDoNotPublish(document, $0) }
            )) {
                Text("Do Not Publish")
            }
            .toggleStyle(narrativeToggleStyle)
            .disabled(inheritedSource != nil)

            if let inheritedSource {
                Text("Inherited from: \(inheritedSource.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var narrativeToggleStyle: some ToggleStyle {
        #if os(macOS)
        CheckboxToggleStyle()
        #else
        SwitchToggleStyle()
        #endif
    }
}

private struct NarrativeFieldsGrid: View {
    @ObservedObject var controller: WorkspaceController
    let document: Document
    let fields: [NarrativeFieldDescriptor]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields, id: \.key) { field in
                if field.key == NarrativeMetadataSchema.targetWordCountKey {
                    wordCountRow(field)
                } else {
                    fieldRow(field)
                }
            }
        }
    }

    private func fieldRow(_ field: NarrativeFieldDescriptor) -> some View {
        let binding = Binding<String>(
            get: { controller.narrativeFieldValue(field, on: document) },
            set: { controller.setNarrativeFieldValue($0, for: field, on: document) }
        )
        return HStack(alignment: .top, spacing: 8) {
            Text(field.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            if field.valueKind == .longText {
                TextEditor(text: binding)
                    .font(.body)
                    .frame(minHeight: 44, maxHeight: 88)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))
            } else {
                TextField(field.placeholder ?? "", text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func wordCountRow(_ field: NarrativeFieldDescriptor) -> some View {
        let binding = Binding<String>(
            get: { controller.narrativeFieldValue(field, on: document) },
            set: { controller.setNarrativeFieldValue($0, for: field, on: document) }
        )
        let actual = document.actualWordCount
        let target = Int64(controller.narrativeFieldValue(field, on: document))
        return HStack(alignment: .center, spacing: 8) {
            Text("Word Count")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text("\(actual) actual")
                .font(.body)
            Text("/")
                .foregroundStyle(.secondary)
            TextField("Target", text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            if let target, target > 0 {
                ProgressView(value: min(Double(actual) / Double(target), 1))
                    .frame(width: 100)
            }
        }
    }
}

