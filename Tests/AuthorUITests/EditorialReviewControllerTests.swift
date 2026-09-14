import XCTest
import CoreData
import AuthorData
import AuthorAI
@testable import AuthorUI

private actor FakeEditor: EditorialReviewClient {
    var calls = 0
    let failFirst: Bool
    let delay: Bool
    init(failFirst: Bool = false, delay: Bool = false) { self.failFirst = failFirst; self.delay = delay }
    func review(_ request: ReviewRequest) async throws -> ReviewResponse {
        calls += 1
        if delay { try await Task.sleep(for: .seconds(10)) }
        if failFirst && calls == 1 { throw ReviewClientError.refused }
        if request.synthesis { return .init(summary: "Cross-section synthesis.", findings: []) }
        let id = request.material.split(separator: "\n")[0].replacingOccurrences(of: "DOCUMENT ", with: "")
        return .init(summary: "The scene needs clearer causality.", findings: [
            .init(category: "story", severity: "moderate", title: "Motivation", explanation: "The reason for opening the door is unclear.", recommendation: "Clarify the motivation.", evidence: [.init(documentID: id, excerpt: "opened the door")])
        ])
    }
}

@MainActor
final class EditorialReviewControllerTests: XCTestCase {
    private func setup(text: String = "She opened the door.") throws -> (AuthorDataStore, WorkspaceController, WritingProject, Document) {
        let store = try AuthorDataStore(inMemory: true)
        let workspace = WorkspaceController(store: store)
        let project = try workspace.createProject(title: "Test Novel")
        let scene = try XCTUnwrap(project.documents.first { $0.kind == DocumentKind.text.rawValue })
        scene.plainText = text; try store.save()
        return (store, workspace, project, scene)
    }
    private func run(_ workspace: WorkspaceController, project: WritingProject, root: Document, client: any EditorialReviewClient) throws {
        let inputs = try ReviewScopeResolver.resolve(root: root, project: project, scope: .document)
        let persona = try XCTUnwrap(workspace.editorialReviews.personas.first)
        workspace.editorialReviews.start(project: project, root: root, scope: .document, persona: persona, inputs: inputs,
                                        providerID: "test", modelID: "fake", client: client)
    }
    func testReviewPersistsWithoutChangingTextAndSurvivesDocumentDeletion() async throws {
        let (store, workspace, project, scene) = try setup()
        let original = scene.plainText
        try run(workspace, project: project, root: scene, client: FakeEditor())
        await workspace.editorialReviews.waitUntilFinished()
        let review = try XCTUnwrap(workspace.editorialReviews.reviews.first)
        XCTAssertEqual(review.status, "completed"); XCTAssertEqual(scene.plainText, original)
        XCTAssertEqual(review.inputs.first?.plainText, original)
        XCTAssertEqual(review.findings.count, 1)
        let finding = try XCTUnwrap(review.findings.first)
        XCTAssertEqual(finding.anchors.first?.location?.intValue, 4)
        workspace.editorialReviews.updateFinding(finding, status: "addressed", note: "Consider tomorrow")
        XCTAssertEqual(finding.status, "addressed"); XCTAssertEqual(scene.plainText, original)
        scene.plainText = "Changed"; try store.save()
        XCTAssertNotEqual(review.inputs.first?.contentHash, ReviewInputSnapshot.hash(scene.plainText!))
        store.context.delete(scene); try store.save()
        XCTAssertNil(review.target); XCTAssertNil(review.inputs.first?.document)
        XCTAssertEqual(review.inputs.first?.plainText, original)
        let reloaded = EditorialReviewController(store: store)
        XCTAssertEqual(reloaded.reviews.first?.findings.first?.userNote, "Consider tomorrow")
        store.context.delete(project); try store.save()
        XCTAssertEqual(try store.editorialReviews.count(), 0)
        XCTAssertEqual(try store.editorialInputs.count(), 0)
        XCTAssertEqual(try store.editorialFindings.count(), 0)
        XCTAssertEqual(try store.editorialAnchors.count(), 0)
    }
    func testRefusedChunkRetainsSuccessfulCoverage() async throws {
        let (_, workspace, project, scene) = try setup(text: String(repeating: "She opened the door.\n", count: 300))
        try run(workspace, project: project, root: scene, client: FakeEditor(failFirst: true))
        await workspace.editorialReviews.waitUntilFinished()
        let review = try XCTUnwrap(workspace.editorialReviews.reviews.first)
        XCTAssertEqual(review.status, "partial")
        XCTAssertEqual(review.chunks.filter { $0.status == "refused" }.count, 1)
        XCTAssertTrue(review.chunks.contains { $0.status == "completed" })
    }
    func testCancelPersistsTerminalState() async throws {
        let (_, workspace, project, scene) = try setup()
        try run(workspace, project: project, root: scene, client: FakeEditor(delay: true))
        workspace.editorialReviews.cancel()
        await workspace.editorialReviews.waitUntilFinished()
        XCTAssertEqual(workspace.editorialReviews.reviews.first?.status, "cancelled")
        XCTAssertFalse(workspace.editorialReviews.isRunning)
    }
    func testScopeUsesHierarchyAndCompileFlagsAndRejectsOtherProject() throws {
        let (store, workspace, project, scene) = try setup()
        let root = try XCTUnwrap(scene.parent)
        root.plainText = "Chapter introduction"; root.includeInCompile = false
        let second = try workspace.addDocument(title: "Second", kind: .text, parentID: root.id)
        second.plainText = "Second scene"; second.includeInCompile = false
        try store.save()
        let included = try ReviewScopeResolver.resolve(root: root, project: project, scope: .chapter)
        XCTAssertEqual(included.map(\.documentID), [scene.id])
        let all = try ReviewScopeResolver.resolve(root: root, project: project, scope: .novel, includeExcluded: true)
        XCTAssertEqual(all.map(\.documentID), [root.id, scene.id, second.id])
        let other = try workspace.createProject(title: "Other")
        XCTAssertThrowsError(try ReviewScopeResolver.resolve(root: root, project: other, scope: .novel))
    }
    func testInterruptedRunIsRecoveredWithoutResending() async throws {
        let (store, workspace, project, scene) = try setup()
        try run(workspace, project: project, root: scene, client: FakeEditor())
        await workspace.editorialReviews.waitUntilFinished()
        let review = try XCTUnwrap(workspace.editorialReviews.reviews.first)
        review.status = "running"
        review.chunks.first?.status = "running"
        try store.save()
        let recovered = EditorialReviewController(store: store)
        XCTAssertEqual(recovered.reviews.first?.status, "interrupted")
        XCTAssertEqual(recovered.reviews.first?.chunks.first?.status, "interrupted")
        XCTAssertFalse(recovered.isRunning)
    }
    func testPersonaEditDoesNotChangeHistoryAndSeedIsIdempotent() async throws {
        let (store, workspace, project, scene) = try setup()
        try EditorPersonaLibrary.seed(in: store)
        XCTAssertEqual(try store.editorPersonas.count(), 6)
        try run(workspace, project: project, root: scene, client: FakeEditor())
        await workspace.editorialReviews.waitUntilFinished()
        let review = try XCTUnwrap(workspace.editorialReviews.reviews.first)
        let rubric = review.personaInstructions
        let persona = try XCTUnwrap(review.persona)
        persona.instructions = "Changed"; store.context.delete(persona); try store.save()
        XCTAssertNil(review.persona); XCTAssertEqual(review.personaInstructions, rubric)
    }
}
