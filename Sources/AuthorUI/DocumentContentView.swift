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
            RichTextEditor(attributedText: attributedText) { updatedText in
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
            TextEditor(
                text: Binding(
                    get: { document.plainText ?? "" },
                    set: {
                        controller.updateDocument(
                            title: document.title,
                            synopsis: document.synopsis,
                            plainText: $0
                        )
                    }
                )
            )
            .font(.body)
            .padding()
        }
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
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributedText)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        guard let textView = scrollView.documentView as? NSTextView,
              !textView.hasMarkedText(),
              textView.attributedString() != attributedText else {
            return
        }
        context.coordinator.isUpdating = true
        textView.textStorage?.setAttributedString(attributedText)
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        var isUpdating = false

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
    let onChange: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = true
        textView.allowsEditingTextAttributes = true
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        textView.delegate = context.coordinator
        textView.attributedText = attributedText
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onChange = onChange
        guard textView.markedTextRange == nil, textView.attributedText != attributedText else {
            return
        }
        context.coordinator.isUpdating = true
        textView.attributedText = attributedText
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onChange: (NSAttributedString) -> Void
        var isUpdating = false

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
