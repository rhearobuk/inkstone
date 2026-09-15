import AuthorData
import AuthorAI
import SwiftUI

public struct EditorialPassage: Equatable {
    public let documentID: UUID
    public let location: Int
    public let length: Int
    public let token: UUID
}

/// A review reads as a received message. Setup and diagnostics live outside the reading flow.
struct ReviewDetailView: View {
    @ObservedObject var review: EditorialReview
    @ObservedObject var editor: EditorialReviewController
    @ObservedObject var workspace: WorkspaceController
    @ObservedObject var settings: AISettingsStore
    let rerun: () -> Void
    @State private var status = "all"
    @State private var showingDetails = false
    @State private var confirmDelete = false

    private var active: Bool { ["queued", "running"].contains(review.status) }
    private var stale: Bool {
        review.inputs.contains { input in
            if let document = input.document { return ReviewInputSnapshot.hash(document.plainText ?? "") != input.contentHash }
            return input.role == "manuscript"
        }
    }
    private var findings: [EditorialFinding] {
        review.findings.filter { status == "all" || $0.status == status }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
    private var summary: String {
        if !review.summary.isEmpty { return review.summary }
        if active { return "I’m reading your manuscript. My notes will appear here as I go." }
        if review.status == "refused" { return "I wasn’t able to review this passage with the selected AI. You can choose another model in Review options and try again." }
        if review.status == "cancelled" { return "This review was stopped. Any notes I’d already gathered are saved below." }
        if review.status == "interrupted" { return "This review was interrupted. Your saved notes are below, and you can ask for a fresh review whenever you’re ready." }
        if !review.findings.isEmpty { return "Here are the notes I was able to gather. I couldn’t finish the whole review." }
        return "I couldn’t complete this review. Your manuscript hasn’t changed. Check the review details or try again."
    }
    private var conversationContext: String {
        let notes = review.findings
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .map { finding in
                let evidence = finding.anchors
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                    .map(\.excerpt)
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                return "[\(finding.severity) \(finding.category)] \(finding.title)\n\(finding.explanation)\nRecommendation: \(finding.recommendation)\nEvidence: \(evidence)"
            }
            .joined(separator: "\n\n")
        return "SUMMARY\n\(summary)\n\nSAVED FINDINGS\n\(notes)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Spacer(minLength: 35)
                VStack(alignment: .trailing, spacing: 7) {
                    Text("Please review “\(review.targetTitle)”.")
                        .font(.system(size: 14)).lineSpacing(3)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(EditorStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 17))
                    Text(review.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    EditorAvatar()
                    Text(EditorStyle.personaName(review.personaName))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Menu {
                        Button("About this review") { showingDetails = true }
                        Button("Ask for a fresh review", action: rerun).disabled(editor.isRunning || review.target == nil)
                        Divider()
                        Button("Delete review", role: .destructive) { confirmDelete = true }.disabled(editor.isRunning)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 25, height: 25)
                    }.editorMenuStyle().fixedSize().foregroundStyle(.secondary)
                        .accessibilityLabel("Review actions")
                        .help("Review actions")
                }
                VStack(alignment: .leading, spacing: 20) {
                    Text(summary)
                        .font(.system(size: 16)).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("editor-response")
                    if stale {
                        Label("You’ve edited this text since this review.", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if review.status == "partial" {
                        Text("This is a partial review. Some passages couldn’t be reviewed.")
                            .font(.system(size: 13)).foregroundStyle(.orange)
                    }
                    if !review.findings.isEmpty {
                        Divider().opacity(0.5)
                        HStack {
                            Text("A few things to look at").font(.system(size: 17, weight: .medium, design: .serif))
                            Spacer(minLength: 0)
                            Menu {
                                Picker("Show notes", selection: $status) {
                                    Text("All notes").tag("all")
                                    Text("Still to consider").tag("open")
                                    Text("Addressed").tag("addressed")
                                    Text("Dismissed").tag("dismissed")
                                }
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease").frame(width: 24, height: 24)
                            }.editorMenuStyle().fixedSize().foregroundStyle(.secondary)
                                .accessibilityLabel("Filter notes")
                                .help("Filter review notes")
                        }
                        if findings.isEmpty { Text("No notes in this view.").font(.system(size: 13)).foregroundStyle(.secondary) }
                        ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                            if index > 0 { Divider().opacity(0.45) }
                            EditorialFindingView(finding: finding, editor: editor, workspace: workspace)
                        }
                    }
                    if active {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(editor.progress.isEmpty ? "Preparing your review…" : editor.progress)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EditorStyle.paper, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1))
                .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
                if !active {
                    HStack {
                        Text("Your words, your decision.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Review details") { showingDetails = true }
                            .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                if !active, review.providerID == AIProvider.ollama.rawValue {
                    SeniorReviewConversation(settings: settings, reviewContext: conversationContext)
                }
            }
        }

        .sheet(isPresented: $showingDetails) { details }
        .alert("Delete this review?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                confirmDelete = false
                DispatchQueue.main.async {
                    editor.deleteReview(review)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The review and its saved copy of the text will be removed. Your manuscript stays unchanged.") }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("About this review").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { showingDetails = false }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(review.targetTitle).font(.headline)
                    Text("\(EditorStyle.personaName(review.personaName)) · \(review.createdAt.formatted())")
                    let chunks = review.chunks.filter { $0.stage == "analysis" }
                    Text("\(chunks.filter { $0.status == "completed" }.count) of \(chunks.count) passages reviewed")
                    if let error = review.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    Text("AI feedback can be mistaken. Use your judgment when considering a suggestion.").foregroundStyle(.secondary)
                    DisclosureGroup("Text that was reviewed") {
                        ForEach(review.inputs.sorted { $0.orderIndex < $1.orderIndex }, id: \.id) { input in
                            DisclosureGroup(input.path) { Text(input.plainText).textSelection(.enabled) }
                        }
                    }
                    DisclosureGroup("Notes from individual passages") {
                        ForEach(review.chunks.sorted { $0.orderIndex < $1.orderIndex }, id: \.id) { chunk in
                            DisclosureGroup("Passage \(chunk.orderIndex + 1) · \(chunk.status)") {
                                Text(chunk.summary).textSelection(.enabled)
                                if let error = chunk.errorMessage { Text(error).foregroundStyle(.orange) }
                            }
                        }
                    }
                    DisclosureGroup("Technical details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(review.providerID) / \(review.modelID)")
                            Text("\(review.personaName), version \(review.personaVersion)")
                            Text(review.personaInstructions)
                            Text(review.parameters)
                            Text(review.environment)
                            if let input = review.inputTokens, let output = review.outputTokens { Text("Usage: \(input) input / \(output) output tokens") }
                            if let previous = review.previousReviewID { Text("Previous review: \(previous.uuidString)") }
                        }.font(.caption).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(minWidth: 390, idealWidth: 460, minHeight: 420, idealHeight: 560)
    }
}

private struct SeniorReviewConversation: View {
    @ObservedObject var settings: AISettingsStore
    let reviewContext: String
    @State private var question = ""
    @State private var messages: [OllamaConversationMessage] = []
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Discuss this review", systemImage: "bubble.left.and.bubble.right")
                .font(.system(size: 15, weight: .semibold))
            Text("Ask the Senior Reviewer about its notes, priorities, or evidence. This discussion is kept only while this review is open.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.role == .user ? "You" : "Senior Reviewer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(message.content)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isSending {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Senior Reviewer is considering your question…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about this review…", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Send") {
                    Task { await send() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || settings.ollamaSeniorReviewerModel.isEmpty)
            }
        }
        .padding(20)
        .background(EditorStyle.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1))
    }

    private func send() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        question = ""
        errorMessage = nil
        messages.append(.init(role: .user, content: text))
        isSending = true
        defer { isSending = false }
        do {
            let response = try await OllamaReviewConversationClient(modelID: settings.ollamaSeniorReviewerModel)
                .respond(reviewContext: reviewContext, messages: messages)
            messages.append(.init(role: .assistant, content: response))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditorialFindingView: View {
    @ObservedObject var finding: EditorialFinding
    @ObservedObject var editor: EditorialReviewController
    @ObservedObject var workspace: WorkspaceController
    @State private var showingNote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(finding.title).font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if finding.status == "addressed" {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Addressed")
                }
            }
            Text(finding.explanation).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            ForEach(finding.anchors.sorted { $0.id.uuidString < $1.id.uuidString }, id: \.id) { anchor in
                if let input = anchor.input {
                    VStack(alignment: .leading, spacing: 8) {
                        if !anchor.excerpt.isEmpty {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2).fill(EditorStyle.accent.opacity(0.5)).frame(width: 3)
                                Text("“\(anchor.excerpt)”").font(.system(size: 14, design: .serif)).italic()
                                    .lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                        if let document = input.document {
                            let unchanged = ReviewInputSnapshot.hash(document.plainText ?? "") == input.contentHash
                            Button {
                                workspace.selection = .document(document.id)
                                if unchanged, let location = anchor.location, let length = anchor.length {
                                    workspace.editorialPassage = .init(documentID: document.id, location: location.intValue, length: length.intValue, token: UUID())
                                } else { workspace.editorialPassage = nil }
                            } label: {
                                Label(unchanged && anchor.location != nil ? "Show in manuscript" : "Open current text", systemImage: "arrow.up.left")
                                    .font(.system(size: 12, weight: .medium))
                            }.buttonStyle(.plain).foregroundStyle(EditorStyle.accent)
                        }
                    }
                }
            }
            Text(finding.recommendation).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            HStack(spacing: 16) {
                Button(finding.status == "addressed" ? "Reopen" : "Mark addressed") {
                    editor.updateFinding(finding, status: finding.status == "addressed" ? "open" : "addressed")
                }
                Button("Add a note") { showingNote.toggle() }
                Spacer(minLength: 0)
                Menu {
                    Button(finding.status == "dismissed" ? "Restore note" : "Dismiss suggestion") {
                        editor.updateFinding(finding, status: finding.status == "dismissed" ? "open" : "dismissed")
                    }
                    Text("\(finding.severity.capitalized) · \(finding.category)")
                } label: { Image(systemName: "ellipsis") }.editorMenuStyle().fixedSize()
                    .accessibilityLabel("Suggestion actions")
                    .help("Suggestion actions")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            if showingNote || !finding.userNote.isEmpty {
                TextField("Your note…", text: Binding(get: { finding.userNote }, set: { editor.updateFinding(finding, note: $0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.system(size: 13))
            }
        }
    }
}
