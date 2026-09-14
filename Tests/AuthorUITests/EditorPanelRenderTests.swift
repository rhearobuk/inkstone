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
        let host = NSHostingView(rootView: EditorPanelView(workspace: workspace, editor: workspace.editorialReviews, settings: settings))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 1050)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try data.write(to: root.appendingPathComponent("work/editor-panel.png"))
        XCTAssertGreaterThan(data.count, 1000)
    }
}
#endif
