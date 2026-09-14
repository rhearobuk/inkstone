import AuthorData
import AuthorAI
import SwiftUI

public struct EditorialPassage: Equatable {
    public let documentID: UUID
    public let location: Int
    public let length: Int
    public let token: UUID
}

struct ReviewDetailView: View {
    @ObservedObject var review: EditorialReview
    @ObservedObject var editor: EditorialReviewController
    @ObservedObject var workspace: WorkspaceController
    let rerun: () -> Void
    @State private var severity = "all"
    @State private var category = "all"
    @State private var status = "all"
    @State private var confirmDelete = false
    private var stale: Bool {
        review.inputs.contains { input in
            if let document = input.document { return ReviewInputSnapshot.hash(document.plainText ?? "") != input.contentHash }
            return input.role == "manuscript"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(review.targetTitle).font(.headline)
            Text("Model feedback may be mistaken. Check the cited passage before acting on a recommendation.").font(.caption).foregroundStyle(.secondary)
            Text("\(review.status.capitalized) · \(review.createdAt.formatted())").font(.caption)
            let chunks = review.chunks.filter { $0.stage == "analysis" }
            Text("\(chunks.filter { $0.status == "completed" }.count) / \(chunks.count) manuscript sections reviewed").font(.caption)
            if stale { Text("Manuscript changed or deleted since review. Evidence below refers to the saved snapshot.").foregroundStyle(.orange).font(.caption) }
            if let error = review.errorMessage { Text(error).foregroundStyle(.orange).font(.caption) }
            Text(review.summary.isEmpty ? "No final synthesis available. Section results are retained below." : review.summary).textSelection(.enabled)
            DisclosureGroup("Review configuration") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(review.personaName), version \(review.personaVersion)")
                    Text("\(review.providerID) / \(review.modelID)")
                    Text("Scope: \(review.scope)")
                    Text(review.personaInstructions)
                    Text(review.parameters)
                    if let input = review.inputTokens, let output = review.outputTokens { Text("Reported usage: \(input) input / \(output) output tokens") }
                    Text(review.environment)
                    if let previous = review.previousReviewID { Text("Previous review: \(previous.uuidString)") }
                }.font(.caption).textSelection(.enabled)
            }
            DisclosureGroup("Saved inputs and section results") {
                ForEach(review.inputs.sorted { $0.orderIndex < $1.orderIndex }, id: \.id) { input in
                    DisclosureGroup(input.path) { Text(input.plainText).font(.caption).textSelection(.enabled) }
                }
                ForEach(review.chunks.sorted { $0.orderIndex < $1.orderIndex }, id: \.id) { chunk in
                    DisclosureGroup("\(chunk.stage.capitalized) \(chunk.orderIndex + 1): \(chunk.status)") {
                        Text(chunk.summary).font(.caption).textSelection(.enabled)
                        if let error = chunk.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
            HStack {
                Button("Review Target Again", action: rerun).disabled(editor.isRunning || review.target == nil)
                Button("Delete", role: .destructive) { confirmDelete = true }.disabled(editor.isRunning)
            }
            Picker("Severity", selection: $severity) {
                Text("All severities").tag("all")
                ForEach(["major", "moderate", "minor"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            Picker("Category", selection: $category) {
                Text("All categories").tag("all")
                ForEach(["technical", "story", "continuity", "style", "academic", "reader"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            Picker("Finding status", selection: $status) {
                Text("All statuses").tag("all")
                ForEach(["open", "addressed", "dismissed"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            let findings = review.findings.filter {
                (severity == "all" || $0.severity == severity) && (category == "all" || $0.category == category) && (status == "all" || $0.status == status)
            }.sorted { $0.createdAt < $1.createdAt }
            Text("\(findings.count) findings").font(.headline)
            ForEach(findings, id: \.id) { finding in
                EditorialFindingView(finding: finding, editor: editor, workspace: workspace)
            }
        }
        .alert("Delete this review and its saved snapshots?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { editor.deleteReview(review) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct EditorialFindingView: View {
    @ObservedObject var finding: EditorialFinding
    @ObservedObject var editor: EditorialReviewController
    @ObservedObject var workspace: WorkspaceController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(finding.title).font(.headline)
            Text("\(finding.severity.capitalized) · \(finding.category) · \(finding.status)").font(.caption).foregroundStyle(.secondary)
            Text(finding.explanation).textSelection(.enabled)
            Text("Recommendation: \(finding.recommendation)").textSelection(.enabled)
            ForEach(finding.anchors.sorted { $0.id.uuidString < $1.id.uuidString }, id: \.id) { anchor in
                if let input = anchor.input {
                    Text(input.title).font(.caption.bold())
                    if !anchor.excerpt.isEmpty { Text("“\(anchor.excerpt)”").font(.callout).italic().textSelection(.enabled) }
                    else { Text("Document-level finding; exact evidence range could not be verified.").font(.caption) }
                    if let document = input.document {
                        let unchanged = ReviewInputSnapshot.hash(document.plainText ?? "") == input.contentHash
                        Button(unchanged && anchor.location != nil ? "Go to Passage" : "Open Current Document") {
                            workspace.selection = .document(document.id)
                            if unchanged, let location = anchor.location, let length = anchor.length {
                                workspace.editorialPassage = .init(documentID: document.id, location: location.intValue, length: length.intValue, token: UUID())
                            } else { workspace.editorialPassage = nil }
                        }
                    }
                }
            }
            HStack {
                Button(finding.status == "addressed" ? "Reopen" : "Mark Addressed") { editor.updateFinding(finding, status: finding.status == "addressed" ? "open" : "addressed") }
                Button("Dismiss") { editor.updateFinding(finding, status: "dismissed") }
            }
            TextField("Your note", text: Binding(get: { finding.userNote }, set: { editor.updateFinding(finding, note: $0) }), axis: .vertical).textFieldStyle(.roundedBorder)
        }.padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
