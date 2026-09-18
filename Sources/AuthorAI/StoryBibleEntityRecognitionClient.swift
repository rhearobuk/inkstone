import Foundation
#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels

@available(macOS 26, iOS 26, visionOS 26, *)
@Generable
private struct AppleStoryBibleRecognitionMatch {
    var entityID: String
    var surfaceText: String
    var occurrence: Int
}

@available(macOS 26, iOS 26, visionOS 26, *)
@Generable
private struct AppleStoryBibleRecognitionResponse {
    @Guide(.count(0...48)) var matches: [AppleStoryBibleRecognitionMatch]
}
#endif

public struct StoryBibleRecognitionCandidate: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let kind: String

    public init(id: String, name: String, aliases: [String], kind: String) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.kind = kind
    }
}

public struct StoryBibleRecognitionRequest: Sendable, Equatable {
    public let sceneText: String
    public let passLabel: String
    public let candidates: [StoryBibleRecognitionCandidate]

    public init(sceneText: String, passLabel: String, candidates: [StoryBibleRecognitionCandidate]) {
        self.sceneText = sceneText
        self.passLabel = passLabel
        self.candidates = candidates
    }
}

public struct StoryBibleRecognitionMatch: Sendable, Equatable {
    public let entityID: String
    public let surfaceText: String
    public let occurrence: Int

    public init(entityID: String, surfaceText: String, occurrence: Int) {
        self.entityID = entityID
        self.surfaceText = surfaceText
        self.occurrence = occurrence
    }
}

public protocol StoryBibleEntityRecognitionClient: Sendable {
    func recognizeMentions(in request: StoryBibleRecognitionRequest) async throws -> [StoryBibleRecognitionMatch]
}

public struct StoryBibleRecognitionError: LocalizedError, Sendable {
    public enum Reason: Sendable {
        case guardrailViolation, refusal
    }

    public let reason: Reason
    public let passLabel: String
    public let diagnostic: String

    public init(reason: Reason, passLabel: String, diagnostic: String) {
        self.reason = reason
        self.passLabel = passLabel
        self.diagnostic = diagnostic
    }

    public var errorDescription: String? {
        let summary: String
        switch reason {
        case .guardrailViolation:
            summary = "Apple Intelligence blocked the \(passLabel) pass with a safety guardrail."
        case .refusal:
            summary = "Apple Intelligence refused the \(passLabel) recognition request."
        }
        let detail = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary + " " + (detail.isEmpty
            ? "Apple did not provide further detail."
            : "Apple diagnostic: \(detail)")
    }
}

private enum StoryBibleRecognitionPromptBuilder {
    static let instructions = """
    You identify mentions of existing Story Bible entities in a scene.
    Use only the supplied candidate entities. Never invent new entities, never merge two candidates, and never guess.
    Return only entities that are explicitly mentioned in the scene text for the current pass.
    For every match:
    - entityID must exactly match one supplied candidate id.
    - surfaceText must be an exact contiguous quote from the scene text as written there.
    - occurrence must be the 1-based occurrence number of that exact surfaceText in the scene text.
    - If the scene does not mention a candidate, omit it.
    - If unsure, omit it.
    - If an entity appears multiple times, return multiple matches.
    """

    static func prompt(_ request: StoryBibleRecognitionRequest) -> String {
        let candidates = request.candidates.map { candidate in
            let aliases = candidate.aliases.isEmpty ? "none" : candidate.aliases.joined(separator: " | ")
            return "- id: \(candidate.id)\n  kind: \(candidate.kind)\n  name: \(candidate.name)\n  aliases: \(aliases)"
        }.joined(separator: "\n")
        return """
        CURRENT PASS
        \(request.passLabel)
        END CURRENT PASS

        CANDIDATES
        \(candidates)
        END CANDIDATES

        SCENE TEXT
        \(request.sceneText)
        END SCENE TEXT
        """
    }
}

public struct AppleIntelligenceStoryBibleRecognitionClient: StoryBibleEntityRecognitionClient {
    public init() {}

    public static var unavailableReason: String? {
        AppleIntelligenceReviewClient.unavailableReason
    }

    public func recognizeMentions(in request: StoryBibleRecognitionRequest) async throws -> [StoryBibleRecognitionMatch] {
        try Task.checkCancellation()
        if let reason = Self.unavailableReason {
            throw ReviewClientError.unavailable(reason)
        }
        #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: StoryBibleRecognitionPromptBuilder.instructions)
                let response = try await session.respond(
                    to: StoryBibleRecognitionPromptBuilder.prompt(request),
                    generating: AppleStoryBibleRecognitionResponse.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1200)
                )
                try Task.checkCancellation()
                return response.content.matches.map {
                    StoryBibleRecognitionMatch(entityID: $0.entityID, surfaceText: $0.surfaceText, occurrence: $0.occurrence)
                }
            } catch let error as LanguageModelSession.GenerationError {
                throw Self.recognitionError(error, passLabel: request.passLabel)
            }
        }
        #endif
        throw ReviewClientError.unavailable(Self.unavailableReason ?? "Apple Intelligence is unavailable.")
    }

    #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
    @available(macOS 26, iOS 26, visionOS 26, *)
    static func recognitionError(_ error: LanguageModelSession.GenerationError, passLabel: String) -> any Error {
        switch error {
        case .guardrailViolation(let context):
            StoryBibleRecognitionError(reason: .guardrailViolation, passLabel: passLabel, diagnostic: context.debugDescription)
        case .refusal(_, let context):
            StoryBibleRecognitionError(reason: .refusal, passLabel: passLabel, diagnostic: context.debugDescription)
        case .exceededContextWindowSize:
            ReviewClientError.contextExceeded
        default:
            ReviewClientError.unavailable(error.localizedDescription)
        }
    }
    #endif
}

public struct DefaultStoryBibleEntityRecognitionClient: StoryBibleEntityRecognitionClient {
    private let appleClient: AppleIntelligenceStoryBibleRecognitionClient

    public init(appleClient: AppleIntelligenceStoryBibleRecognitionClient = AppleIntelligenceStoryBibleRecognitionClient()) {
        self.appleClient = appleClient
    }

    public func recognizeMentions(in request: StoryBibleRecognitionRequest) async throws -> [StoryBibleRecognitionMatch] {
        do {
            return try await appleClient.recognizeMentions(in: request)
        } catch let error as ReviewClientError {
            if case .unavailable = error {
                return []
            }
            throw error
        }
    }
}
