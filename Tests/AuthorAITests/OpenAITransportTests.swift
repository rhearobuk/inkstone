import Foundation
import XCTest
@testable import AuthorAI

private final class ReviewURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.httpMethod, "POST")
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; result.append(contentsOf: buffer.prefix(count))
            }
            data = result
        }
        let body = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertNil(body["tools"])
        XCTAssertTrue((body["instructions"] as? String)?.contains("Never write replacement prose") == true)
        let text = #"{"summary":"No supported issues.","findings":[]}"#
        let output = try! JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["content": [["type": "output_text", "text": text]]]]])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: output)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class OpenAITransportTests: XCTestCase {
    func testExplicitProviderRequestUsesStructuredResponseWithoutServerStorage() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReviewURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = OpenAIReviewClient(apiKey: "test-key", modelID: "test-model", session: session)
        let result = try await client.review(.init(rubric: "Copy edit", material: "Synthetic passage."))
        XCTAssertEqual(result.summary, "No supported issues.")
    }
}
