import XCTest

@MainActor
final class ReviewWalkthroughTests: XCTestCase {
    private let app = XCUIApplication()
    private let chapter = "The Girl in the Chicken Coop"

    override func setUp() async throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        #endif
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDown() async throws {
        if let testRun, testRun.failureCount > 0 {
            capture("Failure")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Accessibility hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    func testCoreAuthoringWalkthrough() throws {
        launchWorkspace()
        try createAndEditProject()
        try writeScene()
        try addStoryBibleEntry()
        try showExport()
    }

    func testBinderMoveWalkthrough() throws {
        launchWorkspace()
        try createAndEditProject()
        try writeScene()
        try moveScene()
    }

    /// Uses the normal importer and a real on-device AI request; no seeded model responses.
    /// On iPad/visionOS select the supplied .scriv project in the file picker when prompted.
    func testImportAndAppleIntelligenceWalkthrough() throws {
        launchWorkspace()
        #if os(macOS)
        activate(app.menuBars.menuBarItems["Window"])
        activate(app.menuItems["Fill"])
        #endif
        XCTAssertTrue(element("workspace.import").waitForExistence(timeout: 30))

        try XCTContext.runActivity(named: "Import the supplied Scrivener project") { _ in
            activateToolbar("workspace.import")
            activate(element("import.source"))
            #if os(macOS)
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("The Wonderful World of Oz.scriv")
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path),
                          "Place the supplied .scriv project at the repository root; it is not committed.")
            app.typeKey("g", modifierFlags: [.command, .shift])
            app.typeText(source.path)
            app.typeKey(.return, modifierFlags: [])
            activate(app.dialogs["open-panel"].buttons["OKButton"])
            #endif
            let confirm = element("import.confirm")
            wait(for: confirm, predicate: "enabled == true", timeout: 180,
                 message: "Select The Wonderful World of Oz.scriv in the system file picker.")
            replaceText(in: app.textFields["import.projectTitle"], with: uniqueTitle("Oz Import"))
            activate(confirm)
            XCTAssertTrue(dialog("Import Complete").waitForExistence(timeout: 180), app.debugDescription)
            activate(dialog("Import Complete").buttons["OK"])
            capture("06 - Scrivener import complete")
        }

        try XCTContext.runActivity(named: "Review only chapter one of Ozma of Oz") { _ in
            try expand("Narrative", revealing: "Manuscript")
            try expand("Manuscript", revealing: "Ozma of Oz")
            try expand("Ozma of Oz", revealing: chapter)
            activate(binderTitle(chapter))
            assertValue(app.textFields["document.title"], equals: chapter)
            let body = app.textViews["document.body"]
            XCTAssertTrue(body.waitForExistence(timeout: 15))
            XCTAssertFalse((body.value as? String ?? "").isEmpty, "The imported chapter must contain text.")
            capture("07 - Ozma of Oz chapter one")

            activateToolbar("workspace.assistant")
            activate(menuItem("AI Editor"))
            activate(element("editor.change"))
            activate(element("editor.provider"))
            activate(menuItem("Apple Intelligence"))
            activate(element("editor.optionsDone"))
            let target = element("editor.target")
            let targetMatches = target.label == chapter || (target.value as? String) == chapter
            XCTAssertTrue(targetMatches, "Do not send another chapter or the whole anthology for review.")
            replaceText(in: element("editor.instructions"),
                        with: "Review this chapter for clarity, pacing, and continuity. Do not rewrite the manuscript.")
            let review = element("editor.review")
            wait(for: review, predicate: "enabled == true", timeout: 30,
                 message: "Apple Intelligence must be enabled, supported, and downloaded on this physical device.")
            activate(review)

            let completed = element("editor.result.completed")
            let didComplete = completed.waitForExistence(timeout: 240)
            if !didComplete, app.buttons["Stop"].exists {
                activate(app.buttons["Stop"])
            }
            XCTAssertTrue(didComplete,
                          "A complete real review is required. A refusal, error, partial review, or timeout is not a pass.\n\(app.debugDescription)")
            XCTAssertFalse(completed.label.isEmpty)
            capture("08 - Completed Apple Intelligence review")
        }
    }

    private func createAndEditProject() throws {
        XCTContext.runActivity(named: "Launch and create a new writing project") { _ in
            dismissKeyboard()
            XCTAssertTrue(element("workspace.add").waitForExistence(timeout: 30), app.debugDescription)
            capture("01 - Launch")
            activateToolbar("workspace.add")
            activate(menuItem("New Project"))
            let alert = dialog("New Project")
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            alert.textFields.firstMatch.typeText(uniqueTitle("Harbor Lights"))
            activate(alert.buttons["Create"])
            activate(binderTitle("Project Definition"))
            replaceText(in: app.textFields["project.author"], with: "Inkstone Review Demo")
        }
        try XCTContext.runActivity(named: "Enter multiword book metadata") { _ in
            try expand("Narrative", revealing: "Untitled Novel")
            activate(binderTitle("Untitled Novel"))
            let series = app.textFields["metadata.system.book.seriesName"]
            replaceText(in: series, with: "Harbor")
            series.typeText(" ")
            assertValue(series, equals: "Harbor ")
            series.typeText("Stories")
            assertValue(series, equals: "Harbor Stories")
            replaceText(in: app.textFields["metadata.system.book.subtitle"], with: "A Journey Home")
            capture("02 - Book metadata with spaces")
        }
    }

    private func writeScene() throws {
        try XCTContext.runActivity(named: "Write a scene and verify saved text") { _ in
            try expand("Untitled Novel", revealing: "Opening Scene")
            activate(binderTitle("Opening Scene"))
            let body = app.textViews["document.body"]
            XCTAssertTrue(body.waitForExistence(timeout: 15))
            activate(body)
            let passage = "Mara reached the harbor before sunrise.\nA lantern waited beside the blue door."
            body.typeText(passage)
            assertValue(body, equals: passage)
            activate(binderTitle("Untitled Novel"))
            activate(binderTitle("Opening Scene"))
            assertValue(body, equals: passage)
            capture("03 - Manuscript writing")
        }
    }

    private func moveScene() throws {
        try XCTContext.runActivity(named: "Move a scene into a new folder") { _ in
            activate(binderTitle("Untitled Novel"))
            activateToolbar("workspace.add")
            activate(menuItem("New Folder"))
            replaceText(in: app.textFields["document.title"], with: "Harbor Chapter")
            activate(binderTitle("Untitled Novel"))
            activateToolbar("workspace.add")
            activate(menuItem("New Scene"))
            replaceText(in: app.textFields["document.title"], with: "The Lantern")
            activate(binderTitle("Untitled Novel"))
            replaceText(in: app.textFields["metadata.system.book.seriesName"], with: "Harbor Stories")

            let source = binderTitle("The Lantern")
            let destination = binderTitle("Harbor Chapter")
            XCTAssertTrue(source.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(destination.waitForExistence(timeout: 10), app.debugDescription)
            #if os(macOS)
            source.click(forDuration: 1, thenDragTo: destination)
            #else
            source.press(forDuration: 1, thenDragTo: destination)
            #endif
            // The destination starts collapsed: disappearance, then reappearance on
            // expansion proves this was a hierarchy move, not just a drag animation.
            wait(for: source, predicate: "exists == false", timeout: 15,
                 message: "The dropped scene should now be inside the collapsed chapter.")
            try expand("Harbor Chapter", revealing: "The Lantern")
            capture("04 - Binder reorganization")
        }
    }

    private func addStoryBibleEntry() throws {
        XCTContext.runActivity(named: "Create a Story Bible place") { _ in
            activateToolbar("workspace.add")
            activate(menuItem("New Place"))
            let alert = dialog("New Story Bible Entry")
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            alert.textFields.firstMatch.typeText("Moon Harbor")
            activate(alert.buttons["Create"])
            assertValue(app.textFields["storyBible.name"], equals: "Moon Harbor")
            replaceText(in: element("storyBible.description"),
                        with: "A quiet port where every house keeps a lantern by the door.")
            capture("05 - Story Bible")
        }
    }

    private func showExport() throws {
        XCTContext.runActivity(named: "Render an export preview") { _ in
            activate(binderTitle("Untitled Novel"))
            activateToolbar("workspace.export")
            let readiness = element("export.readiness")
            XCTAssertTrue(readiness.waitForExistence(timeout: 30), app.debugDescription)
            wait(for: readiness,
                 predicate: "label BEGINSWITH 'Ready to Export' OR value BEGINSWITH 'Ready to Export'",
                 timeout: 15, message: "Export must report Ready to Export.")
            capture("Export preview")
            activate(app.buttons["Cancel"].firstMatch)
        }
    }

    private func expand(_ title: String, revealing child: String) throws {
        if binderTitle(child).exists { return }
        let label = binderTitle(title)
        XCTAssertTrue(label.waitForExistence(timeout: 15), "Missing binder item: \(title)\n\(app.debugDescription)")
        #if os(macOS)
        activate(label)
        app.typeKey(.rightArrow, modifierFlags: [])
        #else
        activate(element("binder.disclosure.\(title)"))
        #endif
        XCTAssertTrue(binderTitle(child).waitForExistence(timeout: 15),
                      "Expanding \(title) should reveal \(child).\n\(app.debugDescription)")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func dialog(_ title: String) -> XCUIElement {
        #if os(macOS)
        app.sheets.containing(.staticText, identifier: title).firstMatch
        #else
        app.alerts[title]
        #endif
    }

    private func launchWorkspace() {
        app.launch()
        #if os(macOS)
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
        }
        #endif
    }

    private func dismissKeyboard() {
        #if os(iOS)
        let hideKeyboard = app.buttons["Hide keyboard"].firstMatch
        if hideKeyboard.exists {
            hideKeyboard.tap()
        }
        #endif
    }

    private func activateToolbar(_ identifier: String) {
        dismissKeyboard()
        activate(element(identifier))
    }

    private func binderTitle(_ title: String) -> XCUIElement {
        #if os(macOS)
        element("binder.title.\(title)")
        #else
        app.staticTexts["binder.title.\(title)"].firstMatch
        #endif
    }

    private func menuItem(_ title: String) -> XCUIElement {
        #if os(macOS)
        app.menuItems[title].firstMatch
        #else
        app.buttons[title].firstMatch
        #endif
    }

    private func activate(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        activate(field)
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #else
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        #endif
        field.typeText(text)
        assertValue(field, equals: text)
    }

    private func assertValue(_ element: XCUIElement, equals expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        if XCTWaiter.wait(for: [expectation], timeout: 15) != .completed {
            let actual = element.exists ? String(describing: element.value) : "element unavailable"
            XCTFail("Expected \(expected.debugDescription), got \(actual)", file: file, line: line)
        }
    }

    private func wait(for element: XCUIElement, predicate: String, timeout: TimeInterval, message: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "\(message)\n\(app.debugDescription)")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func uniqueTitle(_ prefix: String) -> String {
        "\(prefix) \(UUID().uuidString.prefix(8))"
    }
}
