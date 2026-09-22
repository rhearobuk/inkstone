import AuthorData
import CloudKit
import SwiftUI

@MainActor
public final class ShareReviewWorkflowModel: ObservableObject {
    public enum GroupKind: String, CaseIterable, Identifiable { case manuscript, feedback, context; public var id: Self { self } }
    public enum GroupState: Equatable { case notRequired, ready, pending, succeeded, failed(String) }

    @Published public var recipient = ""
    @Published public var role: SharingRole = .reviewer
    @Published public var selectedStatusIdentifiers: Set<String>
    @Published public var storyBibleGrant: StoryBibleGrant = .none
    @Published public private(set) var preview: ReviewAccessPolicyResult?
    @Published public private(set) var groupStates: [GroupKind: GroupState] = [:]
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var participants: [ShareParticipant] = []

    public let project: WritingProject
    public let scopeRoot: Document
    private let service: CloudKitSharingService

    public init(project: WritingProject, scopeRoot: Document, service: CloudKitSharingService) {
        self.project = project
        self.scopeRoot = scopeRoot
        self.service = service
        let statuses = project.statusDefinitions.filter(\.isDefault).map(\.sourceIdentifier)
        selectedStatusIdentifiers = Set(statuses)
        rebuildPreview()
    }

    public var availableStatuses: [StatusDefinition] {
        project.statusDefinitions.sorted { ($0.orderIndex, $0.sourceIdentifier) < ($1.orderIndex, $1.sourceIdentifier) }
    }

    public var canShare: Bool {
        !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && preview?.includedCount ?? 0 > 0
    }

    public func rebuildPreview() {
        do {
            let records = project.documents.filter { !$0.isDeleted }.map { document in
                ReviewPolicyRecord(
                    id: document.id,
                    projectID: project.id,
                    parentID: document.parent?.id,
                    kind: document.kind == DocumentKind.text.rawValue ? .manuscriptText : .structure,
                    statusIdentifier: document.statusIdentifier,
                    includeInCompile: document.includeInCompile?.boolValue
                )
            }
            let policy = ReviewAccessPolicy(
                version: 1,
                projectID: project.id,
                scopeRootID: scopeRoot.id,
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
        let required = GroupKind.allCases.filter { groupStates[$0] == .ready || isFailed(groupStates[$0]) }
        for kind in required { groupStates[kind] = .pending }
        for kind in required {
            do {
                let group = try prepareGroup(for: kind)
                let permission = cloudKitPermission(for: kind)
                _ = try await service.publishInvitation(
                    for: group,
                    recipientEmail: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                    permission: permission
                )
                if let participant = try service.participants(for: group).last {
                    participant.inkstoneRole = role.rawValue
                    try service.dataStore.save()
                }
                groupStates[kind] = .succeeded
            } catch {
                groupStates[kind] = .failed(error.localizedDescription)
            }
        }
        refreshParticipants()
        if groupStates.values.contains(where: { if case .failed = $0 { true } else { false } }) {
            errorMessage = "Some invitation groups failed. Successful groups remain active; retry only the failed groups."
        }
    }

    public func record(_ result: SharingGroupOperationResult, for kind: GroupKind) {
        groupStates[kind] = result.succeeded ? .succeeded : .failed(result.message ?? "Sharing failed")
    }

    public func refreshParticipants() {
        participants = (try? service.dataStore.shareParticipants.fetchAll()) ?? []
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
        guard let identity = participant.cloudKitIdentity else { return }
        do {
            let matching = try service.dataStore.shareParticipants.fetchAll(
                predicate: NSPredicate(format: "cloudKitIdentity == %@", identity)
            )
            for record in matching {
                guard let groupID = record.sharingGroupID,
                      let group = try service.dataStore.sharingGroups.fetch(id: groupID) else { continue }
                if group.domain == SharingGroupDomain.feedback.rawValue, newRole == .viewer {
                    try await service.revokeParticipant(identity: identity, from: group)
                    continue
                }
                let permission: CKShare.ParticipantPermission
                if group.domain == SharingGroupDomain.manuscript.rawValue {
                    permission = newRole == .viewer || newRole == .reviewer ? .readOnly : .readWrite
                } else {
                    permission = record.cloudKitPermission == "readOnly" ? .readOnly : .readWrite
                }
                try await service.updatePermission(for: identity, in: group, to: permission)
                record.inkstoneRole = newRole.rawValue
            }
            try service.dataStore.save()
            refreshParticipants()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareGroup(for kind: GroupKind) throws -> SharingGroup {
        let domain = domain(for: kind)
        let predicate = NSPredicate(
            format: "projectID == %@ AND scopeRootID == %@ AND domain == %@",
            project.id as CVarArg, scopeRoot.id as CVarArg, domain.rawValue
        )
        let group = try service.dataStore.sharingGroups.fetchAll(predicate: predicate).first
            ?? service.dataStore.sharingGroups.create { group in
                group.projectID = project.id
                group.scopeRootID = scopeRoot.id
                group.domain = domain.rawValue
                group.state = "preparing"
                group.createdAt = Date()
                group.modifiedAt = Date()
            }
        let preparer = CanonicalSharingGraphPreparer()
        switch kind {
        case .manuscript:
            let includedIDs = Set(preview?.included.map(\.recordID) ?? [])
            try preparer.prepareManuscript(project.documents.filter { includedIDs.contains($0.id) }, for: group)
        case .feedback:
            break
        case .context:
            let entities: [SemanticEntity]
            switch storyBibleGrant {
            case .none: entities = []
            case .selected(let ids): entities = project.semanticEntities.filter { ids.contains($0.id) }
            case .fullRead, .edit: entities = Array(project.semanticEntities)
            }
            try preparer.prepareStoryContext(entities, for: group)
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
        switch kind {
        case .feedback: .readWrite
        case .context: storyBibleGrant == .edit ? .readWrite : .readOnly
        case .manuscript: role == .viewer || role == .reviewer ? .readOnly : .readWrite
        }
    }

    private func isFailed(_ state: GroupState?) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

public struct ShareReviewWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ShareReviewWorkflowModel

    public init(model: ShareReviewWorkflowModel) { _model = StateObject(wrappedValue: model) }

    public var body: some View {
        NavigationStack {
            Form {
                recipientSection
                scopeSection
                eligibilitySection
                contextSection
                previewSection
                progressSection
                participantSection
            }
            .navigationTitle("Share for Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Invitations") { Task { await model.beginSharing() } }
                        .disabled(!model.canShare)
                        .accessibilityIdentifier("shareReview.createInvitations")
                }
            }
            .onChange(of: model.role) { _, _ in model.rebuildPreview() }
            .onChange(of: model.selectedStatusIdentifiers) { _, _ in model.rebuildPreview() }
        }
        .frame(minWidth: 540, minHeight: 620)
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
            LabeledContent("Book", value: model.scopeRoot.title)
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
                        Menu("Role") {
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
