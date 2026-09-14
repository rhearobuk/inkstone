import SwiftUI
import AuthorData

/// Shared appearance and plain-language labels for the editorial conversation.
enum EditorStyle {
    static let buttonColor = Color(red: 0.39, green: 0.38, blue: 0.70)
    static var accent: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.70, green: 0.68, blue: 0.96, alpha: 1)
                : NSColor(red: 0.39, green: 0.38, blue: 0.70, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.70, green: 0.68, blue: 0.96, alpha: 1)
                : UIColor(red: 0.39, green: 0.38, blue: 0.70, alpha: 1)
        })
        #endif
    }
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    static var paper: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    static func personaName(_ name: String) -> String {
        switch name {
        case "Technical / Copy": "Copy editor"
        case "Story / Developmental": "Story editor"
        case "Character & Continuity": "Continuity editor"
        case "Line & Style": "Style editor"
        case "Academic": "Academic editor"
        case "Genre & Reader Experience": "Reader’s perspective"
        default: name
        }
    }
    static func scopeName(_ scope: EditorialScope) -> String {
        switch scope {
        case .document: "Scene"
        case .chapter: "Chapter"
        case .novel: "Whole novel"
        }
    }
}
struct EditorAvatar: View {
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: "pencil.tip.crop.circle")
            .font(.system(size: size * 0.53, weight: .medium))
            .foregroundStyle(EditorStyle.accent)
            .frame(width: size, height: size)
            .background(EditorStyle.accent.opacity(0.11), in: Circle())
            .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder func editorMenuStyle() -> some View {
        #if os(macOS)
        self.menuStyle(.borderlessButton)
        #else
        self
        #endif
    }
}
