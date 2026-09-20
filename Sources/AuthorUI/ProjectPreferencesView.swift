import AuthorData
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A project-level preferences pane exposing the vocabularies imported from (or authored
/// alongside) a Scrivener-style project: Section Types, Labels, Statuses, and Custom Metadata
/// fields. These correspond to `<SectionTypes>`, `<LabelSettings>`, `<StatusSettings>`, and
/// `<CustomMetaDataSettings>` in the Scrivener project XML.
public struct ProjectPreferencesView: View {
    @ObservedObject private var controller: WorkspaceController
    @Environment(\.dismiss) private var dismiss
    @State private var selection = PreferencesPane.sectionTypes

    public init(controller: WorkspaceController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 12) {
                Picker("Preference category", selection: $selection) {
                    ForEach(PreferencesPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("project.preferences.category")

                ProjectPreferencesContent(selection: selection, controller: controller)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.selectedProject?.title ?? "Project")
                    .font(.headline)
                Text("Preferences")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

private enum PreferencesPane: String, CaseIterable, Identifiable {
    case sectionTypes
    case labels
    case statuses
    case customMetadata

    var id: Self { self }

    var title: String {
        switch self {
        case .sectionTypes: "Section Types"
        case .labels: "Labels"
        case .statuses: "Statuses"
        case .customMetadata: "Custom Metadata"
        }
    }
}

private struct ProjectPreferencesContent: View {
    let selection: PreferencesPane
    @ObservedObject var controller: WorkspaceController

    @ViewBuilder
    var body: some View {
        switch selection {
        case .sectionTypes:
            SectionTypesPane(controller: controller)
        case .labels:
            LabelsPane(controller: controller)
        case .statuses:
            StatusesPane(controller: controller)
        case .customMetadata:
            CustomMetadataPane(controller: controller)
        }
    }
}

// MARK: - Section Types

private struct SectionTypesPane: View {
    @ObservedObject var controller: WorkspaceController
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Section types classify a binder item's structural role, such as Chapter, Scene, or Front Matter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(controller.sortedSectionTypeDefinitions, id: \.id) { definition in
                    SectionTypeRow(definition: definition, controller: controller)
                }
            }
            .listStyle(.inset)
            addRow
        }
        .padding(.top, 8)
    }

    private var addRow: some View {
        HStack {
            TextField("New section type name", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addSectionType)
            Button("Add", action: addSectionType)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addSectionType() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        controller.addSectionType(title: title)
        newTitle = ""
    }
}

private struct SectionTypeRow: View {
    let definition: SectionTypeDefinition
    @ObservedObject var controller: WorkspaceController
    @State private var title: String

    init(definition: SectionTypeDefinition, controller: WorkspaceController) {
        self.definition = definition
        self.controller = controller
        _title = State(initialValue: definition.title)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .onSubmit(commit)
            Spacer()
            Button(role: .destructive) {
                controller.deleteSectionType(definition)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete section type")
            .help("Delete section type")
        }
    }

    private func commit() {
        guard title != definition.title else { return }
        controller.renameSectionType(definition, title: title)
    }
}

// MARK: - Labels

private struct LabelsPane: View {
    @ObservedObject var controller: WorkspaceController
    @State private var newTitle = ""
    @State private var newColor = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels color-code documents in the binder (e.g. content ratings or revision passes).")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(controller.sortedLabelDefinitions, id: \.id) { definition in
                    LabelRow(definition: definition, controller: controller)
                }
            }
            .listStyle(.inset)
            addRow
        }
        .padding(.top, 8)
    }

    private var addRow: some View {
        HStack {
            ColorPicker("", selection: $newColor, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("New label color")
                .help("Choose a color for the new label")
                .frame(width: 32)
            TextField("New label name", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addLabel)
            Button("Add", action: addLabel)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addLabel() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        controller.addLabel(title: title, color: newColor.rgbComponents)
        newTitle = ""
        newColor = .accentColor
    }
}

private struct LabelRow: View {
    let definition: LabelDefinition
    @ObservedObject var controller: WorkspaceController
    @State private var title: String
    @State private var color: Color

    init(definition: LabelDefinition, controller: WorkspaceController) {
        self.definition = definition
        self.controller = controller
        _title = State(initialValue: definition.title)
        _color = State(initialValue: definition.swiftUIColor ?? .gray)
    }

    var body: some View {
        HStack {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("Label color")
                .help("Choose this label's color")
                .frame(width: 32)
                .onChange(of: color) { _, newValue in
                    controller.updateLabel(definition, title: title, color: newValue.rgbComponents)
                }
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .onSubmit(commit)
            if definition.isDefault {
                Text("Default")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                controller.deleteLabel(definition)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete label")
            .help("Delete label")
        }
    }

    private func commit() {
        guard title != definition.title else { return }
        controller.updateLabel(definition, title: title, color: definition.rgbComponents)
    }
}

// MARK: - Statuses

private struct StatusesPane: View {
    @ObservedObject var controller: WorkspaceController
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statuses track a document's draft progress, such as To Do, First Draft, or Done.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(controller.sortedStatusDefinitions, id: \.id) { definition in
                    StatusRow(definition: definition, controller: controller)
                }
            }
            .listStyle(.inset)
            addRow
        }
        .padding(.top, 8)
    }

    private var addRow: some View {
        HStack {
            TextField("New status name", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addStatus)
            Button("Add", action: addStatus)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addStatus() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        controller.addStatus(title: title)
        newTitle = ""
    }
}

private struct StatusRow: View {
    let definition: StatusDefinition
    @ObservedObject var controller: WorkspaceController
    @State private var title: String

    init(definition: StatusDefinition, controller: WorkspaceController) {
        self.definition = definition
        self.controller = controller
        _title = State(initialValue: definition.title)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .onSubmit(commit)
            if definition.isDefault {
                Text("Default")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                controller.deleteStatus(definition)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete status")
            .help("Delete status")
        }
    }

    private func commit() {
        guard title != definition.title else { return }
        controller.renameStatus(definition, title: title)
    }
}

// MARK: - Custom Metadata

private struct CustomMetadataPane: View {
    @ObservedObject var controller: WorkspaceController
    @State private var newTitle = ""
    @State private var newType = "text"

    static let valueTypes = ["text", "list", "checkbox", "date", "long text"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom metadata fields hold per-document values such as ISBNs or content ratings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(controller.sortedCustomMetadataFields, id: \.id) { field in
                    CustomMetadataRow(field: field, controller: controller)
                }
            }
            .listStyle(.inset)
            addRow
        }
        .padding(.top, 8)
    }

    private var addRow: some View {
        HStack {
            TextField("New field name", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addField)
            Picker("", selection: $newType) {
                ForEach(Self.valueTypes, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            Button("Add", action: addField)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addField() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        controller.addCustomMetadataField(displayName: title, valueType: newType)
        newTitle = ""
        newType = "text"
    }
}

private struct CustomMetadataRow: View {
    let field: MetadataField
    @ObservedObject var controller: WorkspaceController
    @State private var title: String
    @State private var valueType: String

    init(field: MetadataField, controller: WorkspaceController) {
        self.field = field
        self.controller = controller
        _title = State(initialValue: field.displayName)
        _valueType = State(initialValue: field.valueType)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $title)
                .textFieldStyle(.plain)
                .onSubmit(commit)
            Spacer()
            Text(valueType.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                controller.deleteCustomMetadataField(field)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete custom metadata field")
            .help("Delete custom metadata field")
        }
    }

    private func commit() {
        guard title != field.displayName else { return }
        controller.updateCustomMetadataField(field, displayName: title, valueType: valueType)
    }
}

// MARK: - Color helpers

extension LabelDefinition {
    var swiftUIColor: Color? {
        guard let red = colorRed?.doubleValue,
              let green = colorGreen?.doubleValue,
              let blue = colorBlue?.doubleValue else { return nil }
        return Color(red: red, green: green, blue: blue)
    }

    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        guard let red = colorRed?.doubleValue,
              let green = colorGreen?.doubleValue,
              let blue = colorBlue?.doubleValue else { return nil }
        return (red, green, blue)
    }
}

private extension Color {
    var rgbComponents: (red: Double, green: Double, blue: Double) {
        #if canImport(AppKit)
        let native = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        return (Double(native.redComponent), Double(native.greenComponent), Double(native.blueComponent))
        #else
        let native = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
        #endif
    }
}
