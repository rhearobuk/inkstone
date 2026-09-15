import Foundation
import XCTest
@testable import AuthorAI

private final class ExternalReviewURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try! JSONSerialization.jsonObject(with: requestBody()) as! [String: Any]
        let text = #"{"summary":"Supported editorial note.","findings":[]}"#
        let response: [String: Any]
        switch request.url?.host {
        case "api.anthropic.com":
            XCTAssertEqual(request.url?.path, "/v1/messages")
            response = ["content": [["type": "text", "text": text]]]
        case "generativelanguage.googleapis.com":
            XCTAssertTrue(request.url?.path.contains(":generateContent") == true)
            response = ["candidates": [["content": ["parts": [["text": text]]]]]]
        case "api.mistral.ai":
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            response = ["choices": [["message": ["content": text]]]]
        case "api.x.ai":
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(body["max_output_tokens"] as? Int, 1200)
            response = ["output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        case "api.cohere.com":
            XCTAssertEqual(request.url?.path, "/v2/chat")
            response = ["message": ["content": [["type": "text", "text": text]]]]
        case "127.0.0.1":
            XCTAssertEqual(request.url?.port, 11434)
            XCTAssertEqual(request.url?.path, "/api/chat")
            response = ["message": ["content": text]]
        default:
            XCTFail("Unexpected provider endpoint: \(request.url?.absoluteString ?? "nil")")
            return
        }
        let data = try! JSONSerialization.data(withJSONObject: response)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

final class ExternalReviewClientTests: XCTestCase {
    func testConfiguredProvidersSubmitAndDecodeEditorialReview() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExternalReviewURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for provider in [
            ExternalReviewProvider.anthropic,
            .google,
            .mistral,
            .xai,
            .cohere,
            .ollama
        ] {
            let client = ExternalReviewClient(provider: provider, apiKey: "test-key", modelID: "test-model", session: session)
            let result = try await client.review(.init(rubric: "Test", material: "Synthetic manuscript."))
            XCTAssertEqual(result.summary, "Supported editorial note.")
            XCTAssertTrue(result.findings.isEmpty)
        }
    }
}
