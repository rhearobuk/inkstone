import AuthorData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
                    if narrativeType == .book {
                        BookISBNsSection(controller: controller, document: document)
                        BookCoversSection(controller: controller, document: document)
                    }
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

private struct BookISBNsSection: View {
    @ObservedObject var controller: WorkspaceController
    let document: Document

    private var isbnEntries: [BookISBN] {
        controller.bookISBNs(on: document)
    }

    private var availableFormats: [BookFormat] {
        BookFormat.allCases.filter { format in
            format.isUserSelectable &&
            !isbnEntries.contains { $0.format == format }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ISBNs by Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Menu("Add Format") {
                    ForEach(availableFormats) { format in
                        Button(format.displayName) {
                            controller.addBookISBN(for: format, on: document)
                        }
                    }
                }
                .disabled(availableFormats.isEmpty)
            }

            ForEach(isbnEntries) { entry in
                HStack(spacing: 8) {
                    Text(entry.format.displayName)
                        .font(.body)
                        .frame(width: 120, alignment: .leading)
                    TextField("978-0-000-00000-0", text: Binding(
                        get: { entry.number },
                        set: { controller.setBookISBN($0, for: entry.format, on: document) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button {
                        controller.removeBookISBN(for: entry.format, on: document)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(entry.format.displayName) ISBN")
                }
            }
        }
    }
}

private struct BookCoversSection: View {
    @ObservedObject var controller: WorkspaceController
    let document: Document
    @State private var coverToUpload: BookCoverKind?
    @State private var showsCoverImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Publishing Covers")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(BookCoverKind.allCases) { kind in
                coverRow(kind)
            }
        }
        .fileImporter(
            isPresented: $showsCoverImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard let kind = coverToUpload else { return }
            defer { coverToUpload = nil }
            do {
                guard let url = try result.get().first else {
                    throw WorkspaceError.noImageSelected
                }
                try controller.setBookCover(from: url, kind: kind, on: document)
            } catch {
                controller.report(error)
            }
        }
    }

    private func coverRow(_ kind: BookCoverKind) -> some View {
        let cover = controller.bookCover(kind, on: document)
        return HStack(spacing: 8) {
            if let cover {
                Button {
                    controller.selection = .galleryItem(cover.id)
                } label: {
                    GalleryImage(data: cover.resource.data)
                        .frame(width: 72, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Open \(kind.displayName)")
            } else {
                Image(systemName: "photo")
                    .frame(width: 72, height: 54)
                    .foregroundStyle(.secondary)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(cover == nil ? "Upload" : "Replace") {
                uploadCover(kind)
            }
            if cover != nil {
                Button(role: .destructive) {
                    controller.removeBookCover(kind, on: document)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(kind.displayName)")
            }
        }
    }

    private func uploadCover(_ kind: BookCoverKind) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Select \(kind.displayName)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try controller.setBookCover(from: url, kind: kind, on: document)
            } catch {
                controller.report(error)
            }
        }
        #else
        coverToUpload = kind
        showsCoverImporter = true
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
