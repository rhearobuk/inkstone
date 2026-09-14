import AuthorData
import AuthorAI
import CoreData
import SwiftUI

@MainActor
public final class EditorialReviewController: ObservableObject {
    private let store: AuthorDataStore
    @Published public private(set) var reviews: [EditorialReview] = []
    @Published public private(set) var personas: [EditorPersona] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var progress = ""
    @Published public var errorMessage: String?
    @Published public var selectedReviewID: UUID?
    private var task: Task<Void, Never>?

    public init(store: AuthorDataStore) {
        self.store = store
        do {
            try EditorPersonaLibrary.seed(in: store)
            for run in try store.editorialReviews.fetchAll() where ["queued", "running"].contains(run.status) {
                run.status = "interrupted"; run.finishedAt = Date()
                run.errorMessage = "The app closed before this review finished. Rerun explicitly to try again."
                for chunk in run.chunks where ["queued", "running"].contains(chunk.status) { chunk.status = "interrupted" }
            }
            try store.save(); refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    public func refresh() {
        do {
            reviews = try store.editorialReviews.fetchAll(sortedBy: [NSSortDescriptor(key: "createdAt", ascending: false)])
            personas = try store.editorPersonas.fetchAll(sortedBy: [NSSortDescriptor(key: "name", ascending: true)])
        } catch { errorMessage = error.localizedDescription }
    }
    public func savePersona(name: String, instructions: String, existing: EditorPersona? = nil) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !instructions.isEmpty else { return }
        guard instructions.utf8.count <= 1600 else { errorMessage = "Please shorten the persona rubric for on-device review."; return }
        let persona: EditorPersona
        if let existing, !existing.isBuiltIn { persona = existing; persona.version += 1 }
        else {
            persona = store.editorPersonas.create { $0.createdAt = Date(); $0.version = 1; $0.presetKey = "custom"; $0.isBuiltIn = false }
        }
        persona.name = name; persona.instructions = instructions; persona.modifiedAt = Date()
        save()
    }
    public func deletePersona(_ persona: EditorPersona) {
        guard !persona.isBuiltIn else { return }
        store.context.delete(persona); save()
    }
    public func updateFinding(_ finding: EditorialFinding, status: String? = nil, note: String? = nil) {
        if let status, ["open", "addressed", "dismissed"].contains(status) { finding.status = status }
        if let note { finding.userNote = note }
        finding.modifiedAt = Date(); save()
    }
    public func deleteReview(_ review: EditorialReview) {
        guard !["queued", "running"].contains(review.status) else { return }
        store.context.delete(review); save()
    }
    private func save() {
        do { try store.save(); refresh() } catch { errorMessage = error.localizedDescription }
    }
    public func cancel() { task?.cancel(); progress = "Cancelling…" }
    public func waitUntilFinished() async { await task?.value }

    public func start(project: WritingProject, root: Document, scope: EditorialScope, persona: EditorPersona,
                      inputs: [ReviewInputSnapshot], providerID: String, modelID: String,
                      instructions: String = "", previousReviewID: UUID? = nil,
                      client: any EditorialReviewClient) {
        guard !isRunning, !inputs.filter({ $0.role == "manuscript" }).isEmpty else { return }
        let rubric = persona.instructions + (instructions.isEmpty ? "" : "\nAdditional editorial focus: " + instructions)
        guard rubric.utf8.count <= 2000 else { errorMessage = "Shorten the persona and review instructions to fit on-device review."; return }
        let context = inputs.filter { $0.role == "context" }.map { "\($0.title): \($0.text)" }.joined(separator: "\n")
        guard context.utf8.count <= 1200 else { errorMessage = "Choose a shorter Story Bible summary for on-device review. No context was truncated."; return }
        errorMessage = nil
        do {
            try store.save()
            let review = store.editorialReviews.create {
                $0.project = project; $0.target = root; $0.targetID = root.id; $0.targetTitle = root.title; $0.scope = scope.rawValue
                $0.persona = persona; $0.personaName = persona.name; $0.personaInstructions = rubric; $0.personaVersion = persona.version
                $0.providerID = providerID; $0.modelID = modelID; $0.promptVersion = EditorPromptBuilder.version; $0.schemaVersion = "1"
                $0.parameters = "chunkUTF8Bytes=2400; maxFindingsPerChunk=4; contextUTF8Bytes=1200"
                $0.environment = ProcessInfo.processInfo.operatingSystemVersionString + "; app=" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")
                $0.status = "queued"; $0.summary = ""; $0.createdAt = Date(); $0.previousReviewID = previousReviewID
            }
            var index: Int64 = 0
            for (position, snapshot) in inputs.enumerated() {
                let input = store.editorialInputs.create {
                    $0.review = review; $0.document = try? store.documents.fetch(id: snapshot.documentID)
                    $0.documentID = snapshot.documentID; $0.title = snapshot.title; $0.path = snapshot.path
                    $0.orderIndex = Int64(position); $0.plainText = snapshot.text; $0.contentHash = snapshot.hash; $0.role = snapshot.role
                }
                if snapshot.role == "manuscript" {
                    for segment in ReviewChunkPlanner.split(snapshot.text) {
                        store.editorialChunks.create {
                            $0.review = review; $0.input = input; $0.stage = "analysis"; $0.orderIndex = index
                            $0.location = Int64(segment.location); $0.length = Int64(segment.text.utf16.count)
                            $0.status = "queued"; $0.attempts = 0; $0.summary = ""; $0.createdAt = Date()
                        }
                        index += 1
                    }
                }
            }
            try store.save(); selectedReviewID = review.id; refresh(); isRunning = true
            task = Task { [weak self] in await self?.execute(review, client: client, context: context) }
        } catch { errorMessage = error.localizedDescription }
    }

    private func execute(_ review: EditorialReview, client: any EditorialReviewClient, context: String) async {
        defer { isRunning = false; progress = ""; refresh() }
        do {
            review.status = "running"; try store.save()
            let chunks = review.chunks.sorted { $0.orderIndex < $1.orderIndex }
            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                guard !review.isDeleted, let input = chunk.input else { throw CancellationError() }
                chunk.status = "running"; chunk.attempts += 1; try store.save()
                progress = "Reviewing section \(index + 1) of \(chunks.count)"
                let segment = (input.plainText as NSString).substring(with: NSRange(location: Int(chunk.location), length: Int(chunk.length)))
                let material = "DOCUMENT \(input.documentID.uuidString)\n\(input.title)\n\(segment)" + (context.isEmpty ? "" : "\nREFERENCE CONTEXT\n\(context)")
                do {
                    let response = try await client.review(.init(rubric: review.personaInstructions, material: material))
                    try Task.checkCancellation()
                    guard !review.isDeleted else { throw CancellationError() }
                    let validated = try ReviewResponseValidator.validate(response, allowedDocumentIDs: [input.documentID.uuidString])
                    persist(validated, review: review, segment: (input, NSRange(location: Int(chunk.location), length: Int(chunk.length))))
                    chunk.summary = validated.summary; chunk.status = "completed"; chunk.finishedAt = Date(); try store.save(); refresh()
                } catch is CancellationError { throw CancellationError() }
                catch {
                    chunk.status = (error as? ReviewClientError).map { if case .refused = $0 { return "refused" }; return "failed" } ?? "failed"
                    chunk.errorMessage = error.localizedDescription; chunk.finishedAt = Date(); try store.save()
                }
            }
            let completed = chunks.filter { $0.status == "completed" }
            if !completed.isEmpty {
                var summaries = completed.map { "DOCUMENT \($0.input?.documentID.uuidString ?? "unknown")\n\($0.summary)" }
                // Hierarchical synthesis accounts for every completed summary; it never trims input to fit.
                var level = 0
                while summaries.count > 1 {
                    level += 1
                    guard level <= 16 else { throw ReviewClientError.contextExceeded }
                    var batches: [String] = []; var current = ""
                    for summary in summaries {
                        guard summary.utf8.count <= 4800 else { throw ReviewClientError.contextExceeded }
                        if !current.isEmpty && (current.utf8.count + summary.utf8.count > 4800) { batches.append(current); current = "" }
                        current += summary + "\n"
                    }
                    if !current.isEmpty { batches.append(current) }
                    var next: [String] = []
                    for (i, batch) in batches.enumerated() {
                        try Task.checkCancellation(); progress = "Combining review findings (pass \(level), group \(i + 1))"
                        let chunk = store.editorialChunks.create {
                            $0.review = review; $0.stage = "synthesis"; $0.orderIndex = Int64(review.chunks.count)
                            $0.location = 0; $0.length = 0; $0.status = "running"; $0.attempts = 1; $0.summary = ""; $0.createdAt = Date()
                        }
                        try store.save()
                        let response = try await client.review(.init(rubric: review.personaInstructions + "\nKeep summary under 500 characters. Synthesis findings must cite original evidence or have no anchors.", material: batch, synthesis: true))
                        try Task.checkCancellation()
                        let validated = try ReviewResponseValidator.validate(response, allowedDocumentIDs: Set(review.inputs.map { $0.documentID.uuidString }))
                        persist(validated, review: review, segment: nil)
                        chunk.summary = validated.summary; chunk.status = "completed"; chunk.finishedAt = Date(); try store.save()
                        next.append(validated.summary)
                    }
                    summaries = next
                }
                review.summary = summaries.first ?? ""
            }
            if completed.count == chunks.count { review.status = "completed" }
            else if !completed.isEmpty { review.status = "partial" }
            else { review.status = chunks.allSatisfy { $0.status == "refused" } ? "refused" : "failed" }
            if completed.count != chunks.count { review.errorMessage = "\(completed.count) of \(chunks.count) manuscript sections reviewed. Inspect section errors below." }
        } catch {
            if !review.isDeleted {
                if error is CancellationError || Task.isCancelled { review.status = "cancelled" }
                else { review.status = review.chunks.contains { $0.status == "completed" } ? "partial" : "failed" }
                review.errorMessage = error.localizedDescription
                for chunk in review.chunks where ["queued", "running"].contains(chunk.status) {
                    chunk.status = review.status == "cancelled" ? "cancelled" : "failed"; chunk.errorMessage = error.localizedDescription; chunk.finishedAt = Date()
                }
            }
        }
        if !review.isDeleted {
            review.finishedAt = Date()
            if let project = review.project, !project.isDeleted {
                store.provenanceEvents.create {
                    $0.project = project; $0.eventType = "editorialReview"; $0.agent = "model"; $0.agentVersion = review.modelID
                    $0.timestamp = Date(); $0.sourceIdentifier = review.id.uuidString
                    $0.details = "\(review.personaName): \(review.status)"
                }
            }
            save()
        }
    }

    private func persist(_ response: ReviewResponse, review: EditorialReview,
                         segment: (EditorialReviewInput, NSRange)?) {
        if let count = response.inputTokens { review.inputTokens = NSNumber(value: (review.inputTokens?.intValue ?? 0) + count) }
        if let count = response.outputTokens { review.outputTokens = NSNumber(value: (review.outputTokens?.intValue ?? 0) + count) }
        if let model = response.resolvedModelID, !review.parameters.contains("resolvedModel=") { review.parameters += "; resolvedModel=" + model }
        for item in response.findings {
            let existing = review.findings.first { $0.title == item.title && $0.explanation == item.explanation && $0.recommendation == item.recommendation }
            let finding = existing ?? store.editorialFindings.create {
                $0.review = review; $0.category = item.category; $0.severity = item.severity; $0.title = item.title
                $0.explanation = item.explanation; $0.recommendation = item.recommendation; $0.status = "open"; $0.userNote = ""
                $0.createdAt = Date(); $0.modifiedAt = Date()
            }
            for evidence in item.evidence {
                guard let input = review.inputs.first(where: { $0.documentID.uuidString == evidence.documentID }) else { continue }
                let source: String; let offset: Int
                if let segment { source = (segment.0.plainText as NSString).substring(with: segment.1); offset = segment.1.location }
                else { source = input.plainText; offset = 0 }
                let range = ReviewResponseValidator.uniqueRange(excerpt: evidence.excerpt, in: source)
                if finding.anchors.contains(where: { $0.input == input && $0.excerpt == (range == nil ? "" : evidence.excerpt) && $0.location?.intValue == range.map({ $0.location + offset }) }) { continue }
                store.editorialAnchors.create {
                    $0.finding = finding; $0.input = input
                    // Unverifiable quotations are never presented as manuscript evidence.
                    $0.excerpt = range == nil ? "" : evidence.excerpt
                    if let range { $0.location = NSNumber(value: range.location + offset); $0.length = NSNumber(value: range.length) }
                }
            }
            if finding.anchors.isEmpty, let input = segment?.0 {
                store.editorialAnchors.create { $0.finding = finding; $0.input = input; $0.excerpt = "" }
            }
        }
    }
}
