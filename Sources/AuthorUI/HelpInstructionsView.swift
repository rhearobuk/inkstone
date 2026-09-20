import SwiftUI

/// A concise in-app guide to the authoring workflow and its primary tools.
public struct HelpInstructionsView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Inkstone Help")
                        .font(.largeTitle.bold())

                    Text("Create, organize, revise, and export your writing from one workspace. Changes are saved automatically while you work.")
                        .foregroundStyle(.secondary)

                    HelpSection("Start a project", systemImage: "book.closed") {
                        HelpStep("Create a project", detail: "Select New Project in the toolbar, enter a title, and choose Create. Select a project in the Projects sidebar whenever you want to switch your workspace.")
                        HelpStep("Import existing work", detail: "Select Import Project and choose a .scriv package or .scrivx file. Import into a new Inkstone project or an existing one. Importing reads your Scrivener project; it never changes the source project.")
                    }

                    HelpSection("Organize the binder", systemImage: "list.bullet.indent") {
                        HelpStep("Navigate", detail: "Select an item in the binder to open it. Expand folders and chapters to reveal their children.")
                        HelpStep("Reorder", detail: "Use Move Up or Move Down in a Mac context menu or the ellipsis menu on iPad and Vision Pro. You can also drag entries before or after another entry in the same Story Bible category, including mixed documents and native entries. Documents still support dropping inside folders. Clear search and filters, and show hidden items, before reordering. Entries cannot be dragged between projects, and semantic entries cannot be converted to another category by dragging.")
                        HelpStep("Classify", detail: "Assign one Label and one Status in any document, folder, character dossier, or Story Bible entry. Choose None to clear an assignment, or Manage Labels and Statuses to create or edit definitions in Project Preferences. Imported character dossiers share assignments with their source documents. Use the Status and Label controls above the binder to filter documents and Story Bible entries.")
                        HelpStep("Show hidden items", detail: "Choose View Options in the toolbar, turn on Show Hidden Items, then use the hidden item's context menu and choose Show Scene.")
                        HelpStep("Recover deleted work", detail: "Use Move to Trash from a project or binder item’s context menu. Restore items from Trash to their original location, or empty Trash only when you no longer need them.")
                        HelpStep("Delete a Story Bible entry", detail: "Use Delete Entry Permanently in an entry's detail view or binder menu; on iPad and Vision Pro, open the row's ellipsis menu. Confirm only when you no longer need the entry, or choose Cancel to keep it. Semantic entries do not go to Trash. Character deletion also removes an imported character's source entry. Document-backed Research continues to use Trash and Restore.")
                    }

                    HelpSection("Write and revise", systemImage: "square.and.pencil") {
                        HelpStep("Edit", detail: "Select a text document in the binder, then write in the editor. Use the document inspector to manage its title, synopsis, notes, metadata, and publishing inclusion where available.")
                        HelpStep("Search", detail: "Choose Find in Project in the toolbar to filter the binder by title. Choose Find & Replace to preview and replace body text across the selected project.")
                        HelpStep("Build your Story Bible", detail: "Select Story Bible items in the binder to record people, places, artifacts, events, worldbuilding, and relationships that support your manuscript.")
                    }

                    HelpSection("Export your manuscript", systemImage: "square.and.arrow.up") {
                        HelpStep("Choose scope", detail: "Select a narrative item, then choose Export. Pick the document, chapter, or book scope you want to publish.")
                        HelpStep("Select format", detail: "Choose Manuscript for DOCX, PDF for a print-ready document, or Ebook for EPUB. Review the available template and format options before saving.")
                        HelpStep("Check exclusions", detail: "Documents marked as excluded from publishing are omitted by default. Enable the export option to include them only when you intend to export draft or supplementary material.")
                    }

                    HelpSection("Use AI-assisted tools", systemImage: "sparkles") {
                        HelpStep("Configure a provider", detail: "Open Inkstone Settings from the app menu to choose Apple Intelligence, add an API key for a supported cloud provider, or configure local Ollama models. API keys are stored in the system Keychain.")
                        HelpStep("Request editorial feedback", detail: "Open AI Assistant in the toolbar and select AI Editor. Choose a persona, review scope, and manuscript target, then review the returned notes before deciding how to revise.")
                        HelpStep("Ask about your project", detail: "Choose Project Chat in the AI Assistant menu for project-aware conversation. AI suggestions are recommendations; they do not automatically modify manuscript text.")
                    }

                    HelpSection("Privacy and support", systemImage: "hand.raised") {
                        Text("Apple Intelligence runs on-device. Cloud AI requests send the text and project context needed for that request to the selected provider; Inkstone does not automatically fall back to a cloud provider. Keep personal writing and API credentials out of shared repositories.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(32)
            }
            .navigationTitle("Help")
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 620, idealHeight: 760)
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
    }
}

private struct HelpStep: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}
