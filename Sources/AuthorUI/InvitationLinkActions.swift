import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Ways to deliver a CloudKit invitation link. Copy Link writes straight to the pasteboard so
/// the author always has a path that doesn't depend on Mail or the system share picker.
struct InvitationLinkActions: View {
    let invitationURL: URL
    let emailURL: URL?
    let emailTitle: String
    let shareSubject: String
    let shareTitle: String

    @State private var copied = false

    var body: some View {
        HStack {
            Button {
                Self.copyToPasteboard(invitationURL)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("invitation.copyLink")

            if let emailURL {
                Link(destination: emailURL) {
                    Label(emailTitle, systemImage: "envelope")
                }
                .buttonStyle(.bordered)
            }

            ShareLink(
                item: invitationURL,
                subject: Text(shareSubject),
                message: Text("Open this invitation in Inkstone while signed in to iCloud.")
            ) {
                Label(shareTitle, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: invitationURL) { _, _ in copied = false }
    }

    static func copyToPasteboard(_ url: URL) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.url = url
        #endif
    }
}
