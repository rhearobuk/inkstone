import SwiftUI
import UniformTypeIdentifiers

struct ScrivenerImportView: View {
    @ObservedObject var controller: WorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var sourceURL: URL?
    @State private var showsSourcePicker = false
    @State private var destinationMode: DestinationMode = .newProject
    @State private var targetProjectID: UUID?
    @State private var newProjectTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Scrivener Source") {
                    Button {
                        showsSourcePicker = true
                    } label: {
                        Label(
                            sourceURL?.lastPathComponent ?? "Choose .scriv Package or .scrivx File",
                            systemImage: "doc.badge.plus"
                        )
                    }
                }

                Section("Destination") {
                    Picker("Import into", selection: $destinationMode) {
                        Text("New Project").tag(DestinationMode.newProject)
                        Text("Existing Project").tag(DestinationMode.existingProject)
                    }
                    .pickerStyle(.segmented)

                    if destinationMode == .newProject {
                        TextField("Project title", text: $newProjectTitle)
                    } else {
                        Picker("Target project", selection: $targetProjectID) {
                            ForEach(controller.projects, id: \.id) { project in
                                Text(project.title).tag(Optional(project.id))
                            }
                        }
                    }
                }

                Section {
                    Text(
                        "If an imported Story Bible identity already exists, the imported copy is renamed using the Scrivener project name."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Scrivener Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { performImport() }
                        .disabled(!canImport || controller.isImporting)
                }
            }
            .fileImporter(
                isPresented: $showsSourcePicker,
                allowedContentTypes: [.scrivenerProject, .scrivenerProjectXML, .folder, .xml],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    sourceURL = url
                    if newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        newProjectTitle = url.deletingPathExtension().lastPathComponent
                    }
                } catch {
                    controller.report(error)
                }
            }
            .onAppear {
                targetProjectID = controller.selectedProjectID ?? controller.projects.first?.id
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    private var canImport: Bool {
        guard sourceURL != nil else { return false }
        switch destinationMode {
        case .newProject:
            return !newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existingProject:
            return targetProjectID != nil
        }
    }

    private func performImport() {
        guard let sourceURL else { return }
        let destination: ScrivenerImportDestination
        switch destinationMode {
        case .newProject:
            destination = .newProject(title: newProjectTitle)
        case .existingProject:
            guard let targetProjectID else { return }
            destination = .existing(targetProjectID)
        }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        do {
            _ = try controller.importScrivenerProject(
                from: sourceURL,
                destination: destination
            )
            dismiss()
        } catch {
            controller.report(error)
        }
    }
}

private enum DestinationMode: Hashable {
    case newProject
    case existingProject
}

private extension UTType {
    static let scrivenerProject = UTType(filenameExtension: "scriv")
        ?? UTType(importedAs: "com.literatureandlatte.scrivener.project", conformingTo: .package)
    static let scrivenerProjectXML = UTType(filenameExtension: "scrivx")
        ?? UTType(importedAs: "com.literatureandlatte.scrivener.project-xml", conformingTo: .xml)
}
