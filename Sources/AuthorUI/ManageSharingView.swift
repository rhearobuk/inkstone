import AuthorData
import CloudKit
import SwiftUI

@MainActor
public final class ManageSharingModel: ObservableObject {
    public struct AccessGroup: Identifiable, Equatable {
        public let id: UUID
        public let name: String
        public let content: String
    }

    public struct ShareRow: Identifiable {
        public let id: String
        public let administrationGroupID: UUID
        public let projectTitle: String
        public let recipient: String
        public let role: String
        public let permission: String
        public let invitationState: String
        public let invitationURL: URL?
        public let accessGroups: [AccessGroup]

        public var emailURL: URL? {
            guard let invitationURL else { return nil }
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = recipient
            components.queryItems = [
                URLQueryItem(name: "subject", value: "Reminder: invitation to review \(projectTitle)"),
                URLQueryItem(
                    name: "body",
                    value: "Here is your Inkstone invitation. Open it while signed in to the invited iCloud account:\n\n\(invitationURL.absoluteString)"
                )
            ]
            return components.url
        }
    }

    @Published public private(set) var rows: [ShareRow] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var busyRowIDs: Set<String> = []

    private let projects: [WritingProject]
    private let service: CloudKitSharingService

    public init(projects: [WritingProject], service: CloudKitSharingService) {
        self.projects = projects
        self.service = service
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var updatedRows: [ShareRow] = []
        var refreshErrors: [String] = []

        for project in projects where !project.isDeleted {
            do {
                _ = try await service.refreshInvitationStatuses(for: project)
            } catch CloudSharingError.localOnlyBuild {
            } catch {
                refreshErrors.append("\(project.title): \(error.localizedDescription)")
            }

            let groups = ((try? service.dataStore.sharingGroups.fetchAll(
                predicate: NSPredicate(format: "projectID == %@", project.id as CVarArg)
            )) ?? []).filter { $0.state != "revoked" }
            let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
            let groupIDs = Set(groupsByID.keys)
            let participants = ((try? service.dataStore.shareParticipants.fetchAll()) ?? []).filter {
                $0.sharingGroupID.map(groupIDs.contains) == true && $0.invitationState != "revoked"
            }
            let participantsByIdentityAndScope = Dictionary(grouping: participants) { participant in
                let identity = participant.cloudKitIdentity?.lowercased() ?? participant.id.uuidString
                let scopeID = participant.sharingGroupID.flatMap { groupsByID[$0]?.scopeRootID }
                return "\(identity)|\(scopeID?.uuidString ?? "project")"
            }

            for (rowKey, records) in participantsByIdentityAndScope {
                let sortedRecords = records.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
                guard let latest = sortedRecords.first else { continue }
                let accessGroups = sortedRecords.compactMap { record -> AccessGroup? in
                    guard let groupID = record.sharingGroupID, let group = groupsByID[groupID] else { return nil }
                    return AccessGroup(
                        id: groupID,
                        name: Self.groupName(for: group.domain),
                        content: Self.contentDescription(for: group, project: project, service: service)
                    )
                }
                .reduce(into: [UUID: AccessGroup]()) { $0[$1.id] = $1 }
                .values
                .sorted { $0.name < $1.name }
                let manuscriptGroup = sortedRecords.compactMap { record in
                    record.sharingGroupID.flatMap { groupsByID[$0] }
                }.first { $0.domain == SharingGroupDomain.manuscript.rawValue }
                guard let administrationGroup = manuscriptGroup ?? sortedRecords.compactMap({ record in
                    record.sharingGroupID.flatMap { groupsByID[$0] }
                }).first else { continue }
                let invitationURL = manuscriptGroup.flatMap { try? service.invitationURL(for: $0) }

                updatedRows.append(ShareRow(
                    id: "\(project.id.uuidString)-\(rowKey)",
                    administrationGroupID: administrationGroup.id,
                    projectTitle: project.title,
                    recipient: latest.cloudKitIdentity ?? "Unknown participant",
                    role: latest.inkstoneRole,
                    permission: latest.cloudKitPermission,
                    invitationState: latest.invitationState,
                    invitationURL: invitationURL,
                    accessGroups: accessGroups
                ))
            }
        }

        rows = updatedRows.sorted {
            ($0.projectTitle.localizedStandardCompare($1.projectTitle) == .orderedAscending)
                || ($0.projectTitle == $1.projectTitle
                    && $0.recipient.localizedStandardCompare($1.recipient) == .orderedAscending)
        }
        errorMessage = refreshErrors.isEmpty ? nil : refreshErrors.joined(separator: "\n")
        lastUpdated = Date()
    }

    public func changeRole(for row: ShareRow, to role: SharingRole) async {
        guard role != .owner, !busyRowIDs.contains(row.id) else { return }
        busyRowIDs.insert(row.id)
        defer { busyRowIDs.remove(row.id) }

        do {
            let group = try service.dataStore.sharingGroups.require(id: row.administrationGroupID)
            let permission: CKShare.ParticipantPermission = role == .viewer ? .readOnly : .readWrite
            try await service.updatePermission(for: row.recipient, in: group, to: permission)

            let accessGroupIDs = Set(row.accessGroups.map(\.id))
            let matchingRecords = try service.dataStore.shareParticipants.fetchAll(
                predicate: NSPredicate(format: "cloudKitIdentity == %@", row.recipient)
            ).filter { record in
                record.sharingGroupID.map(accessGroupIDs.contains) == true
            }
            for record in matchingRecords {
                record.inkstoneRole = role.rawValue
                record.modifiedAt = Date()
            }
            try service.dataStore.save()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revoke(_ row: ShareRow) async {
        guard !busyRowIDs.contains(row.id) else { return }
        busyRowIDs.insert(row.id)
        defer { busyRowIDs.remove(row.id) }

        do {
            let group = try service.dataStore.sharingGroups.require(id: row.administrationGroupID)
            try await service.revokeParticipant(identity: row.recipient, from: group)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func groupName(for domain: String) -> String {
        switch domain {
        case SharingGroupDomain.manuscript.rawValue: "Manuscript"
        case SharingGroupDomain.feedback.rawValue: "Feedback"
        case SharingGroupDomain.storyContext.rawValue: "Story Bible"
        default: domain.capitalized
        }
    }

    private static func contentDescription(
        for group: SharingGroup,
        project: WritingProject,
        service: CloudKitSharingService
    ) -> String {
        let scopeTitle: String
        if let scopeID = group.scopeRootID, scopeID != project.id,
           let document = try? service.dataStore.documents.fetchAll(predicate: NSPredicate(
                format: "id == %@ AND sharingGroupID == nil",
                scopeID as CVarArg
           )).first {
            scopeTitle = document.title
        } else {
            scopeTitle = project.title
        }

        switch group.domain {
        case SharingGroupDomain.manuscript.rawValue: return "Reviewable manuscript content in \(scopeTitle)"
        case SharingGroupDomain.feedback.rawValue: return "Comments and review feedback for \(scopeTitle)"
        case SharingGroupDomain.storyContext.rawValue: return "Granted Story Bible context for \(scopeTitle)"
        default: return scopeTitle
        }
    }
}

public struct ManageSharingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ManageSharingModel
    @State private var pendingRevocation: ManageSharingModel.ShareRow?

    public init(model: ManageSharingModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if model.rows.isEmpty && !model.isRefreshing {
                    ContentUnavailableView(
                        "No Active Shares",
                        systemImage: "person.2.slash",
                        description: Text("Create an invitation from Share for Review. It will appear here with its acceptance status and access groups.")
                    )
                } else {
                    List(model.rows) { row in
                        ShareManagementRow(
                            row: row,
                            isBusy: model.busyRowIDs.contains(row.id),
                            onRoleChange: { role in Task { await model.changeRole(for: row, to: role) } },
                            onRevoke: { pendingRevocation = row }
                        )
                    }
                }
            }
            .overlay {
                if model.isRefreshing && model.rows.isEmpty {
                    ProgressView("Checking iCloud sharing status…")
                }
            }
            .navigationTitle("Manage Sharing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.bar)
                } else if let lastUpdated = model.lastUpdated {
                    Text("Status checked \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .task { await model.refresh() }
            .confirmationDialog(
                "Revoke access for \(pendingRevocation?.recipient ?? "this participant")?",
                isPresented: Binding(
                    get: { pendingRevocation != nil },
                    set: { if !$0 { pendingRevocation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Revoke Access", role: .destructive) {
                    guard let row = pendingRevocation else { return }
                    pendingRevocation = nil
                    Task { await model.revoke(row) }
                }
                Button("Cancel", role: .cancel) { pendingRevocation = nil }
            } message: {
                Text("This removes access to every listed access group for this share. Content already downloaded cannot be recalled.")
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 560, idealHeight: 680)
    }
}

private struct ShareManagementRow: View {
    let row: ManageSharingModel.ShareRow
    let isBusy: Bool
    let onRoleChange: (SharingRole) -> Void
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.recipient)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(row.projectTitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                InvitationStatusBadge(state: row.invitationState)
            }

            HStack(spacing: 8) {
                Label(row.role.capitalized, systemImage: "person.crop.circle")
                Text("·")
                Text(row.permission == "readOnly" ? "Read only" : "Can edit")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Menu {
                    ForEach([SharingRole.viewer, .reviewer, .editor, .collaborator], id: \.self) { role in
                        Button(role.rawValue.capitalized) { onRoleChange(role) }
                    }
                } label: {
                    Label("Change Access", systemImage: "person.badge.key")
                }
                .disabled(isBusy)

                Button("Revoke Access", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                    onRevoke()
                }
                .disabled(isBusy)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Access Groups")
                    .font(.subheadline.weight(.semibold))
                ForEach(row.accessGroups) { group in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text(group.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let invitationURL = row.invitationURL {
                HStack {
                    if let emailURL = row.emailURL {
                        Link(destination: emailURL) {
                            Label("Email Again", systemImage: "envelope")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ShareLink(
                        item: invitationURL,
                        subject: Text("Invitation to review \(row.projectTitle)"),
                        message: Text("Open this invitation in Inkstone while signed in to iCloud.")
                    ) {
                        Label("Resend Another Way", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label("Invitation link unavailable. Refresh while connected to iCloud.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct InvitationStatusBadge: View {
    let state: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Invitation status: \(label)")
    }

    private var label: String {
        switch state {
        case "accepted": "Accepted"
        case "removed": "Removed"
        case "pending": "Awaiting Acceptance"
        default: "Status Unknown"
        }
    }

    private var symbol: String {
        switch state {
        case "accepted": "checkmark.circle.fill"
        case "removed": "xmark.circle.fill"
        case "pending": "clock.fill"
        default: "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case "accepted": .green
        case "removed": .red
        case "pending": .orange
        default: .secondary
        }
    }
}
