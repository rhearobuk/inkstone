import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
                        #if os(macOS)
                        selectSourceMacOS()
                        #else
                        showsSourcePicker = true
                        #endif
                    } label: {
                        Label(
                            sourceURL?.lastPathComponent ?? "Choose .scriv Package or .scrivx File",
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .help("Choose a Scrivener project to import")
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

                    Text(
                        "Scrivener is a trademark of Literature & Latte Ltd. Inkstone is an independent project and is not affiliated with, endorsed by, or sponsored by Literature & Latte Ltd."
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
                allowedContentTypes: Self.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    handleSelectedURL(url)
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

    private func handleSelectedURL(_ url: URL) {
        sourceURL = url
        if newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newProjectTitle = url.deletingPathExtension().lastPathComponent
        }
    }

    #if os(macOS)
    private func selectSourceMacOS() {
        let panel = NSOpenPanel()
        panel.title = "Select Scrivener Project"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = Self.allowedContentTypes

        if panel.runModal() == .OK, let url = panel.url {
            handleSelectedURL(url)
        }
    }
    #endif

    private static var allowedContentTypes: [UTType] {
        [
            .scrivenerProjectPackage,
            .scrivenerProjectDirectory,
            .scrivenerProjectBundle,
            .scrivenerProjectItem,
            .scrivenerProjectXML,
            .scrivenerProjectData,
            UTType(importedAs: "com.literatureandlatte.scrivener2", conformingTo: .package),
            UTType(importedAs: "com.literatureandlatte.scrivener3.scriv", conformingTo: .package),
            .package,
            .bundle,
            .directory,
            .folder,
            .xml,
            .data,
            .item
        ]
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
    static let scrivenerProjectPackage = UTType(tag: "scriv", tagClass: .filenameExtension, conformingTo: .package)
        ?? UTType(importedAs: "com.literatureandlatte.scrivener.project", conformingTo: .package)
    static let scrivenerProjectDirectory = UTType(tag: "scriv", tagClass: .filenameExtension, conformingTo: .directory)
        ?? UTType(importedAs: "com.literatureandlatte.scrivener.project-directory", conformingTo: .directory)
    static let scrivenerProjectBundle = UTType(tag: "scriv", tagClass: .filenameExtension, conformingTo: .bundle)
        ?? .bundle
    static let scrivenerProjectItem = UTType(tag: "scriv", tagClass: .filenameExtension, conformingTo: .item)
        ?? .item
    static let scrivenerProjectXML = UTType(tag: "scrivx", tagClass: .filenameExtension, conformingTo: .xml)
        ?? UTType(importedAs: "com.literatureandlatte.scrivener.project-xml", conformingTo: .xml)
    static let scrivenerProjectData = UTType(tag: "scrivx", tagClass: .filenameExtension, conformingTo: .data)
        ?? .data
}
