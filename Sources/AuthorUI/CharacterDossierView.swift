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
                        HStack {
                            TextField(
                                "Alias",
                                text: Binding(
                                    get: { alias.name },
                                    set: {
                                        alias.name = $0
                                        controller.saveAlias(alias, for: profile)
                                    }
                                )
                            )
                            deleteButton { controller.deleteAlias(alias) }
                        }
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
                        VStack(alignment: .leading) {
                            HStack {
                                TextField(
                                    "Measurement",
                                    text: Binding(
                                        get: { measurement.name },
                                        set: {
                                            measurement.name = $0
                                            controller.saveMeasurement(measurement)
                                        }
                                    )
                                )
                                TextField(
                                    "Value",
                                    text: Binding(
                                        get: { measurement.value },
                                        set: {
                                            measurement.value = $0
                                            controller.saveMeasurement(measurement)
                                        }
                                    )
                                )
                                TextField(
                                    "Unit",
                                    text: Binding(
                                        get: { measurement.unit ?? "" },
                                        set: {
                                            measurement.unit = $0
                                            controller.saveMeasurement(measurement)
                                        }
                                    )
                                )
                                deleteButton { controller.deleteMeasurement(measurement) }
                            }
                            TextField(
                                "Measurement notes",
                                text: Binding(
                                    get: { measurement.notes ?? "" },
                                    set: {
                                        measurement.notes = $0
                                        controller.saveMeasurement(measurement)
                                    }
                                ),
                                axis: .vertical
                            )
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
                            HStack {
                                TextField(
                                    "Note title",
                                    text: Binding(
                                        get: { note.title ?? "" },
                                        set: {
                                            note.title = $0
                                            controller.saveCharacterNote(note)
                                        }
                                    )
                                )
                                .font(.headline)
                                deleteButton { controller.deleteCharacterNote(note) }
                            }
                            TextField(
                                "Note",
                                text: Binding(
                                    get: { note.body },
                                    set: {
                                        note.body = $0
                                        controller.saveCharacterNote(note)
                                    }
                                ),
                                axis: .vertical
                            )
                        }
                    }
                    Button("Add Note") { editor = .note }
                }

                Section("Key Relationships") {
                    ForEach(sortedRelationships(profile), id: \.id) { relationship in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Picker(
                                    "Character",
                                    selection: relationshipTargetBinding(relationship)
                                ) {
                                    ForEach(controller.otherCharacterProfiles, id: \.id) { character in
                                        Text(character.semanticEntity.canonicalName)
                                            .tag(character.id)
                                    }
                                }
                                TextField(
                                    "Type",
                                    text: Binding(
                                        get: { relationship.kind },
                                        set: {
                                            relationship.kind = $0
                                            controller.saveCharacterRelationship(relationship)
                                        }
                                    )
                                )
                                deleteButton {
                                    controller.deleteCharacterRelationship(relationship)
                                }
                            }
                            TextField(
                                "Relationship notes",
                                text: Binding(
                                    get: { relationship.notes ?? "" },
                                    set: {
                                        relationship.notes = $0
                                        controller.saveCharacterRelationship(relationship)
                                    }
                                ),
                                axis: .vertical
                            )
                        }
                    }
                    Button("Add Relationship") { editor = .relationship }
                        .disabled(controller.otherCharacterProfiles.isEmpty)
                }

                Section("Conflicts") {
                    ForEach(sortedConflicts(profile), id: \.id) { conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                TextField(
                                    "Conflict title",
                                    text: Binding(
                                        get: { conflict.title },
                                        set: {
                                            conflict.title = $0
                                            controller.saveCharacterConflict(conflict)
                                        }
                                    )
                                )
                                .font(.headline)
                                Picker(
                                    "Type",
                                    selection: Binding(
                                        get: { conflict.kind },
                                        set: {
                                            conflict.kind = $0
                                            controller.saveCharacterConflict(conflict)
                                        }
                                    )
                                ) {
                                    Text("Internal").tag("internal")
                                    Text("External").tag("external")
                                    Text("Other").tag("other")
                                }
                                .labelsHidden()
                                deleteButton { controller.deleteCharacterConflict(conflict) }
                            }
                            TextField(
                                "Summary",
                                text: Binding(
                                    get: { conflict.summary ?? "" },
                                    set: {
                                        conflict.summary = $0
                                        controller.saveCharacterConflict(conflict)
                                    }
                                ),
                                axis: .vertical
                            )
                            Menu("Related Characters") {
                                ForEach(controller.otherCharacterProfiles, id: \.id) { character in
                                    Toggle(
                                        character.semanticEntity.canonicalName,
                                        isOn: conflictParticipantBinding(conflict, character: character)
                                    )
                                }
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

    private func relationshipTargetBinding(
        _ relationship: CharacterRelationship
    ) -> Binding<UUID> {
        Binding(
            get: { relationship.targetCharacter.id },
            set: { id in
                guard let character = controller.otherCharacterProfiles.first(where: { $0.id == id }) else {
                    return
                }
                relationship.targetCharacter = character
                controller.saveCharacterRelationship(relationship)
            }
        )
    }

    private func conflictParticipantBinding(
        _ conflict: CharacterConflict,
        character: CharacterProfile
    ) -> Binding<Bool> {
        Binding(
            get: { conflict.relatedCharacters.contains(character) },
            set: { isIncluded in
                if isIncluded {
                    conflict.relatedCharacters.insert(character)
                } else {
                    conflict.relatedCharacters.remove(character)
                }
                controller.saveCharacterConflict(conflict)
            }
        )
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
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
