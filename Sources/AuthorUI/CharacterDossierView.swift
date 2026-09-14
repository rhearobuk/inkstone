import AuthorData
import SwiftUI

struct CharacterDossierView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var editor: DossierEditor?

    var body: some View {
        if let profile = controller.selectedCharacterProfile {
            Form {
                Section("Identity") {
                    TextField("First name", text: requiredBinding(profile, \.firstName))
                    TextField("Middle name", text: optionalBinding(profile, \.middleName))
                    TextField("Last name", text: optionalBinding(profile, \.lastName))
                    TextField("Age", text: optionalBinding(profile, \.ageText))
                    TextField("Location", text: optionalBinding(profile, \.location))
                }

                Section("Aliases") {
                    ForEach(sortedAliases(profile), id: \.id) { alias in
                        Text(alias.name)
                    }
                    Button("Add Alias") { editor = .alias }
                }

                Section("Biometrics") {
                    TextField("Height", text: optionalBinding(profile, \.height))
                    TextField("Weight", text: optionalBinding(profile, \.weight))
                    TextField(
                        "Physical description",
                        text: optionalBinding(profile, \.physicalDescription),
                        axis: .vertical
                    )
                    ForEach(sortedMeasurements(profile), id: \.id) { measurement in
                        LabeledContent(measurement.name) {
                            Text([measurement.value, measurement.unit].compactMap { $0 }.joined(separator: " "))
                        }
                    }
                    Button("Add Measurement") { editor = .measurement }
                }

                Section("Biography") {
                    TextField(
                        "Biography",
                        text: optionalBinding(profile, \.biography),
                        axis: .vertical
                    )
                }

                Section("Notes") {
                    ForEach(sortedNotes(profile), id: \.id) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title ?? note.kind.capitalized)
                                .font(.headline)
                            Text(note.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Add Note") { editor = .note }
                }

                Section("Key Relationships") {
                    ForEach(sortedRelationships(profile), id: \.id) { relationship in
                        LabeledContent(relationship.targetCharacter.semanticEntity.canonicalName) {
                            Text(relationship.kind.capitalized)
                        }
                        if let notes = relationship.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Add Relationship") { editor = .relationship }
                        .disabled(controller.otherCharacterProfiles.isEmpty)
                }

                Section("Conflicts") {
                    ForEach(sortedConflicts(profile), id: \.id) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(conflict.title)
                                    .font(.headline)
                                Spacer()
                                Text(conflict.kind.capitalized)
                                    .foregroundStyle(.secondary)
                            }
                            if let summary = conflict.summary, !summary.isEmpty {
                                Text(summary)
                            }
                            let related = conflict.relatedCharacters
                                .map(\.semanticEntity.canonicalName)
                                .sorted()
                            if !related.isEmpty {
                                Text("Related: \(related.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Add Conflict") { editor = .conflict }
                }

                if let sourceDocument = profile.sourceDocument {
                    Section("Migration Source") {
                        LabeledContent("Imported from", value: sourceDocument.title)
                        Text("The original binder card and RTF remain preserved for provenance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(profile.semanticEntity.canonicalName)
            .sheet(item: $editor) { editor in
                DossierEditorSheet(
                    editor: editor,
                    profile: profile,
                    controller: controller
                )
            }
        }
    }

    private func requiredBinding(
        _ profile: CharacterProfile,
        _ keyPath: ReferenceWritableKeyPath<CharacterProfile, String>
    ) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: {
                profile[keyPath: keyPath] = $0
                controller.saveCharacterProfile(profile)
            }
        )
    }

    private func optionalBinding(
        _ profile: CharacterProfile,
        _ keyPath: ReferenceWritableKeyPath<CharacterProfile, String?>
    ) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] ?? "" },
            set: {
                profile[keyPath: keyPath] = $0
                controller.saveCharacterProfile(profile)
            }
        )
    }

    private func sortedAliases(_ profile: CharacterProfile) -> [EntityAlias] {
        profile.semanticEntity.aliases.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sortedMeasurements(_ profile: CharacterProfile) -> [CharacterMeasurement] {
        profile.measurements.sorted {
            ($0.orderIndex, $0.name) < ($1.orderIndex, $1.name)
        }
    }

    private func sortedNotes(_ profile: CharacterProfile) -> [CharacterNote] {
        profile.notes.sorted {
            ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
        }
    }

    private func sortedRelationships(_ profile: CharacterProfile) -> [CharacterRelationship] {
        profile.outgoingRelationships.sorted {
            $0.targetCharacter.semanticEntity.canonicalName.localizedCaseInsensitiveCompare(
                $1.targetCharacter.semanticEntity.canonicalName
            ) == .orderedAscending
        }
    }

    private func sortedConflicts(_ profile: CharacterProfile) -> [CharacterConflict] {
        profile.conflicts.sorted {
            $0.createdAt < $1.createdAt
        }
    }
}

private enum DossierEditor: String, Identifiable {
    case alias
    case measurement
    case note
    case relationship
    case conflict

    var id: Self { self }
}

private struct DossierEditorSheet: View {
    let editor: DossierEditor
    let profile: CharacterProfile
    @ObservedObject var controller: WorkspaceController
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var value = ""
    @State private var unit = ""
    @State private var bodyText = ""
    @State private var kind = "other"
    @State private var relatedCharacterID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                switch editor {
                case .alias:
                    TextField("Alias", text: $title)
                case .measurement:
                    TextField("Measurement name", text: $title)
                    TextField("Value", text: $value)
                    TextField("Unit (optional)", text: $unit)
                case .note:
                    TextField("Title (optional)", text: $title)
                    TextField("Notes", text: $bodyText, axis: .vertical)
                case .relationship:
                    Picker("Character", selection: $relatedCharacterID) {
                        ForEach(controller.otherCharacterProfiles, id: \.id) { character in
                            Text(character.semanticEntity.canonicalName)
                                .tag(Optional(character.id))
                        }
                    }
                    TextField("Relationship type", text: $kind)
                    TextField("Relationship notes", text: $bodyText, axis: .vertical)
                case .conflict:
                    TextField("Conflict title", text: $title)
                    Picker("Type", selection: $kind) {
                        Text("Internal").tag("internal")
                        Text("External").tag("external")
                        Text("Other").tag("other")
                    }
                    Picker("Related character", selection: $relatedCharacterID) {
                        Text("None").tag(UUID?.none)
                        ForEach(controller.otherCharacterProfiles, id: \.id) { character in
                            Text(character.semanticEntity.canonicalName)
                                .tag(Optional(character.id))
                        }
                    }
                    TextField("Summary", text: $bodyText, axis: .vertical)
                }
            }
            .navigationTitle(editor.rawValue.capitalized)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if editor == .relationship {
                    relatedCharacterID = controller.otherCharacterProfiles.first?.id
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var canSave: Bool {
        switch editor {
        case .alias: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .measurement:
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .note: !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .relationship: relatedCharacterID != nil
        case .conflict: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        do {
            switch editor {
            case .alias:
                try controller.addAlias(title, to: profile)
            case .measurement:
                try controller.addMeasurement(
                    name: title,
                    value: value,
                    unit: unit,
                    to: profile
                )
            case .note:
                try controller.addCharacterNote(title: title, body: bodyText, to: profile)
            case .relationship:
                guard let related = relatedCharacter else { return }
                try controller.addCharacterRelationship(
                    kind: kind,
                    notes: bodyText,
                    from: profile,
                    to: related
                )
            case .conflict:
                try controller.addCharacterConflict(
                    title: title,
                    summary: bodyText,
                    kind: kind,
                    relatedCharacter: relatedCharacter,
                    to: profile
                )
            }
            dismiss()
        } catch {
            controller.report(error)
        }
    }

    private var relatedCharacter: CharacterProfile? {
        guard let relatedCharacterID else { return nil }
        return controller.otherCharacterProfiles.first { $0.id == relatedCharacterID }
    }
}
