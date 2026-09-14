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
            RichTextEditor(attributedText: attributedText, passage: passage) { updatedText in
                do {
                    let range = NSRange(location: 0, length: updatedText.length)
                    let data = try updatedText.data(
                        from: range,
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    controller.updateDocumentRichText(
                        rtfData: data,
                        plainText: updatedText.string
                    )
                } catch {
                    controller.report(error)
                }
            }
        } else {
            PlainDocumentEditor(text: document.plainText ?? "", passage: passage) { text in
                controller.updateDocument(title: document.title, synopsis: document.synopsis, plainText: text)
            }

        }
    }

    private var passage: EditorialPassage? {
        controller.editorialPassage?.documentID == document.id ? controller.editorialPassage : nil
    }

    private var rtfResource: ContentResource? {
        document.resources.first {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = true
        textView.isRichText = true
        textView.allowsImageEditing = true
        textView.importsGraphics = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.hasMarkedText(), textView.attributedString() != attributedText {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
            textView.usesAdaptiveColorMappingForDarkAppearance = true
            context.coordinator.isUpdating = true
            textView.textStorage?.setAttributedString(attributedText)
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        var isUpdating = false
        var lastPassage: UUID?

        init(onChange: @escaping (NSAttributedString) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            onChange(textView.attributedString())
        }
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        textView.delegate = context.coordinator
        textView.attributedText = attributedText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        if textView.markedTextRange == nil, textView.attributedText != attributedText {
            context.coordinator.isUpdating = true
            textView.attributedText = attributedText
            context.coordinator.isUpdating = false
        }
        if let passage, passage.token != context.coordinator.lastPassage,
           passage.location >= 0, passage.length >= 0,
           passage.location + passage.length <= textView.text.utf16.count {
            let range = NSRange(location: passage.location, length: passage.length)
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            context.coordinator.lastPassage = passage.token
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        var isUpdating = false
        var lastPassage: UUID?

        init(onChange: @escaping (NSAttributedString) -> Void) {
            self.onChange = onChange
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            onChange(textView.attributedText)
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
