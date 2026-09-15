import AuthorData
import Foundation
import SwiftUI

/// Application-wide author details used as the default profile for author-facing workflows.
@MainActor
public final class AuthorInformationSettings: ObservableObject {
    @Published public var name: String {
        didSet { save(name, forKey: Keys.name) }
    }
    @Published public var penName: String {
        didSet { save(penName, forKey: Keys.penName) }
    }
    @Published public var addressLine1: String {
        didSet { save(addressLine1, forKey: Keys.addressLine1) }
    }
    @Published public var addressLine2: String {
        didSet { save(addressLine2, forKey: Keys.addressLine2) }
    }
    @Published public var locality: String {
        didSet { save(locality, forKey: Keys.locality) }
    }
    @Published public var region: String {
        didSet { save(region, forKey: Keys.region) }
    }
    @Published public var postalCode: String {
        didSet { save(postalCode, forKey: Keys.postalCode) }
    }
    @Published public var country: String {
        didSet { save(country, forKey: Keys.country) }
    }
    @Published public var email: String {
        didSet { save(email, forKey: Keys.email) }
    }
    @Published public var phone: String {
        didSet { save(phone, forKey: Keys.phone) }
    }
    @Published public var website: String {
        didSet { save(website, forKey: Keys.website) }
    }
    @Published public var agentName: String {
        didSet { save(agentName, forKey: Keys.agentName) }
    }
    @Published public var agency: String {
        didSet { save(agency, forKey: Keys.agency) }
    }
    @Published public var agentAddressLine1: String {
        didSet { save(agentAddressLine1, forKey: Keys.agentAddressLine1) }
    }
    @Published public var agentAddressLine2: String {
        didSet { save(agentAddressLine2, forKey: Keys.agentAddressLine2) }
    }
    @Published public var agentLocality: String {
        didSet { save(agentLocality, forKey: Keys.agentLocality) }
    }
    @Published public var agentRegion: String {
        didSet { save(agentRegion, forKey: Keys.agentRegion) }
    }
    @Published public var agentPostalCode: String {
        didSet { save(agentPostalCode, forKey: Keys.agentPostalCode) }
    }
    @Published public var agentCountry: String {
        didSet { save(agentCountry, forKey: Keys.agentCountry) }
    }
    @Published public var agentEmail: String {
        didSet { save(agentEmail, forKey: Keys.agentEmail) }
    }
    @Published public var agentPhone: String {
        didSet { save(agentPhone, forKey: Keys.agentPhone) }
    }
    @Published public var agentWebsite: String {
        didSet { save(agentWebsite, forKey: Keys.agentWebsite) }
    }

    private let defaults: UserDefaults
    private let ubiquitousStore: NSUbiquitousKeyValueStore?
    private var isApplyingRemoteValues = false
    private var ubiquitousStoreObserver: UbiquitousStoreObserver?

    private final class UbiquitousStoreObserver: @unchecked Sendable {
        let token: NSObjectProtocol

        init(_ token: NSObjectProtocol) {
            self.token = token
        }
    }

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

    public init(defaults: UserDefaults = .standard,
                ubiquitousStore: NSUbiquitousKeyValueStore? = .default) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
        ubiquitousStore?.synchronize()
        self.name = ubiquitousStore?.string(forKey: Keys.name) ?? defaults.string(forKey: Keys.name) ?? ""
        self.penName = ubiquitousStore?.string(forKey: Keys.penName) ?? defaults.string(forKey: Keys.penName) ?? ""
        self.addressLine1 = ubiquitousStore?.string(forKey: Keys.addressLine1) ?? defaults.string(forKey: Keys.addressLine1) ?? ""
        self.addressLine2 = ubiquitousStore?.string(forKey: Keys.addressLine2) ?? defaults.string(forKey: Keys.addressLine2) ?? ""
        self.locality = ubiquitousStore?.string(forKey: Keys.locality) ?? defaults.string(forKey: Keys.locality) ?? ""
        self.region = ubiquitousStore?.string(forKey: Keys.region) ?? defaults.string(forKey: Keys.region) ?? ""
        self.postalCode = ubiquitousStore?.string(forKey: Keys.postalCode) ?? defaults.string(forKey: Keys.postalCode) ?? ""
        self.country = ubiquitousStore?.string(forKey: Keys.country) ?? defaults.string(forKey: Keys.country) ?? ""
        self.email = ubiquitousStore?.string(forKey: Keys.email) ?? defaults.string(forKey: Keys.email) ?? ""
        self.phone = ubiquitousStore?.string(forKey: Keys.phone) ?? defaults.string(forKey: Keys.phone) ?? ""
        self.website = ubiquitousStore?.string(forKey: Keys.website) ?? defaults.string(forKey: Keys.website) ?? ""
        self.agentName = ubiquitousStore?.string(forKey: Keys.agentName) ?? defaults.string(forKey: Keys.agentName) ?? ""
        self.agency = ubiquitousStore?.string(forKey: Keys.agency) ?? defaults.string(forKey: Keys.agency) ?? ""
        self.agentAddressLine1 = ubiquitousStore?.string(forKey: Keys.agentAddressLine1) ?? defaults.string(forKey: Keys.agentAddressLine1) ?? ""
        self.agentAddressLine2 = ubiquitousStore?.string(forKey: Keys.agentAddressLine2) ?? defaults.string(forKey: Keys.agentAddressLine2) ?? ""
        self.agentLocality = ubiquitousStore?.string(forKey: Keys.agentLocality) ?? defaults.string(forKey: Keys.agentLocality) ?? ""
        self.agentRegion = ubiquitousStore?.string(forKey: Keys.agentRegion) ?? defaults.string(forKey: Keys.agentRegion) ?? ""
        self.agentPostalCode = ubiquitousStore?.string(forKey: Keys.agentPostalCode) ?? defaults.string(forKey: Keys.agentPostalCode) ?? ""
        self.agentCountry = ubiquitousStore?.string(forKey: Keys.agentCountry) ?? defaults.string(forKey: Keys.agentCountry) ?? ""
        self.agentEmail = ubiquitousStore?.string(forKey: Keys.agentEmail) ?? defaults.string(forKey: Keys.agentEmail) ?? ""
        self.agentPhone = ubiquitousStore?.string(forKey: Keys.agentPhone) ?? defaults.string(forKey: Keys.agentPhone) ?? ""
        self.agentWebsite = ubiquitousStore?.string(forKey: Keys.agentWebsite) ?? defaults.string(forKey: Keys.agentWebsite) ?? ""
        migrateLocalValuesIfNeeded()
        let token = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitousStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadRemoteValues()
            }
        }
        ubiquitousStoreObserver = UbiquitousStoreObserver(token)
    }

    deinit {
        if let ubiquitousStoreObserver {
            NotificationCenter.default.removeObserver(ubiquitousStoreObserver.token)
        }
    }

    private func save(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
        guard !isApplyingRemoteValues else { return }
        ubiquitousStore?.set(value, forKey: key)
    }

    private func migrateLocalValuesIfNeeded() {
        guard let ubiquitousStore else { return }
        for (key, value) in values {
            if ubiquitousStore.object(forKey: key) == nil, defaults.object(forKey: key) != nil {
                ubiquitousStore.set(value, forKey: key)
            }
        }
    }

    private func loadRemoteValues() {
        guard let ubiquitousStore else { return }
        isApplyingRemoteValues = true
        defer { isApplyingRemoteValues = false }
        if let value = ubiquitousStore.string(forKey: Keys.name) { name = value }
        if let value = ubiquitousStore.string(forKey: Keys.penName) { penName = value }
        if let value = ubiquitousStore.string(forKey: Keys.addressLine1) { addressLine1 = value }
        if let value = ubiquitousStore.string(forKey: Keys.addressLine2) { addressLine2 = value }
        if let value = ubiquitousStore.string(forKey: Keys.locality) { locality = value }
        if let value = ubiquitousStore.string(forKey: Keys.region) { region = value }
        if let value = ubiquitousStore.string(forKey: Keys.postalCode) { postalCode = value }
        if let value = ubiquitousStore.string(forKey: Keys.country) { country = value }
        if let value = ubiquitousStore.string(forKey: Keys.email) { email = value }
        if let value = ubiquitousStore.string(forKey: Keys.phone) { phone = value }
        if let value = ubiquitousStore.string(forKey: Keys.website) { website = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentName) { agentName = value }
        if let value = ubiquitousStore.string(forKey: Keys.agency) { agency = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentAddressLine1) { agentAddressLine1 = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentAddressLine2) { agentAddressLine2 = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentLocality) { agentLocality = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentRegion) { agentRegion = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentPostalCode) { agentPostalCode = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentCountry) { agentCountry = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentEmail) { agentEmail = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentPhone) { agentPhone = value }
        if let value = ubiquitousStore.string(forKey: Keys.agentWebsite) { agentWebsite = value }
    }

    private var values: [(String, String)] {
        [
            (Keys.name, name), (Keys.penName, penName), (Keys.addressLine1, addressLine1),
            (Keys.addressLine2, addressLine2), (Keys.locality, locality), (Keys.region, region),
            (Keys.postalCode, postalCode), (Keys.country, country), (Keys.email, email),
            (Keys.phone, phone), (Keys.website, website), (Keys.agentName, agentName),
            (Keys.agency, agency), (Keys.agentAddressLine1, agentAddressLine1),
            (Keys.agentAddressLine2, agentAddressLine2), (Keys.agentLocality, agentLocality),
            (Keys.agentRegion, agentRegion), (Keys.agentPostalCode, agentPostalCode),
            (Keys.agentCountry, agentCountry), (Keys.agentEmail, agentEmail),
            (Keys.agentPhone, agentPhone), (Keys.agentWebsite, agentWebsite)
        ]
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
