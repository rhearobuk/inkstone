import Foundation
#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, *)
@Generable
private struct AppleEvidence {
    var documentID: String
    var excerpt: String
}
@available(macOS 26, iOS 26, visionOS 26, *)
@Generable
private struct AppleFinding {
    @Guide(.anyOf(["technical", "story", "continuity", "style", "academic", "reader"])) var category: String
    @Guide(.anyOf(["minor", "moderate", "major"])) var severity: String
    var title: String
    var explanation: String
    var recommendation: String
    @Guide(.count(0...2)) var evidence: [AppleEvidence]
}
@available(macOS 26, iOS 26, visionOS 26, *)
@Generable
private struct AppleReview {
    var summary: String
    @Guide(.count(0...4)) var findings: [AppleFinding]
}
#endif

public struct AppleIntelligenceReviewClient: EditorialReviewClient {
    public init() {}
    public static var unavailableReason: String? {
        #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This device does not support Apple Intelligence."
            case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings."
            case .unavailable(.modelNotReady): return "Apple's on-device model is still downloading or preparing. Try again when it is ready."
            case .unavailable: return "Apple Intelligence is currently unavailable."
            }
        }
        #endif
        return "On-device review requires a supported device with macOS 26, iOS 26, or visionOS 26 or later."
    }
    public func review(_ request: ReviewRequest) async throws -> ReviewResponse {
        try Task.checkCancellation()
        if let reason = Self.unavailableReason { throw ReviewClientError.unavailable(reason) }
        #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: EditorPromptBuilder.contract)
                let response = try await session.respond(to: EditorPromptBuilder.prompt(request), generating: AppleReview.self, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1400))
                try Task.checkCancellation()
                return ReviewResponse(summary: response.content.summary, findings: response.content.findings.map {
                    ReviewFinding(category: $0.category, severity: $0.severity, title: $0.title,
                                  explanation: $0.explanation, recommendation: $0.recommendation,
                                  evidence: $0.evidence.map { ReviewEvidence(documentID: $0.documentID, excerpt: $0.excerpt) })
                })
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation, .refusal: throw ReviewClientError.refused
                case .exceededContextWindowSize: throw ReviewClientError.contextExceeded
                default: throw ReviewClientError.unavailable(error.localizedDescription)
                }
            }
        }
        #endif
        throw ReviewClientError.unavailable(Self.unavailableReason ?? "Apple Intelligence is unavailable.")
    }
}
