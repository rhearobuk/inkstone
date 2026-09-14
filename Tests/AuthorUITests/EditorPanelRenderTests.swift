#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import AuthorData
@testable import AuthorUI

@MainActor
final class EditorPanelRenderTests: XCTestCase {
    func testPanelRendersAtSidebarWidth() throws {
        guard ProcessInfo.processInfo.environment["AUTHOR_RENDER_EDITOR"] == "1" else { throw XCTSkip("Opt-in visual inspection artifact") }
        _ = NSApplication.shared
        let store = try AuthorDataStore(inMemory: true)
        let workspace = WorkspaceController(store: store)
        let project = try workspace.createProject(title: "The Night Library")
        let scene = try XCTUnwrap(project.documents.first { $0.kind == "Text" })
        scene.title = "Chapter One — The Arrival"
        scene.plainText = "The clock struck noon. Two minutes later, it was midnight. She opened the door."
        workspace.selection = .document(scene.id); try store.save()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "EditorPanelRenderTests"))
        defer { defaults.removePersistentDomain(forName: "EditorPanelRenderTests") }
        let settings = AISettingsStore(defaults: defaults)
        settings.selectedProvider = .appleIntelligence
        let review = store.editorialReviews.create {
            $0.project = project; $0.target = scene; $0.targetID = scene.id; $0.targetTitle = "The Arrival"
            $0.scope = "document"; $0.personaName = "Story / Developmental"; $0.personaInstructions = "Review pacing"
            $0.personaVersion = 1; $0.providerID = "appleIntelligence"; $0.modelID = "apple-system-on-device"
            $0.promptVersion = "1"; $0.schemaVersion = "1"; $0.parameters = "preview"; $0.environment = "preview"
            $0.status = "completed"; $0.createdAt = Date()
            $0.summary = "There’s a lovely sense of unease in this opening. The quiet action at the door makes me want to know what’s on the other side.\n\nI’d take another look at the shift in time. It’s intriguing, but I’m not yet sure whether it’s intentional."
        }
        let input = store.editorialInputs.create {
            $0.review = review; $0.document = scene; $0.documentID = scene.id; $0.title = scene.title
            $0.path = scene.title; $0.orderIndex = 0; $0.plainText = scene.plainText!; $0.contentHash = ReviewInputSnapshot.hash($0.plainText); $0.role = "manuscript"
        }
        let finding = store.editorialFindings.create {
            $0.review = review; $0.category = "story"; $0.severity = "moderate"; $0.title = "Help me follow the time shift"
            $0.explanation = "We move from noon to midnight in two minutes. If that’s deliberate, a small clue could help the reader feel unsettled rather than lost."
            $0.recommendation = "Consider whether this is a slip in the timeline or the first sign that something unusual is happening."
            $0.status = "open"; $0.userNote = ""; $0.createdAt = Date(); $0.modifiedAt = Date()
        }
        store.editorialAnchors.create {
            $0.finding = finding; $0.input = input; $0.excerpt = "Two minutes later, it was midnight."
            $0.location = 23; $0.length = 35
        }
        try store.save(); workspace.editorialReviews.refresh(); workspace.editorialReviews.selectedReviewID = review.id
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let workspaceView = AuthorWorkspaceView(controller: workspace, editorInitiallyVisible: true)
            .environmentObject(settings).environment(\.colorScheme, .light)
        let workspaceHost = NSHostingView(rootView: workspaceView)
        workspaceHost.appearance = NSAppearance(named: .aqua)
        workspaceHost.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let workspaceWindow = NSWindow(contentRect: workspaceHost.frame, styleMask: [.titled], backing: .buffered, defer: false)
        workspaceWindow.appearance = workspaceHost.appearance; workspaceWindow.contentView = workspaceHost
        workspaceHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        workspaceHost.layoutSubtreeIfNeeded()
        let workspaceBitmap = try XCTUnwrap(workspaceHost.bitmapImageRepForCachingDisplay(in: workspaceHost.bounds))
        workspaceHost.cacheDisplay(in: workspaceHost.bounds, to: workspaceBitmap)
        try XCTUnwrap(workspaceBitmap.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("work/editor-workspace.png"))
        for dark in [false, true] {
            let view = EditorPanelView(workspace: workspace, editor: workspace.editorialReviews, settings: settings)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 420, height: 1080)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 420, height: 1080)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = host.appearance
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: root.appendingPathComponent("work/editor-conversation-\(dark ? "dark" : "light").png"))
            XCTAssertGreaterThan(data.count, 1000)
        }
    }
}
#endif
