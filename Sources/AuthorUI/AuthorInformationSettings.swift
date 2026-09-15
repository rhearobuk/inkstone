import AuthorData
import Foundation
import SwiftUI

/// Application-wide author details used as the default profile for author-facing workflows.
@MainActor
public final class AuthorInformationSettings: ObservableObject {
    @Published public var name: String {
        didSet { defaults.set(name, forKey: Keys.name) }
    }
    @Published public var penName: String {
        didSet { defaults.set(penName, forKey: Keys.penName) }
    }
    @Published public var addressLine1: String {
        didSet { defaults.set(addressLine1, forKey: Keys.addressLine1) }
    }
    @Published public var addressLine2: String {
        didSet { defaults.set(addressLine2, forKey: Keys.addressLine2) }
    }
    @Published public var locality: String {
        didSet { defaults.set(locality, forKey: Keys.locality) }
    }
    @Published public var region: String {
        didSet { defaults.set(region, forKey: Keys.region) }
    }
    @Published public var postalCode: String {
        didSet { defaults.set(postalCode, forKey: Keys.postalCode) }
    }
    @Published public var country: String {
        didSet { defaults.set(country, forKey: Keys.country) }
    }
    @Published public var email: String {
        didSet { defaults.set(email, forKey: Keys.email) }
    }
    @Published public var phone: String {
        didSet { defaults.set(phone, forKey: Keys.phone) }
    }
    @Published public var website: String {
        didSet { defaults.set(website, forKey: Keys.website) }
    }
    @Published public var agentName: String {
        didSet { defaults.set(agentName, forKey: Keys.agentName) }
    }
    @Published public var agency: String {
        didSet { defaults.set(agency, forKey: Keys.agency) }
    }
    @Published public var agentAddressLine1: String {
        didSet { defaults.set(agentAddressLine1, forKey: Keys.agentAddressLine1) }
    }
    @Published public var agentAddressLine2: String {
        didSet { defaults.set(agentAddressLine2, forKey: Keys.agentAddressLine2) }
    }
    @Published public var agentLocality: String {
        didSet { defaults.set(agentLocality, forKey: Keys.agentLocality) }
    }
    @Published public var agentRegion: String {
        didSet { defaults.set(agentRegion, forKey: Keys.agentRegion) }
    }
    @Published public var agentPostalCode: String {
        didSet { defaults.set(agentPostalCode, forKey: Keys.agentPostalCode) }
    }
    @Published public var agentCountry: String {
        didSet { defaults.set(agentCountry, forKey: Keys.agentCountry) }
    }
    @Published public var agentEmail: String {
        didSet { defaults.set(agentEmail, forKey: Keys.agentEmail) }
    }
    @Published public var agentPhone: String {
        didSet { defaults.set(agentPhone, forKey: Keys.agentPhone) }
    }
    @Published public var agentWebsite: String {
        didSet { defaults.set(agentWebsite, forKey: Keys.agentWebsite) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let name = "AuthorInformation.name"
        static let penName = "AuthorInformation.penName"
        static let addressLine1 = "AuthorInformation.addressLine1"
        static let addressLine2 = "AuthorInformation.addressLine2"
        static let locality = "AuthorInformation.locality"
        static let region = "AuthorInformation.region"
        static let postalCode = "AuthorInformation.postalCode"
        static let country = "AuthorInformation.country"
        static let email = "AuthorInformation.email"
        static let phone = "AuthorInformation.phone"
        static let website = "AuthorInformation.website"
        static let agentName = "AuthorInformation.agentName"
        static let agency = "AuthorInformation.agency"
        static let agentAddressLine1 = "AuthorInformation.agentAddressLine1"
        static let agentAddressLine2 = "AuthorInformation.agentAddressLine2"
        static let agentLocality = "AuthorInformation.agentLocality"
        static let agentRegion = "AuthorInformation.agentRegion"
        static let agentPostalCode = "AuthorInformation.agentPostalCode"
        static let agentCountry = "AuthorInformation.agentCountry"
        static let agentEmail = "AuthorInformation.agentEmail"
        static let agentPhone = "AuthorInformation.agentPhone"
        static let agentWebsite = "AuthorInformation.agentWebsite"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.name = defaults.string(forKey: Keys.name) ?? ""
        self.penName = defaults.string(forKey: Keys.penName) ?? ""
        self.addressLine1 = defaults.string(forKey: Keys.addressLine1) ?? ""
        self.addressLine2 = defaults.string(forKey: Keys.addressLine2) ?? ""
        self.locality = defaults.string(forKey: Keys.locality) ?? ""
        self.region = defaults.string(forKey: Keys.region) ?? ""
        self.postalCode = defaults.string(forKey: Keys.postalCode) ?? ""
        self.country = defaults.string(forKey: Keys.country) ?? ""
        self.email = defaults.string(forKey: Keys.email) ?? ""
        self.phone = defaults.string(forKey: Keys.phone) ?? ""
        self.website = defaults.string(forKey: Keys.website) ?? ""
        self.agentName = defaults.string(forKey: Keys.agentName) ?? ""
        self.agency = defaults.string(forKey: Keys.agency) ?? ""
        self.agentAddressLine1 = defaults.string(forKey: Keys.agentAddressLine1) ?? ""
        self.agentAddressLine2 = defaults.string(forKey: Keys.agentAddressLine2) ?? ""
        self.agentLocality = defaults.string(forKey: Keys.agentLocality) ?? ""
        self.agentRegion = defaults.string(forKey: Keys.agentRegion) ?? ""
        self.agentPostalCode = defaults.string(forKey: Keys.agentPostalCode) ?? ""
        self.agentCountry = defaults.string(forKey: Keys.agentCountry) ?? ""
        self.agentEmail = defaults.string(forKey: Keys.agentEmail) ?? ""
        self.agentPhone = defaults.string(forKey: Keys.agentPhone) ?? ""
        self.agentWebsite = defaults.string(forKey: Keys.agentWebsite) ?? ""
    }
}

extension AuthorInformationSettings {
    var exportContactInformation: ExportContactInformation {
        ExportContactInformation(
            author: preferredByline,
            authorAddress: formattedAddress(
                line1: addressLine1,
                line2: addressLine2,
                locality: locality,
                region: region,
                postalCode: postalCode,
                country: country
            ),
            authorPhone: nonEmpty(phone),
            authorEmail: nonEmpty(email),
            agentName: nonEmpty(agentName),
            agency: nonEmpty(agency),
            agentAddress: formattedAddress(
                line1: agentAddressLine1,
                line2: agentAddressLine2,
                locality: agentLocality,
                region: agentRegion,
                postalCode: agentPostalCode,
                country: agentCountry
            ),
            agentPhone: nonEmpty(agentPhone),
            agentEmail: nonEmpty(agentEmail)
        )
    }

    private var preferredByline: String? {
        nonEmpty(penName) ?? nonEmpty(name)
    }

    private func formattedAddress(
        line1: String,
        line2: String,
        locality: String,
        region: String,
        postalCode: String,
        country: String
    ) -> String? {
        let localityLine = [nonEmpty(locality), nonEmpty(region), nonEmpty(postalCode)]
            .compactMap { $0 }
            .joined(separator: ", ")
        return [nonEmpty(line1), nonEmpty(line2), nonEmpty(localityLine), nonEmpty(country)]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty
    }

    private func nonEmpty(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
