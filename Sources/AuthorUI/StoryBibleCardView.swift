import AuthorData
import SwiftUI
import UniformTypeIdentifiers

struct StoryBibleCardView: View {
    @ObservedObject var controller: WorkspaceController
    @State private var showsImageImporter = false
    @State private var showsNewNote = false
    @State private var noteTitle = ""
    @State private var noteBody = ""

    var body: some View {
        if let card = controller.selectedStoryBibleCard {
            Form {
                Section("Identity") {
                    TextField("Name", text: entityBinding(card, \.canonicalName))
                        .accessibilityIdentifier("storyBible.name")
                    TextField("Description", text: cardBinding(card, \.details), axis: .vertical)
                        .accessibilityIdentifier("storyBible.description")
                }

                switch card.semanticEntity.kind {
                case SemanticEntityKind.location.rawValue:
                    placeFields(card)
                case SemanticEntityKind.object.rawValue:
                    characterLinks(card, title: "Owners", relationship: .artifact)
                case SemanticEntityKind.organization.rawValue:
                    characterLinks(card, title: "Linked Characters", relationship: .organization)
                default:
                    EmptyView()
                }

                Section("Photos") {
                    let photos = card.semanticEntity.galleryItems.sorted {
                        ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
                    }
                    if photos.isEmpty {
                        Text("No photos attached.").foregroundStyle(.secondary)
                    } else {
                        LinkedGalleryItemsView(items: photos) { controller.selection = .galleryItem($0.id) }
                    }
                    Button("Add Photos", systemImage: "photo.badge.plus") { showsImageImporter = true }
                }

                Section("Notes") {
                    ForEach(card.notes.sorted { $0.orderIndex < $1.orderIndex }, id: \.id) { note in
                        VStack(alignment: .leading) {
                            HStack {
                                TextField("Note title", text: noteBinding(note, \.title))
                                Button(role: .destructive) {
                                    controller.deleteStoryBibleNote(note)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete note")
                                .help("Delete note")
                            }
                            TextField("Note", text: noteBinding(note, \.body), axis: .vertical)
                        }
                    }
                    Button("Add Note") { showsNewNote = true }
                }

                StoryBibleRelationshipsSection(entity: card.semanticEntity, controller: controller)
            }
            .formStyle(.grouped)
            .navigationTitle(card.semanticEntity.canonicalName)
            .fileImporter(
                isPresented: $showsImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                do {
                    _ = try controller.addGalleryImages(from: result.get(), relatedTo: card.semanticEntity)
                } catch {
                    controller.report(error)
                }
            }
            .sheet(isPresented: $showsNewNote) {
                NavigationStack {
                    Form {
                        TextField("Title (optional)", text: $noteTitle)
                        TextField("Note", text: $noteBody, axis: .vertical)
                    }
                    .navigationTitle("New Note")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { resetNote() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                do {
                                    try controller.addStoryBibleNote(title: noteTitle, body: noteBody, to: card)
                                    resetNote()
                                } catch {
                                    controller.report(error)
                                }
                            }
                            .disabled(noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func placeFields(_ card: StoryBibleCard) -> some View {
        Section("Place") {
            TextField("Unique features", text: cardBinding(card, \.uniqueFeatures), axis: .vertical)
            TextField("Location description", text: cardBinding(card, \.locationDescription), axis: .vertical)
            TextField("Street address", text: cardBinding(card, \.streetAddress), axis: .vertical)
            TextField("GPS coordinates", text: cardBinding(card, \.gpsCoordinates))
        }
        characterLinks(card, title: "Related Characters", relationship: .place)
        Section("Descriptors") {
            TextField("Sights", text: cardBinding(card, \.sights), axis: .vertical)
            TextField("Sounds", text: cardBinding(card, \.sounds), axis: .vertical)
            TextField("Smells", text: cardBinding(card, \.smells), axis: .vertical)
        }
    }

    private func characterLinks(
        _ card: StoryBibleCard,
        title: String,
        relationship: StoryBibleCharacterRelationship
    ) -> some View {
        Section(title) {
            Menu("Select Characters") {
                ForEach(controller.storyBibleCharacterProfiles, id: \.id) { character in
                    Toggle(character.semanticEntity.canonicalName, isOn: characterBinding(
                        character,
                        card: card,
                        relationship: relationship
                    ))
                }
            }
            let names = characters(for: card, relationship: relationship)
                .map(\.semanticEntity.canonicalName)
                .sorted()
            if !names.isEmpty {
                Text(names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func characters(
        for card: StoryBibleCard,
        relationship: StoryBibleCharacterRelationship
    ) -> Set<CharacterProfile> {
        switch relationship {
        case .place: card.relatedCharacters
        case .artifact: card.owners
        case .organization: card.linkedCharacters
        }
    }

    private func characterBinding(
        _ character: CharacterProfile,
        card: StoryBibleCard,
        relationship: StoryBibleCharacterRelationship
    ) -> Binding<Bool> {
        Binding(
            get: { characters(for: card, relationship: relationship).contains(character) },
            set: { include in
                var selected = characters(for: card, relationship: relationship)
                if include {
                    selected.insert(character)
                } else {
                    selected.remove(character)
                }
                controller.setCharacters(selected, for: card, relationship: relationship)
            }
        )
    }

    private func entityBinding(
        _ card: StoryBibleCard,
        _ keyPath: ReferenceWritableKeyPath<SemanticEntity, String>
    ) -> Binding<String> {
        Binding(
            get: { card.semanticEntity[keyPath: keyPath] },
            set: {
                card.semanticEntity[keyPath: keyPath] = $0
                controller.saveStoryBibleCard(card)
            }
        )
    }

    private func cardBinding(
        _ card: StoryBibleCard,
        _ keyPath: ReferenceWritableKeyPath<StoryBibleCard, String?>
    ) -> Binding<String> {
        Binding(
            get: { card[keyPath: keyPath] ?? "" },
            set: {
                card[keyPath: keyPath] = $0.blankAsNil
                controller.saveStoryBibleCard(card)
            }
        )
    }

    private func noteBinding(
        _ note: StoryBibleNote,
        _ keyPath: ReferenceWritableKeyPath<StoryBibleNote, String?>
    ) -> Binding<String> {
        Binding(
            get: { note[keyPath: keyPath] ?? "" },
            set: {
                note[keyPath: keyPath] = $0.blankAsNil
                controller.saveStoryBibleNote(note)
            }
        )
    }

    private func noteBinding(
        _ note: StoryBibleNote,
        _ keyPath: ReferenceWritableKeyPath<StoryBibleNote, String>
    ) -> Binding<String> {
        Binding(
            get: { note[keyPath: keyPath] },
            set: {
                note[keyPath: keyPath] = $0
                controller.saveStoryBibleNote(note)
            }
        )
    }

    private func resetNote() {
        noteTitle = ""
        noteBody = ""
        showsNewNote = false
    }
}

private extension String {
    var blankAsNil: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
