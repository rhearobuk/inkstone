import AuthorData
import CoreData
import Foundation

public enum BinderContentTarget: Hashable, Codable, Sendable {
    case document(UUID)
    case semanticEntity(UUID)

    public var id: UUID {
        switch self {
        case .document(let id), .semanticEntity(let id): id
        }
    }
}

public struct BinderDragPayload: Codable, Sendable {
    public let projectID: UUID
    public let target: BinderContentTarget

    public init(projectID: UUID, target: BinderContentTarget) {
        self.projectID = projectID
        self.target = target
    }

    public var encoded: String {
        let kind: String
        switch target {
        case .document: kind = "document"
        case .semanticEntity: kind = "entity"
        }
        return "inkstone:\(projectID.uuidString):\(kind):\(target.id.uuidString)"
    }

    public static func decode(_ string: String) throws -> Self {
        let components = string.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4, components[0] == "inkstone",
              let projectID = UUID(uuidString: String(components[1])),
              let id = UUID(uuidString: String(components[3])) else {
            throw ContentManagementError.invalidDrag
        }
        let target: BinderContentTarget
        switch components[2] {
        case "document": target = .document(id)
        case "entity": target = .semanticEntity(id)
        default: throw ContentManagementError.invalidDrag
        }
        return Self(projectID: projectID, target: target)
    }
}

public enum ContentManagementError: LocalizedError {
    case invalidDrag
    case unavailableTarget
    case foreignDefinition
    case filteredMovement
    case movementBoundary

    public var errorDescription: String? {
        switch self {
        case .invalidDrag: "This is not a valid Inkstone binder item."
        case .unavailableTarget: "This item is unavailable, in the Trash, or belongs to another project."
        case .foreignDefinition: "Choose a label or status from the current project's definitions."
        case .filteredMovement: "Clear the binder search and filters before reorganizing items."
        case .movementBoundary: "This item cannot move any further in that direction."
        }
    }
}

@MainActor
private enum ManagedContent {
    case document(Document)
    case entity(SemanticEntity)

    var target: BinderContentTarget {
        switch self {
        case .document(let document): .document(document.id)
        case .entity(let entity): .semanticEntity(entity.id)
        }
    }

    var project: WritingProject {
        switch self {
        case .document(let document): document.project
        case .entity(let entity): entity.project
        }
    }

    var order: Int64? {
        switch self {
        case .document(let document): document.storyBibleOrderIndex?.int64Value
        case .entity(let entity): entity.storyBibleOrderIndex?.int64Value
        }
    }

    func setOrder(_ index: Int64?) {
        let value = index.map { NSNumber(value: $0) }
        switch self {
        case .document(let document):
            document.storyBibleOrderIndex = value
            document.modifiedAt = Date()
        case .entity(let entity):
            entity.storyBibleOrderIndex = value
            entity.modifiedAt = Date()
        }
    }
}

extension WorkspaceController {
    public var canReorderBinder: Bool {
        binderSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            labelFilter == nil && statusFilter == nil
    }

    public func contentTarget(for entity: SemanticEntity) -> BinderContentTarget {
        if let document = entity.characterProfile?.sourceDocument {
            return .document(document.id)
        }
        return .semanticEntity(entity.id)
    }

    public func contentMetadata(
        for target: BinderContentTarget
    ) throws -> (labelIdentifier: String?, statusIdentifier: String?) {
        switch try managedContent(target, allowsTrashed: true) {
        case .document(let document): (document.labelIdentifier, document.statusIdentifier)
        case .entity(let entity): (entity.labelIdentifier, entity.statusIdentifier)
        }
    }

    public func setContentLabel(_ identifier: String?, for target: BinderContentTarget) throws {
        let content = try managedContent(target)
        guard identifier == nil || content.project.labelDefinitions.contains(where: {
            !$0.isDeleted && $0.sourceIdentifier == identifier
        }) else { throw ContentManagementError.foreignDefinition }
        try performContentMutation {
            switch content {
            case .document(let document):
                document.labelIdentifier = identifier
                document.modifiedAt = Date()
            case .entity(let entity):
                entity.labelIdentifier = identifier
                entity.modifiedAt = Date()
            }
            content.project.modifiedAt = Date()
        }
    }

    public func setContentStatus(_ identifier: String?, for target: BinderContentTarget) throws {
        let content = try managedContent(target)
        guard identifier == nil || content.project.statusDefinitions.contains(where: {
            !$0.isDeleted && $0.sourceIdentifier == identifier
        }) else { throw ContentManagementError.foreignDefinition }
        try performContentMutation {
            switch content {
            case .document(let document):
                document.statusIdentifier = identifier
                document.modifiedAt = Date()
            case .entity(let entity):
                entity.statusIdentifier = identifier
                entity.modifiedAt = Date()
            }
            content.project.modifiedAt = Date()
        }
    }

    public func deleteSemanticEntity(_ id: UUID) throws {
        let entity = try store.semanticEntities.require(id: id)
        guard !entity.isDeleted, entity.project.id == selectedProjectID else {
            throw ContentManagementError.unavailableTarget
        }
        _ = try managedContent(contentTarget(for: entity))
        let project = entity.project
        let category = StoryBibleCategory.allCases.first { $0.contains(kind: entity.kind) } ?? .worldbuilding
        try performContentMutation {
            selection = .storyBibleCategory(projectID: project.id, category: category)
            if let profile = entity.characterProfile {
                if let document = profile.sourceDocument {
                    WordCountService.removeSubtree(document, from: document.parent)
                    document.parent = nil
                    store.context.delete(document)
                }
                store.context.delete(profile)
            }
            store.context.delete(entity)
            project.modifiedAt = Date()
        }
    }

    public func storyBibleItems(in category: StoryBibleCategory) -> [BinderItem] {
        binderItems.first { $0.kind == .storyBible }?
            .children?.first { $0.kind == .storyBibleCategory(category) }?.children ?? []
    }

    public func canMoveContent(_ target: BinderContentTarget, offset: Int) -> Bool {
        guard canReorderBinder, offset == -1 || offset == 1,
              let siblings = visibleSiblings(of: target, in: binderItems),
              let index = siblings.firstIndex(of: target) else { return false }
        return siblings.indices.contains(index + offset)
    }

    public func moveContent(_ target: BinderContentTarget, offset: Int) throws {
        guard canReorderBinder else { throw ContentManagementError.filteredMovement }
        guard offset == -1 || offset == 1,
              let siblings = visibleSiblings(of: target, in: binderItems),
              let index = siblings.firstIndex(of: target),
              siblings.indices.contains(index + offset) else {
            throw ContentManagementError.movementBoundary
        }
        try moveContent(target, relativeTo: siblings[index + offset], position: offset < 0 ? .before : .after)
    }

    public func moveContent(
        _ target: BinderContentTarget,
        relativeTo other: BinderContentTarget,
        position requestedPosition: DropPosition
    ) throws {
        guard canReorderBinder else { throw ContentManagementError.filteredMovement }
        let source = try managedContent(target)
        let destination = try managedContent(other)
        guard source.target != destination.target else { throw WorkspaceError.invalidMove }
        let position: DropPosition = {
            if requestedPosition == .inside, case .document(let document) = destination,
               document.kind != DocumentKind.folder.rawValue,
               document.kind != DocumentKind.draftFolder.rawValue, document.children.isEmpty {
                return .after
            }
            return requestedPosition
        }()

        if position != .inside, let category = rootCategory(of: destination) {
            if case .entity(let entity) = source, !category.contains(kind: entity.kind) {
                throw WorkspaceError.invalidStoryBibleMove
            }
            try performContentMutation {
                if case .document(let document) = source {
                    if document.parent != nil || storyBibleCategory(for: document) != category {
                        if case .document(let destinationDocument) = destination {
                            try relocateDocument(document.id, relativeTo: destinationDocument.id, position: position)
                        } else {
                            try relocateDocument(document.id, toStoryBibleCategory: category)
                        }
                    }
                    document.sectionTypeIdentifier = "storyBible.\(category.id)"
                }
                var ordered = categoryContents(category, project: source.project)
                    .filter { $0.target != source.target }
                guard let destinationIndex = ordered.firstIndex(where: { $0.target == destination.target }) else {
                    throw ContentManagementError.unavailableTarget
                }
                ordered.insert(source, at: destinationIndex + (position == .after ? 1 : 0))
                for (index, content) in ordered.enumerated() {
                    content.setOrder(Int64(index))
                }
                source.project.modifiedAt = Date()
            }
        } else {
            guard case .document(let document) = source,
                  case .document(let destinationDocument) = destination else {
                throw WorkspaceError.invalidStoryBibleMove
            }
            try performContentMutation {
                try relocateDocument(document.id, relativeTo: destinationDocument.id, position: position)
            }
        }
    }

    public func moveContent(
        _ target: BinderContentTarget,
        toStoryBibleCategory category: StoryBibleCategory
    ) throws {
        guard canReorderBinder else { throw ContentManagementError.filteredMovement }
        let content = try managedContent(target)
        switch content {
        case .document(let document):
            try performContentMutation {
                try relocateDocument(document.id, toStoryBibleCategory: category)
            }
        case .entity(let entity):
            guard category.contains(kind: entity.kind) else { throw WorkspaceError.invalidStoryBibleMove }
            try performContentMutation {
                var ordered = categoryContents(category, project: entity.project)
                    .filter { $0.target != content.target }
                ordered.append(content)
                for (index, item) in ordered.enumerated() { item.setOrder(Int64(index)) }
                entity.project.modifiedAt = Date()
            }
        }
    }

    func orderedStoryBibleItems(_ items: [BinderItem]) -> [BinderItem] {
        items.enumerated().sorted { left, right in
            switch (left.element.storyBibleOrderIndex, right.element.storyBibleOrderIndex) {
            case (.some(let lhs), .some(let rhs)):
                lhs == rhs ? left.element.id < right.element.id : lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): left.offset < right.offset
            }
        }.map(\.element)
    }

    func appendStoryBibleOrder(
        for target: BinderContentTarget,
        in category: StoryBibleCategory,
        project: WritingProject
    ) {
        let contents = categoryContents(category, project: project)
        guard let content = contents.first(where: { $0.target == target }) else { return }
        let others = contents.filter { $0.target != target }
        if others.contains(where: { $0.order != nil }) {
            for (index, item) in others.enumerated() { item.setOrder(Int64(index)) }
            content.setOrder(Int64(others.count))
        } else {
            content.setOrder(nil)
        }
    }

    func performContentMutation(_ mutation: () throws -> Void) throws {
        // Preserve pending edits before establishing a rollback boundary for this operation.
        try flushPendingContentChanges()
        let oldSelection = selection
        let oldLabelFilter = labelFilter
        let oldStatusFilter = statusFilter
        do {
            try mutation()
            try store.save()
        } catch {
            store.context.rollback()
            selection = oldSelection
            labelFilter = oldLabelFilter
            statusFilter = oldStatusFilter
            refresh()
            throw error
        }
        refresh()
    }

    private func managedContent(
        _ target: BinderContentTarget,
        allowsTrashed: Bool = false
    ) throws -> ManagedContent {
        switch target {
        case .document(let id):
            guard let project = selectedProject,
                  let document = documents(in: project).first(where: { $0.id == id }) else {
                throw WorkspaceError.missingDocument(id)
            }
            guard !document.isDeleted, document.project.id == selectedProjectID,
                  allowsTrashed || !isDocumentTrashed(document) else {
                throw ContentManagementError.unavailableTarget
            }
            return .document(document)
        case .semanticEntity(let id):
            guard let entity = try store.fetchAcrossStores(SemanticEntity.self, id: id) else {
                throw ContentManagementError.unavailableTarget
            }
            guard !entity.isDeleted, entity.project.id == selectedProjectID else {
                throw ContentManagementError.unavailableTarget
            }
            if let document = entity.characterProfile?.sourceDocument {
                return try managedContent(.document(document.id), allowsTrashed: allowsTrashed)
            }
            return .entity(entity)
        }
    }

    private func rootCategory(of content: ManagedContent) -> StoryBibleCategory? {
        switch content {
        case .document(let document):
            return document.parent == nil ? storyBibleCategory(for: document) : nil
        case .entity(let entity):
            return StoryBibleCategory.allCases.first { $0.contains(kind: entity.kind) }
        }
    }

    private func categoryContents(_ category: StoryBibleCategory, project: WritingProject) -> [ManagedContent] {
        let entities = project.semanticEntities.filter {
            !$0.isDeleted && $0.characterProfile?.sourceDocument == nil && category.contains(kind: $0.kind)
        }.sorted {
            let result = $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName)
            return result == .orderedSame ? $0.id.uuidString < $1.id.uuidString : result == .orderedAscending
        }.map { ManagedContent.entity($0) }
        let documents = project.documents.filter {
            !$0.isDeleted && !isDocumentTrashed($0) && $0.parent == nil && storyBibleCategory(for: $0) == category
        }.sorted {
            ($0.orderIndex, $0.id.uuidString) < ($1.orderIndex, $1.id.uuidString)
        }.map { ManagedContent.document($0) }
        return (entities + documents).enumerated().sorted { left, right in
            switch (left.element.order, right.element.order) {
            case (.some(let lhs), .some(let rhs)):
                lhs == rhs ? left.element.target.id.uuidString < right.element.target.id.uuidString : lhs < rhs
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): left.offset < right.offset
            }
        }.map(\.element)
    }

    private func visibleSiblings(
        of target: BinderContentTarget,
        in items: [BinderItem]
    ) -> [BinderContentTarget]? {
        if items.contains(where: { $0.contentTarget == target && !$0.isTrashed }) {
            return items.filter { !$0.isTrashed }.compactMap(\.contentTarget)
        }
        for item in items {
            if let siblings = visibleSiblings(of: target, in: item.children ?? []) { return siblings }
        }
        return nil
    }
}
