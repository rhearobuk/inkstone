import AuthorData
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(visionOS)
import UIKit
#endif

struct DocumentContentView: View {
    let document: Document
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        if let imageData = imageResource?.data {
            PlatformImageView(data: imageData)
        } else if let rtfData = rtfResource?.data,
                  let attributedText = try? NSAttributedString(
                      data: rtfData,
                      options: [.documentType: NSAttributedString.DocumentType.rtf],
                      documentAttributes: nil
                  ) {
            richTextEditor(attributedText: attributedText)
        } else if document.kind == DocumentKind.text.rawValue {
            richTextEditor(attributedText: NSAttributedString(string: document.plainText ?? ""))
        } else {
            PlainDocumentEditor(text: document.plainText ?? "", passage: passage) { text in
                controller.updateDocument(
                    documentID: document.id,
                    title: document.title,
                    synopsis: document.synopsis,
                    plainText: text
                )
            }
            .id(document.id)

        }
    }

    private func richTextEditor(attributedText: NSAttributedString) -> some View {
            RichTextEditor(attributedText: attributedText, passage: passage) { updatedText in
                do {
                    let range = NSRange(location: 0, length: updatedText.length)
                    let data = try updatedText.data(
                        from: range,
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    controller.updateDocumentRichText(
                        documentID: document.id,
                        rtfData: data,
                        plainText: updatedText.string
                    )
                } catch {
                    controller.report(error)
                }
            } onCommit: {
                controller.flushPendingChanges()
            }
            .id(document.id)
    }

    private var passage: EditorialPassage? {
        controller.editorialPassage?.documentID == document.id ? controller.editorialPassage : nil
    }

    private var rtfResource: ContentResource? {
        document.resources.first {
            $0.role == "content"
                && $0.mediaType == "application/rtf"
                && !$0.isSourcePreserved
        } ?? document.resources.first {
            $0.role == "content" && $0.mediaType == "application/rtf"
        }
    }

    private var imageResource: ContentResource? {
        document.resources.first {
            $0.role == "content" && $0.mediaType.hasPrefix("image/")
        }
    }
}

#if os(macOS)
private struct RichTextEditor: NSViewRepresentable {
    let attributedText: NSAttributedString
    let passage: EditorialPassage?
    let onChange: (NSAttributedString) -> Void
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> RichTextEditorContainerView {
        let scrollView = NSTextView.scrollableTextView()
        let editorView = RichTextEditorContainerView(scrollView: scrollView, coordinator: context.coordinator)
        guard let textView = editorView.textView else { return editorView }
        textView.setAccessibilityIdentifier("document.body")
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsImageEditing = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.usesRuler = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        return editorView
    }

    func updateNSView(_ editorView: RichTextEditorContainerView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCommit = onCommit
        guard let textView = editorView.textView else { return }
        // Only re-apply the model's text when its characters actually differ from what the
        // editor shows. Comparing attributed strings would never match, because saving round-trips
        // the text through RTF, which normalises attributes — that mismatch fed an endless
        // save -> publish -> setAttributedString -> save loop.
        if !textView.hasMarkedText(),
           (textView.window?.firstResponder !== textView
                || !context.coordinator.hasUncommittedChanges),
           textView.string != attributedText.string {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
            textView.usesAdaptiveColorMappingForDarkAppearance = true
            context.coordinator.isUpdating = true
            textView.textStorage?.setAttributedString(attributedText)
            textView.textStorage?.delegate = context.coordinator
            context.coordinator.hasUncommittedChanges = false
            context.coordinator.isUpdating = false
        }

        if let passage, passage.token != context.coordinator.lastPassage,
           passage.location >= 0, passage.length >= 0,
           passage.location + passage.length <= textView.string.utf16.count {
            let range = NSRange(location: passage.location, length: passage.length)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            context.coordinator.lastPassage = passage.token
        }
    }

    static func dismantleNSView(_ editorView: RichTextEditorContainerView, coordinator: Coordinator) {
        coordinator.commitPendingChange()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var onChange: (NSAttributedString) -> Void
        var onCommit: () -> Void
        var isUpdating = false
        var hasUncommittedChanges = false
        var lastPassage: UUID?
        private var pendingChange: DispatchWorkItem?
        weak var textView: NSTextView?

        init(onChange: @escaping (NSAttributedString) -> Void, onCommit: @escaping () -> Void) {
            self.onChange = onChange
            self.onCommit = onCommit
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationWillResignActive),
                name: NSApplication.willResignActiveNotification,
                object: nil,
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            scheduleChange(from: textView)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            // Attribute-only edits (font panel, colour panel, ruler) don't post textDidChange, so
            // they're captured here. Character edits are already covered by textDidChange, and
            // system attribute fixing happens during layout — reporting it synchronously would
            // publish controller changes from inside a SwiftUI view update.
            guard !isUpdating,
                  editedMask.contains(.editedAttributes),
                  !editedMask.contains(.editedCharacters),
                  let textView,
                  textView.window?.firstResponder === textView else { return }
            scheduleChange(from: textView)
        }

        private func scheduleChange(from textView: NSTextView) {
            pendingChange?.cancel()
            hasUncommittedChanges = true
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, !isUpdating, let textView else { return }
                onChange(textView.attributedString())
                pendingChange = nil
                hasUncommittedChanges = false
            }
            pendingChange = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }

        func commitPendingChange() {
            pendingChange?.cancel()
            pendingChange = nil
            guard !isUpdating else { return }
            if hasUncommittedChanges, let textView {
                onChange(textView.attributedString())
                hasUncommittedChanges = false
            }
            onCommit()
        }

        @objc
        private func applicationWillResignActive() {
            commitPendingChange()
        }

        @objc
        func toggleBold() {
            toggleFontTrait(.boldFontMask)
        }

        @objc
        func toggleItalic() {
            toggleFontTrait(.italicFontMask)
        }

        @objc
        func toggleUnderline() {
            toggleAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                defaultIsEnabled: false
            )
        }

        @objc
        func decreaseFontSize() {
            changeFontSize(by: -1)
        }

        @objc
        func increaseFontSize() {
            changeFontSize(by: 1)
        }

        @objc
        func showFontPanel() {
            focusEditor()
            NSFontManager.shared.orderFrontFontPanel(nil)
        }

        @objc
        func showColorPanel() {
            focusEditor()
            let colorPanel = NSColorPanel.shared
            colorPanel.setTarget(textView)
            colorPanel.setAction(#selector(NSTextView.changeColor(_:)))
            colorPanel.orderFront(nil)
        }

        @objc
        func alignLeft() {
            setAlignment(.left)
        }

        @objc
        func alignCenter() {
            setAlignment(.center)
        }

        @objc
        func alignRight() {
            setAlignment(.right)
        }

        @objc
        func alignJustified() {
            setAlignment(.justified)
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask) {
            applyFormatting { textView in
                let selection = textView.selectedRange()
                if selection.length == 0 {
                    var attributes = textView.typingAttributes
                    attributes[.font] = toggledFont(attributes[.font] as? NSFont, trait: trait, fallback: textView.font)
                    textView.typingAttributes = attributes
                    return
                }

                textView.textStorage?.beginEditing()
                textView.textStorage?.enumerateAttribute(.font, in: selection) { value, range, _ in
                    let font = toggledFont(value as? NSFont, trait: trait, fallback: textView.font)
                    textView.textStorage?.addAttribute(.font, value: font, range: range)
                }
                textView.textStorage?.endEditing()
                textView.setSelectedRange(selection)
            }
        }

        private func toggledFont(_ font: NSFont?, trait: NSFontTraitMask, fallback: NSFont?) -> NSFont {
            let font = font ?? fallback ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let manager = NSFontManager.shared
            if manager.traits(of: font).contains(trait) {
                return manager.convert(font, toNotHaveTrait: trait)
            }
            return manager.convert(font, toHaveTrait: trait)
        }

        private func changeFontSize(by delta: CGFloat) {
            applyFormatting { textView in
                let selection = textView.selectedRange()
                if selection.length == 0 {
                    var attributes = textView.typingAttributes
                    attributes[.font] = resizedFont(attributes[.font] as? NSFont, delta: delta, fallback: textView.font)
                    textView.typingAttributes = attributes
                    return
                }

                textView.textStorage?.beginEditing()
                textView.textStorage?.enumerateAttribute(.font, in: selection) { value, range, _ in
                    let font = resizedFont(value as? NSFont, delta: delta, fallback: textView.font)
                    textView.textStorage?.addAttribute(.font, value: font, range: range)
                }
                textView.textStorage?.endEditing()
                textView.setSelectedRange(selection)
            }
        }

        private func resizedFont(_ font: NSFont?, delta: CGFloat, fallback: NSFont?) -> NSFont {
            let font = font ?? fallback ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            return NSFontManager.shared.convert(font, toSize: max(1, font.pointSize + delta))
        }

        private func toggleAttribute(_ key: NSAttributedString.Key, value: Any, defaultIsEnabled: Bool) {
            applyFormatting { textView in
                let selection = textView.selectedRange()
                if selection.length == 0 {
                    var attributes = textView.typingAttributes
                    let isEnabled = (attributes[key] as? Int).map { $0 != 0 } ?? defaultIsEnabled
                    attributes[key] = isEnabled ? 0 : value
                    textView.typingAttributes = attributes
                    return
                }

                let currentValue = textView.textStorage?.attribute(key, at: selection.location, effectiveRange: nil) as? Int
                let isEnabled = (currentValue ?? 0) != 0
                textView.textStorage?.addAttribute(key, value: isEnabled ? 0 : value, range: selection)
                textView.setSelectedRange(selection)
            }
        }

        private func setAlignment(_ alignment: NSTextAlignment) {
            applyFormatting { textView in
                let selection = textView.selectedRange()
                let paragraphRange = (textView.string as NSString).paragraphRange(for: selection)
                textView.textStorage?.beginEditing()
                textView.textStorage?.enumerateAttribute(.paragraphStyle, in: paragraphRange) { value, range, _ in
                    let paragraphStyle = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paragraphStyle.alignment = alignment
                    textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
                }
                textView.textStorage?.endEditing()
                textView.setSelectedRange(selection)
            }
        }

        private func applyFormatting(_ format: (NSTextView) -> Void) {
            guard let textView else { return }
            focusEditor()
            format(textView)
            onChange(textView.attributedString())
        }

        private func focusEditor() {
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }
}

private final class RichTextEditorContainerView: NSView {
    let scrollView: NSScrollView

    var textView: NSTextView? {
        scrollView.documentView as? NSTextView
    }

    init(scrollView: NSScrollView, coordinator: RichTextEditor.Coordinator) {
        self.scrollView = scrollView
        super.init(frame: .zero)

        let toolbar = RichTextToolbarView(coordinator: coordinator)
        addSubview(toolbar)
        addSubview(scrollView)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RichTextToolbarView: NSVisualEffectView {
    init(coordinator: RichTextEditor.Coordinator) {
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        state = .active

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addButton(
            symbol: "bold",
            fallbackTitle: "B",
            tooltip: "Bold",
            action: #selector(RichTextEditor.Coordinator.toggleBold),
            target: coordinator,
            to: stack,
            fontTraits: [.boldFontMask]
        )
        addButton(
            symbol: "italic",
            fallbackTitle: "I",
            tooltip: "Italic",
            action: #selector(RichTextEditor.Coordinator.toggleItalic),
            target: coordinator,
            to: stack,
            fontTraits: [.italicFontMask]
        )
        addButton(
            symbol: "underline",
            fallbackTitle: "U",
            tooltip: "Underline",
            action: #selector(RichTextEditor.Coordinator.toggleUnderline),
            target: coordinator,
            to: stack,
            underlined: true
        )
        addSeparator(to: stack)
        addButton(
            symbol: "textformat.size.smaller",
            fallbackTitle: "A-",
            tooltip: "Decrease font size",
            action: #selector(RichTextEditor.Coordinator.decreaseFontSize),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "textformat.size.larger",
            fallbackTitle: "A+",
            tooltip: "Increase font size",
            action: #selector(RichTextEditor.Coordinator.increaseFontSize),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "textformat",
            fallbackTitle: "Font",
            tooltip: "Show fonts",
            action: #selector(RichTextEditor.Coordinator.showFontPanel),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "paintpalette",
            fallbackTitle: "Color",
            tooltip: "Show colors",
            action: #selector(RichTextEditor.Coordinator.showColorPanel),
            target: coordinator,
            to: stack
        )
        addSeparator(to: stack)
        addButton(
            symbol: "text.alignleft",
            fallbackTitle: "Left",
            tooltip: "Align left",
            action: #selector(RichTextEditor.Coordinator.alignLeft),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "text.aligncenter",
            fallbackTitle: "Center",
            tooltip: "Align center",
            action: #selector(RichTextEditor.Coordinator.alignCenter),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "text.alignright",
            fallbackTitle: "Right",
            tooltip: "Align right",
            action: #selector(RichTextEditor.Coordinator.alignRight),
            target: coordinator,
            to: stack
        )
        addButton(
            symbol: "text.justify",
            fallbackTitle: "Justify",
            tooltip: "Justify",
            action: #selector(RichTextEditor.Coordinator.alignJustified),
            target: coordinator,
            to: stack
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Builds a toolbar button showing `symbol`, falling back to a styled text title on the rare
    /// system where the symbol is unavailable. The tooltip doubles as the accessibility label,
    /// since the button's content is purely graphical.
    private func addButton(
        symbol: String,
        fallbackTitle: String,
        tooltip: String,
        action: Selector,
        target: AnyObject,
        to stack: NSStackView,
        fontTraits: NSFontTraitMask = [],
        underlined: Bool = false
    ) {
        let button = NSButton(title: fallbackTitle, target: target, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            image.isTemplate = true
            button.image = image.withSymbolConfiguration(.init(scale: .medium)) ?? image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else if !fontTraits.isEmpty || underlined {
            let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let convertedFont = NSFontManager.shared.convert(font, toHaveTrait: fontTraits)
            let title = NSMutableAttributedString(string: fallbackTitle, attributes: [.font: convertedFont])
            if underlined {
                title.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: 0, length: title.length)
                )
            }
            button.attributedTitle = title
        }

        stack.addArrangedSubview(button)
    }

    private func addSeparator(to stack: NSStackView) {
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)
    }
}

private struct PlatformImageView: View {
    let data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        } else {
            Text("The imported image could not be decoded.")
                .foregroundStyle(.secondary)
        }
    }
}
#elseif os(iOS) || os(visionOS)
private struct RichTextEditor: UIViewRepresentable {
    let attributedText: NSAttributedString
    let passage: EditorialPassage?
    let onChange: (NSAttributedString) -> Void
    let onCommit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onCommit: onCommit)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.accessibilityIdentifier = "document.body"
        textView.isEditable = true
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        textView.delegate = context.coordinator
        textView.attributedText = Self.displayText(attributedText, colorScheme: colorScheme)
        context.coordinator.textView = textView
        context.coordinator.colorScheme = colorScheme
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onCommit = onCommit
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        let storedEditorText = Self.storageText(from: textView.attributedText, colorScheme: context.coordinator.colorScheme)
        if textView.markedTextRange == nil,
           (!textView.isFirstResponder || !context.coordinator.hasUncommittedChanges),
           storedEditorText != attributedText {
            context.coordinator.isUpdating = true
            textView.attributedText = Self.displayText(attributedText, colorScheme: colorScheme)
            context.coordinator.hasUncommittedChanges = false
            context.coordinator.isUpdating = false
        } else if context.coordinator.colorScheme != colorScheme {
            let selection = textView.selectedRange
            context.coordinator.isUpdating = true
            textView.attributedText = Self.displayText(storedEditorText, colorScheme: colorScheme)
            textView.selectedRange = selection
            context.coordinator.isUpdating = false
        }
        context.coordinator.colorScheme = colorScheme

        if let passage, passage.token != context.coordinator.lastPassage,
           passage.location >= 0, passage.length >= 0,
           passage.location + passage.length <= textView.text.utf16.count {
            let range = NSRange(location: passage.location, length: passage.length)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            context.coordinator.lastPassage = passage.token
        }
    }

    private static let originalForegroundColor = NSAttributedString.Key(
        "com.robertrhea.scribe.originalForegroundColor"
    )
    private static let missingForegroundColor = "missing"

    private static func displayText(
        _ attributedText: NSAttributedString,
        colorScheme: ColorScheme
    ) -> NSAttributedString {
        let displayText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: displayText.length)
        displayText.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard let color = value as? UIColor else {
                displayText.addAttribute(
                    originalForegroundColor,
                    value: missingForegroundColor,
                    range: range
                )
                displayText.addAttribute(.foregroundColor, value: UIColor.label, range: range)
                return
            }
            guard shouldAdapt(color, for: colorScheme) else { return }
            displayText.addAttribute(originalForegroundColor, value: color, range: range)
            displayText.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        }
        return displayText
    }

    private static func storageText(
        from attributedText: NSAttributedString,
        colorScheme: ColorScheme
    ) -> NSAttributedString {
        let storageText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: storageText.length)
        storageText.enumerateAttribute(originalForegroundColor, in: fullRange) { value, range, _ in
            defer { storageText.removeAttribute(originalForegroundColor, range: range) }
            if value as? String == missingForegroundColor {
                storageText.removeAttribute(.foregroundColor, range: range)
                return
            }
            guard let originalColor = value as? UIColor,
                  let displayedColor = storageText.attribute(
                    .foregroundColor,
                    at: range.location,
                    effectiveRange: nil
                  ) as? UIColor,
                  colorsMatch(displayedColor, UIColor.label, colorScheme: colorScheme) else {
                return
            }
            storageText.addAttribute(.foregroundColor, value: originalColor, range: range)
        }
        return storageText
    }

    private static func shouldAdapt(_ color: UIColor, for colorScheme: ColorScheme) -> Bool {
        guard let luminance = luminance(of: color, colorScheme: colorScheme) else { return false }
        return colorScheme == .dark ? luminance < 0.15 : luminance > 0.85
    }

    private static func colorsMatch(
        _ lhs: UIColor,
        _ rhs: UIColor,
        colorScheme: ColorScheme
    ) -> Bool {
        guard let lhsLuminance = luminance(of: lhs, colorScheme: colorScheme),
              let rhsLuminance = luminance(of: rhs, colorScheme: colorScheme) else {
            return lhs == rhs
        }
        return abs(lhsLuminance - rhsLuminance) < 0.01
    }

    private static func luminance(of color: UIColor, colorScheme: ColorScheme) -> CGFloat? {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let resolvedColor = color.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style)
        )
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.textView = textView
        coordinator.commitPendingChange()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        var onCommit: () -> Void
        var isUpdating = false
        var hasUncommittedChanges = false
        var lastPassage: UUID?
        var colorScheme: ColorScheme = .light
        private var pendingChange: DispatchWorkItem?
        weak var textView: UITextView?

        init(onChange: @escaping (NSAttributedString) -> Void, onCommit: @escaping () -> Void) {
            self.onChange = onChange
            self.onCommit = onCommit
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationWillResignActive),
                name: UIApplication.willResignActiveNotification,
                object: nil,
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            self.textView = textView
            pendingChange?.cancel()
            hasUncommittedChanges = true
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, !isUpdating, let textView else { return }
                onChange(RichTextEditor.storageText(from: textView.attributedText, colorScheme: colorScheme))
                pendingChange = nil
                hasUncommittedChanges = false
            }
            pendingChange = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }

        func commitPendingChange() {
            pendingChange?.cancel()
            pendingChange = nil
            guard !isUpdating else { return }
            if hasUncommittedChanges, let textView {
                onChange(RichTextEditor.storageText(from: textView.attributedText, colorScheme: colorScheme))
                hasUncommittedChanges = false
            }
            onCommit()
        }

        @objc
        private func applicationWillResignActive() {
            commitPendingChange()
        }
    }
}

private struct PlatformImageView: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        } else {
            Text("The imported image could not be decoded.")
                .foregroundStyle(.secondary)
        }
    }
}
#endif

#if os(macOS)
private struct PlainDocumentEditor: NSViewRepresentable {
    let text: String
    let passage: EditorialPassage?
    let onChange: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isRichText = false; view.font = .systemFont(ofSize: 16)
        view.textContainerInset = NSSize(width: 24, height: 24)
        view.string = text; view.delegate = context.coordinator
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let view = scroll.documentView as! NSTextView
        context.coordinator.onChange = onChange
        if !view.hasMarkedText(), view.string != text { view.string = text }
        if let passage, passage.token != context.coordinator.lastPassage,
           passage.location >= 0, passage.length >= 0, passage.location + passage.length <= view.string.utf16.count {
            let range = NSRange(location: passage.location, length: passage.length)
            view.setSelectedRange(range); view.scrollRangeToVisible(range); context.coordinator.lastPassage = passage.token
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var lastPassage: UUID?
        init(_ onChange: @escaping (String) -> Void) { self.onChange = onChange }
        func textDidChange(_ notification: Notification) { if let view = notification.object as? NSTextView { onChange(view.string) } }
    }
}
#elseif os(iOS) || os(visionOS)
private struct PlainDocumentEditor: UIViewRepresentable {
    let text: String
    let passage: EditorialPassage?
    let onChange: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChange) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.font = .preferredFont(forTextStyle: .body); view.text = text; view.delegate = context.coordinator; return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        if view.markedTextRange == nil, view.text != text { view.text = text }
        if let passage, passage.token != context.coordinator.lastPassage,
           passage.location >= 0, passage.length >= 0, passage.location + passage.length <= view.text.utf16.count {
            let range = NSRange(location: passage.location, length: passage.length)
            view.selectedRange = range; view.scrollRangeToVisible(range); context.coordinator.lastPassage = passage.token
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (String) -> Void
        var lastPassage: UUID?
        init(_ onChange: @escaping (String) -> Void) { self.onChange = onChange }
        func textViewDidChange(_ view: UITextView) { onChange(view.text) }
    }
}
#else
private struct PlainDocumentEditor: View {
    let text: String
    let passage: EditorialPassage?
    let onChange: (String) -> Void
    var body: some View { TextEditor(text: Binding(get: { text }, set: onChange)) }
}
#endif
