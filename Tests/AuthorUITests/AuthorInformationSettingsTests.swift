import XCTest
@testable import AuthorUI

@MainActor
final class AuthorInformationSettingsTests: XCTestCase {
    func testPersistsAuthorInformation() throws {
        let suiteName = "AuthorInformationSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AuthorInformationSettings(defaults: defaults)
        settings.name = "Ada Lovelace"
        settings.penName = "A. L. Ada"
        settings.addressLine1 = "12 Analytical Engine Way"
        settings.addressLine2 = "Flat 4"
        settings.locality = "London"
        settings.region = "Greater London"
        settings.postalCode = "SW1A 1AA"
        settings.country = "United Kingdom"
        settings.email = "ada@example.com"
        settings.phone = "+44 20 7946 0958"
        settings.website = "https://example.com"
        settings.agentName = "Grace Hopper"
        settings.agency = "Hopper Literary"
        settings.agentAddressLine1 = "1 Compiler Court"
        settings.agentAddressLine2 = "Suite 200"
        settings.agentLocality = "Arlington"
        settings.agentRegion = "Virginia"
        settings.agentPostalCode = "22201"
        settings.agentCountry = "United States"
        settings.agentEmail = "grace@hopperliterary.example"
        settings.agentPhone = "+1 555 0100"
        settings.agentWebsite = "https://hopperliterary.example"

        let restored = AuthorInformationSettings(defaults: defaults)
        XCTAssertEqual(restored.name, "Ada Lovelace")
        XCTAssertEqual(restored.penName, "A. L. Ada")
        XCTAssertEqual(restored.addressLine1, "12 Analytical Engine Way")
        XCTAssertEqual(restored.addressLine2, "Flat 4")
        XCTAssertEqual(restored.locality, "London")
        XCTAssertEqual(restored.region, "Greater London")
        XCTAssertEqual(restored.postalCode, "SW1A 1AA")
        XCTAssertEqual(restored.country, "United Kingdom")
        XCTAssertEqual(restored.email, "ada@example.com")
        XCTAssertEqual(restored.phone, "+44 20 7946 0958")
        XCTAssertEqual(restored.website, "https://example.com")
        XCTAssertEqual(restored.agentName, "Grace Hopper")
        XCTAssertEqual(restored.agency, "Hopper Literary")
        XCTAssertEqual(restored.agentAddressLine1, "1 Compiler Court")
        XCTAssertEqual(restored.agentAddressLine2, "Suite 200")
        XCTAssertEqual(restored.agentLocality, "Arlington")
        XCTAssertEqual(restored.agentRegion, "Virginia")
        XCTAssertEqual(restored.agentPostalCode, "22201")
        XCTAssertEqual(restored.agentCountry, "United States")
        XCTAssertEqual(restored.agentEmail, "grace@hopperliterary.example")
        XCTAssertEqual(restored.agentPhone, "+1 555 0100")
        XCTAssertEqual(restored.agentWebsite, "https://hopperliterary.example")
    }
}
