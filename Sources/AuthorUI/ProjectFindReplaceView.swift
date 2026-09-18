import SwiftUI

struct ProjectFindReplaceView: View {
    @ObservedObject var controller: WorkspaceController
    @Binding var findText: String
    @Environment(\.dismiss) private var dismiss
    @State private var replacementText = ""
    @State private var caseSensitive = false
    @State private var showsReplacementConfirmation = false
    @State private var replacementSummary: ProjectTextReplacementSummary?

    private var results: [ProjectTextSearchResult] {
        controller.projectTextSearchResults(for: findText, caseSensitive: caseSensitive)
    }

    private var matchCount: Int {
        results.reduce(0) { $0 + $1.matchCount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find")
                            .font(.headline)
                    TextField("Text to find", text: $findText)
                        Toggle("Match case", isOn: $caseSensitive)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Replace")
                            .font(.headline)
                    TextEditor(text: $replacementText)
                            .font(.body)
                            .frame(height: 72)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.secondary.opacity(0.3))
                            }
                    Text("Use \\n for a new line, \\t for a tab, or \\\\ for a backslash. Typed new lines are preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if findText.isEmpty {
                        emptyState(
                            title: "Enter Text to Find",
                            description: "Matches are searched across all document body text in this project."
                        )
                    } else if results.isEmpty {
                        emptyState(
                            title: "No Matches",
                            description: "No document body text matches your search."
                        )
                    } else {
                        Label(
                            "\(matchCount) match\(matchCount == 1 ? "" : "es") in \(results.count) document\(results.count == 1 ? "" : "s")",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .font(.headline)
                    }

                    if let replacementSummary {
                        Text(
                            "Replaced \(replacementSummary.replacementCount) occurrence\(replacementSummary.replacementCount == 1 ? "" : "s") in \(replacementSummary.documentCount) document\(replacementSummary.documentCount == 1 ? "" : "s")."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Find & Replace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace All") {
                        showsReplacementConfirmation = true
                    }
                    .disabled(findText.isEmpty || results.isEmpty)
                }
            }
            .alert(
                "Replace All Occurrences?",
                isPresented: $showsReplacementConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Replace All", role: .destructive) {
                    Task { @MainActor in
                        do {
                            replacementSummary = try await controller.replaceProjectText(
                                searchText: findText,
                                with: replacementText,
                                caseSensitive: caseSensitive
                            )
                        } catch {
                            controller.report(error)
                        }
                    }
                }
            } message: {
                Text("This will replace \(matchCount) occurrence\(matchCount == 1 ? "" : "s") in \(results.count) document\(results.count == 1 ? "" : "s").")
            }
        }
        .frame(width: 520, height: 380)
    }

    private func emptyState(title: String, description: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
