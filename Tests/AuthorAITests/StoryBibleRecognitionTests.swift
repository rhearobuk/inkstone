import XCTest
@testable import AuthorAI
#if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
import FoundationModels
#endif

final class StoryBibleRecognitionTests: XCTestCase {
    func testMissingDiagnosticDoesNotInventAReason() {
        let error = StoryBibleRecognitionError(reason: .refusal, passLabel: "Characters", diagnostic: " \n")
        XCTAssertEqual(
            error.localizedDescription,
            "Apple Intelligence refused the Characters recognition request. Apple did not provide further detail."
        )
    }

    #if canImport(FoundationModels) && !os(tvOS) && !os(watchOS)
    func testAppleGuardrailAndRefusalRemainDistinct() throws {
        guard #available(macOS 26, iOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires Foundation Models")
        }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "Synthetic diagnostic.")
        let guardrail = try XCTUnwrap(
            AppleIntelligenceStoryBibleRecognitionClient.recognitionError(
                .guardrailViolation(context), passLabel: "Characters"
            ) as? StoryBibleRecognitionError
        )
        guard case .guardrailViolation = guardrail.reason else { return XCTFail("Expected guardrail") }
        XCTAssertEqual(guardrail.passLabel, "Characters")
        XCTAssertEqual(guardrail.diagnostic, "Synthetic diagnostic.")

        let refusal = try XCTUnwrap(
            AppleIntelligenceStoryBibleRecognitionClient.recognitionError(
                .refusal(.init(transcriptEntries: []), context), passLabel: "Artifacts and objects"
            ) as? StoryBibleRecognitionError
        )
        guard case .refusal = refusal.reason else { return XCTFail("Expected refusal") }
        XCTAssertEqual(refusal.passLabel, "Artifacts and objects")
        XCTAssertEqual(refusal.diagnostic, "Synthetic diagnostic.")
    }

    func testAppleContextOverflowIsNotARefusal() throws {
        guard #available(macOS 26, iOS 26, visionOS 26, *) else {
            throw XCTSkip("Requires Foundation Models")
        }
        let error = AppleIntelligenceStoryBibleRecognitionClient.recognitionError(
            .exceededContextWindowSize(.init(debugDescription: "Too long")), passLabel: "Characters"
        )
        guard case ReviewClientError.contextExceeded = error else { return XCTFail("Expected context overflow") }
    }
    #endif
}
