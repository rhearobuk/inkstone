import AuthorData
import CloudKit
import SwiftUI

@MainActor
public final class ShareReviewWorkflowModel: ObservableObject {
    public enum GroupKind: String, CaseIterable, Identifiable { case manuscript, feedback, context; public var id: Self { self } }
    public enum GroupState: Equatable { case notRequired, ready, pending, succeeded, failed(String) }
    public struct ScopeOption: Identifiable, Hashable {
        public let id: UUID?
        public let title: String
        public let depth: Int
    }

    @Published public var recipient = ""
    @Published public var role: SharingRole = .reviewer
    @Published public var selectedStatusIdentifiers: Set<String>
    @Published public var storyBibleGrant: StoryBibleGrant = .none
    @Published public private(set) var preview: ReviewAccessPolicyResult?
    @Published public private(set) var groupStates: [GroupKind: GroupState] = [:]
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var participants: [ShareParticipant] = []
    @Published public private(set) var invitationURL: URL?
    @Published public private(set) var isCreatingInvitation = false

    public let project: WritingProject
    @Published public var selectedScopeID: UUID?
    private let service: CloudKitSharingService

    public init(project: WritingProject, scopeRoot: Document, service: CloudKitSharingService) {
        self.project = project
        selectedScopeID = scopeRoot.id
        self.service = service
        let statuses = project.statusDefinitions.filter(\.isDefault).map(\.sourceIdentifier)
        selectedStatusIdentifiers = Set(statuses)
        rebuildPreview()
        refreshParticipants()
    }

    public var availableStatuses: [StatusDefinition] {
        project.statusDefinitions.sorted { ($0.orderIndex, $0.sourceIdentifier) < ($1.orderIndex, $1.sourceIdentifier) }
    }

    public var availableScopes: [ScopeOption] {
        let documents = projectDocuments
        let ids = Set(documents.map(\.id))
        let children = Dictionary(grouping: documents, by: { document in
            document.parentID.flatMap(ids.contains) == true ? document.parentID : nil
        })
        var result = [ScopeOption(id: nil, title: project.title, depth: 0)]
        func append(_ document: Document, depth: Int) {
            result.append(ScopeOption(id: document.id, title: document.title, depth: depth))
            for child in (children[document.id] ?? []).sorted(by: documentOrder) {
                append(child, depth: depth + 1)
            }
        }
        for root in (children[nil] ?? []).sorted(by: documentOrder) { append(root, depth: 1) }
        return result
    }

    private var projectDocuments: [Document] {
        let fetched = (try? service.dataStore.documents.fetchAll(
            predicate: NSPredicate(format: "projectID == %@", project.id as CVarArg)
        )) ?? Array(project.documents)
        var seenIDs = Set<UUID>()
        return fetched.filter { !$0.isDeleted && $0.sharingGroupID == nil && seenIDs.insert($0.id).inserted }
    }

    public var canShare: Bool {
        !isCreatingInvitation
            && !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preview?.includedCount ?? 0 > 0
    }

    public var emailInvitationURL: URL? {
        guard let invitationURL else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Invitation to review \(project.title)"),
            URLQueryItem(
                name: "body",
                value: "You have been invited to review \(project.title) in Inkstone. Open this invitation while signed in to iCloud:\n\n\(invitationURL.absoluteString)"
            )
        ]
        return components.url
    }

    public func rebuildPreview() {
        do {
            var records = projectDocuments.map { document in
                ReviewPolicyRecord(
                    id: document.id,
                    projectID: project.id,
                    parentID: document.parentID,
                    kind: document.kind == DocumentKind.text.rawValue ? .manuscriptText : .structure,
                    statusIdentifier: document.statusIdentifier,
                    includeInCompile: document.includeInCompile?.boolValue
                )
            }
            let scopeRootID: UUID
            if let selectedScopeID {
                scopeRootID = selectedScopeID
            } else {
                scopeRootID = project.id
                records = records.map { record in
                    ReviewPolicyRecord(
                        id: record.id,
                        projectID: record.projectID,
                        parentID: record.parentID ?? project.id,
                        kind: record.kind,
                        statusIdentifier: record.statusIdentifier,
                        includeInCompile: record.includeInCompile
                    )
                }
                records.append(ReviewPolicyRecord(id: project.id, projectID: project.id, kind: .structure))
            }
            let policy = ReviewAccessPolicy(
                version: 1,
                projectID: project.id,
                scopeRootID: scopeRootID,
                reviewableStatusIdentifiers: selectedStatusIdentifiers
            )
            let reviewRole: ReviewParticipantRole = role == .viewer ? .viewer : (role == .reviewer ? .reviewer : .editor)
            preview = try ReviewAccessPolicyResolver.preview(
                policy: policy,
                grant: .init(role: reviewRole, storyBible: storyBibleGrant),
                records: records
            )
            groupStates[.manuscript] = .ready
            groupStates[.feedback] = role == .viewer ? .notRequired : .ready
            groupStates[.context] = storyBibleGrant == .none ? .notRequired : .ready
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    public func beginSharing() async {
        rebuildPreview()
        guard canShare else { return }
        guard service.state != .localOnly else {
            errorMessage = CloudSharingError.localOnlyBuild.localizedDescription
            return
        }
        isCreatingInvitation = true
        defer { isCreatingInvitation = false }
        invitationURL = nil
        let required = GroupKind.allCases.filter { groupStates[$0] == .ready || isFailed(groupStates[$0]) }
        for kind in required { groupStates[kind] = .pending }
        for kind in required {
            do {
                let group = try prepareGroup(for: kind)
                let permission = cloudKitPermission(for: kind)
                let share = try await service.publishInvitation(
                    for: group,
                    recipientEmail: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                    permission: permission
                )
                invitationURL = share.url ?? invitationURL
                if let participant = try service.participants(for: group).last {
                    participant.inkstoneRole = role.rawValue
                    try service.dataStore.save()
                }
                groupStates[kind] = .succeeded
            } catch {
                service.dataStore.context.rollback()
                groupStates[kind] = .failed(Self.actionableMessage(for: error, group: kind))
            }
        }
        refreshParticipants()
        if groupStates.values.contains(where: { if case .failed = $0 { true } else { false } }) {
            errorMessage = "Some invitation groups failed. Successful groups remain active; retry only the failed groups."
        } else if invitationURL == nil {
            errorMessage = "The share was created, but iCloud did not return an invitation link. Refresh Manage Sharing and try again."
        }
    }

    public func record(_ result: SharingGroupOperationResult, for kind: GroupKind) {
        groupStates[kind] = result.succeeded ? .succeeded : .failed(result.message ?? "Sharing failed")
    }

    public func refreshParticipants() {
        let projectGroupIDs = Set(((try? service.dataStore.sharingGroups.fetchAll(
            predicate: NSPredicate(format: "projectID == %@", project.id as CVarArg)
        )) ?? []).map(\.id))
        let records = ((try? service.dataStore.shareParticipants.fetchAll()) ?? []).filter {
            $0.invitationState != "revoked" && $0.sharingGroupID.map(projectGroupIDs.contains) == true
        }
        var seenIdentities = Set<String>()
        participants = records
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            .filter { participant in
                let identity = participant.cloudKitIdentity?.lowercased() ?? participant.id.uuidString
                return seenIdentities.insert(identity).inserted
            }
    }

    public func revoke(_ participant: ShareParticipant) async {
        guard let groupID = participant.sharingGroupID,
              let group = try? service.dataStore.sharingGroups.require(id: groupID),
              let identity = participant.cloudKitIdentity else { return }
        do {
            try await service.revokeParticipant(identity: identity, from: group)
            refreshParticipants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func changeRole(for participant: ShareParticipant, to newRole: SharingRole) async {
        guard let identity = participant.cloudKitIdentity,
              let groupID = participant.sharingGroupID,
              let group = try? service.dataStore.sharingGroups.fetch(id: groupID) else { return }
        do {
            let matching = try service.dataStore.shareParticipants.fetchAll(
                predicate: NSPredicate(format: "cloudKitIdentity == %@", identity)
            )
            let permission: CKShare.ParticipantPermission = newRole == .viewer ? .readOnly : .readWrite
            try await service.updatePermission(for: identity, in: group, to: permission)
            for record in matching {
                record.inkstoneRole = newRole.rawValue
            }
            try service.dataStore.save()
            refreshParticipants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func actionableMessage(for error: Error, group: GroupKind) -> String {
        if let sharingError = error as? CloudSharingError {
            switch sharingError {
            case .unsafeObjectGraph:
                return "Inkstone found private linked data and stopped before uploading anything. Your project was not changed."
            case .staleShareZone:
                return "The previous iCloud share no longer exists. Close and reopen Inkstone, then try again."
            default:
                break
            }
        }
        let nsError = error as NSError
        if containsCocoaError(134060, in: nsError) {
            return "This local library still contains records tied to old iCloud shares. This is not an entitlement or connection problem. Reset the local development library before sharing again."
        }
        if group == .context, nsError.domain == NSCocoaErrorDomain {
            return "Story Bible access could not be prepared. Set Story Bible Access to None to continue without it."
        }
        return "Couldn’t create this invitation. iCloud returned error \(nsError.code)."
    }

    private static func containsCocoaError(_ code: Int, in error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain, error.code == code { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           containsCocoaError(code, in: underlying) {
            return true
        }
        return error.userInfo.values.contains { value in
            guard let nested = value as? NSError else { return false }
            return containsCocoaError(code, in: nested)
        }
    }

    private func prepareGroup(for kind: GroupKind) throws -> SharingGroup {
        let domain = domain(for: kind)
        let scopeRootID = selectedScopeID ?? project.id
        let predicate = NSPredicate(
            format: "projectID == %@ AND scopeRootID == %@ AND domain == %@",
            project.id as CVarArg, scopeRootID as CVarArg, domain.rawValue
        )
        let existing = try service.dataStore.sharingGroups.fetchAll(predicate: predicate).first { group in
            group.state != "legacyRevoked"
                && (try? service.isLegacyProjectShare(group, project: project)) != true
        }
        let group = existing ?? service.dataStore.sharingGroups.create { group in
                group.projectID = project.id
                group.scopeRootID = scopeRootID
                group.domain = domain.rawValue
                group.state = "preparing"
                group.createdAt = Date()
                group.modifiedAt = Date()
            }
        if kind == .manuscript, let preview {
            let includedIDs = Set(preview.included.map(\.recordID))
            try service.prepareScopedManuscript(
                for: group,
                project: project,
                documents: projectDocuments.filter { includedIDs.contains($0.id) }
            )
        }
        group.state = "ready"
        group.modifiedAt = Date()
        try service.dataStore.save()
        return group
    }

    private func domain(for kind: GroupKind) -> SharingGroupDomain {
        switch kind { case .manuscript: .manuscript; case .feedback: .feedback; case .context: .storyContext }
    }

    private func cloudKitPermission(for kind: GroupKind) -> CKShare.ParticipantPermission {
        // CloudKit has one permission per participant for the whole project share.
        // Inkstone enforces the narrower manuscript, feedback, and context capabilities.
        role == .viewer ? .readOnly : .readWrite
    }

    private func isFailed(_ state: GroupState?) -> Bool {
        if case .failed = state { return true }
        return false
    }

    private func documentOrder(_ lhs: Document, _ rhs: Document) -> Bool {
        (lhs.orderIndex, lhs.title, lhs.id.uuidString) < (rhs.orderIndex, rhs.title, rhs.id.uuidString)
    }
}

public struct ShareReviewWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ShareReviewWorkflowModel

    public init(model: ShareReviewWorkflowModel) { _model = StateObject(wrappedValue: model) }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Invite a reader", systemImage: "person.crop.circle.badge.plus")
                        .font(.title2.weight(.semibold))
                    Text("Choose exactly what this person can read and edit. Review the summary before creating the invitation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider()

                Form {
                    recipientSection
                    scopeSection
                    eligibilitySection
                    contextSection
                    previewSection
                    progressSection
                    sendInvitationSection
                    participantSection
                }
                .formStyle(.grouped)
                .padding(.horizontal, 20)
            }
            .navigationTitle("Share for Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Invitation Link") { Task { await model.beginSharing() } }
                        .disabled(!model.canShare)
                        .accessibilityIdentifier("shareReview.createInvitations")
                }
            }
            .onAppear {
                model.rebuildPreview()
                model.refreshParticipants()
            }
            .onChange(of: model.role) { _, _ in model.rebuildPreview() }
            .onChange(of: model.selectedScopeID) { _, _ in model.rebuildPreview() }
            .onChange(of: model.selectedStatusIdentifiers) { _, _ in model.rebuildPreview() }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 700, idealHeight: 780)
    }

    private var recipientSection: some View {
        Section("Recipient and Role") {
            TextField("Recipient email or contact", text: $model.recipient)
                .textContentType(.emailAddress)
                .accessibilityIdentifier("shareReview.recipient")
            Picker("Role", selection: $model.role) {
                Text("Viewer").tag(SharingRole.viewer)
                Text("Reviewer").tag(SharingRole.reviewer)
                Text("Editor").tag(SharingRole.editor)
                Text("Collaborator").tag(SharingRole.collaborator)
            }
        }
    }

    private var scopeSection: some View {
        Section("Scope") {
            LabeledContent("Project", value: model.project.title)
            Picker("Share", selection: $model.selectedScopeID) {
                ForEach(model.availableScopes) { scope in
                    Text(String(repeating: "  ", count: scope.depth) + scope.title)
                        .tag(scope.id)
                }
            }
            .accessibilityIdentifier("shareReview.contentScope")
            Text("Choose the whole project or any binder item. Everything nested beneath that item is included according to the status rules below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eligibilitySection: some View {
        Section("Reviewable Statuses") {
            ForEach(model.availableStatuses, id: \.id) { status in
                Toggle(status.title, isOn: Binding(
                    get: { model.selectedStatusIdentifiers.contains(status.sourceIdentifier) },
                    set: { selected in
                        if selected { model.selectedStatusIdentifiers.insert(status.sourceIdentifier) }
                        else { model.selectedStatusIdentifiers.remove(status.sourceIdentifier) }
                    }
                ))
            }
        }
    }

    private var contextSection: some View {
        Section("Story Bible Access") {
            Picker("Context", selection: $model.storyBibleGrant) {
                Text("None").tag(StoryBibleGrant.none)
                Text("Full Read").tag(StoryBibleGrant.fullRead)
                Text("Edit").tag(StoryBibleGrant.edit)
            }
            .onChange(of: model.storyBibleGrant) { _, _ in model.rebuildPreview() }
        }
    }

    private var previewSection: some View {
        Section("Exact Sharing Preview") {
            if let preview = model.preview {
                if preview.includedCount == 0 {
                    Label {
                        Text("Nothing can be shared yet. Review the exclusion counts below, then adjust the selected scope, publication settings, or statuses.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Included", value: preview.includedCount.formatted())
                LabeledContent("Excluded", value: preview.excludedCount.formatted())
                ForEach(ReviewExclusionReason.allCases, id: \.self) { reason in
                    let count = preview.exclusionCount(for: reason)
                    if count > 0 { LabeledContent(reason.label, value: count.formatted()) }
                }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
    }

    private var progressSection: some View {
        Section("Invitation Groups") {
            ForEach(ShareReviewWorkflowModel.GroupKind.allCases) { kind in
                HStack { Text(kind.label); Spacer(); Text(model.groupStates[kind, default: .notRequired].label) }
            }
            Text("Invitations are independent. Partial completion remains retryable and is never shown as fully shared.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sendInvitationSection: some View {
        if let invitationURL = model.invitationURL {
            Section("Send Invitation") {
                Text("The reader will not see shared content until they open and accept this link using the iCloud account you invited.")
                    .foregroundStyle(.secondary)
                if let emailURL = model.emailInvitationURL {
                    Link(destination: emailURL) {
                        Label("Email Invitation to \(model.recipient)", systemImage: "envelope")
                    }
                    .buttonStyle(.borderedProminent)
                }
                ShareLink(
                    item: invitationURL,
                    subject: Text("Invitation to review \(model.project.title)"),
                    message: Text("Open this invitation in Inkstone while signed in to iCloud.")
                ) {
                    Label("Send Another Way", systemImage: "square.and.arrow.up")
                }
                Text(invitationURL.absoluteString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var participantSection: some View {
        Section("Participants") {
            if model.participants.isEmpty {
                Text("No current participants")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.participants, id: \.id) { participant in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(participant.cloudKitIdentity ?? "Pending identity")
                            Text("\(participant.inkstoneRole.capitalized) · \(participant.cloudKitPermission)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu(participant.inkstoneRole.capitalized) {
                            Button("Viewer") { Task { await model.changeRole(for: participant, to: .viewer) } }
                            Button("Reviewer") { Task { await model.changeRole(for: participant, to: .reviewer) } }
                            Button("Editor") { Task { await model.changeRole(for: participant, to: .editor) } }
                            Button("Collaborator") { Task { await model.changeRole(for: participant, to: .collaborator) } }
                        }
                        Button("Revoke", role: .destructive) { Task { await model.revoke(participant) } }
                    }
                }
            }
            Text("Revocation prevents future access after CloudKit propagates it; it cannot recall content already downloaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension ReviewExclusionReason {
    var label: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
}

private extension ShareReviewWorkflowModel.GroupKind { var label: String { rawValue.capitalized } }
private extension ShareReviewWorkflowModel.GroupState {
    var label: String {
        switch self { case .notRequired: "Not Required"; case .ready: "Ready"; case .pending: "Pending";
        case .succeeded: "Shared"; case .failed(let message): "Failed: \(message)" }
    }
}
