import Foundation

public enum ReviewResponseValidator {
    public static func validate(_ response: ReviewResponse, allowedDocumentIDs: Set<String>) throws -> ReviewResponse {
        var response = response
        for index in response.findings.indices {
            response.findings[index].category = response.findings[index].category.lowercased()
            response.findings[index].severity = response.findings[index].severity.lowercased()
            for anchor in response.findings[index].evidence.indices {
                var identifier = response.findings[index].evidence[anchor].documentID.trimmingCharacters(in: .whitespacesAndNewlines)
                if identifier.hasPrefix("DOCUMENT ") { identifier = String(identifier.dropFirst(9)) }
                if let uuid = UUID(uuidString: identifier) { identifier = uuid.uuidString }
                response.findings[index].evidence[anchor].documentID = identifier
            }
        }
        guard !response.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.summary.utf8.count <= 16000, response.findings.count <= 20 else { throw ReviewClientError.invalidResponse }
        let categories = Set(["technical", "story", "continuity", "style", "academic", "reader"])
        let severities = Set(["minor", "moderate", "major"])
        for finding in response.findings {
            guard categories.contains(finding.category), severities.contains(finding.severity),
                  !finding.title.isEmpty, !finding.explanation.isEmpty, !finding.recommendation.isEmpty,
                  finding.title.count <= 300, finding.explanation.count <= 4000, finding.recommendation.count <= 4000,
                  finding.evidence.count <= 4,
                  finding.evidence.allSatisfy({ allowedDocumentIDs.contains($0.documentID) && $0.excerpt.utf16.count <= 600 }) else {
                throw ReviewClientError.invalidResponse
            }
        }
        return response
    }
    public static func uniqueRange(excerpt: String, in text: String) -> NSRange? {
        guard !excerpt.isEmpty else { return nil }
        let source = text as NSString
        let range = source.range(of: excerpt)
        guard range.location != NSNotFound else { return nil }
        let remaining = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
        guard source.range(of: excerpt, range: remaining).location == NSNotFound else { return nil }
        return range
    }
}
