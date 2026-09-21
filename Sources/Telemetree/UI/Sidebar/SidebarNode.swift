import Foundation

/// A row in the sidebar outline view. Reference type on purpose: NSOutlineView
/// tracks expansion state by item identity, so the same node instance must be
/// reused across reloads.
final class SidebarNode {
    enum Kind {
        case sectionHeader(String)
        case connection(ConnectionProfile)
        case database(ConnectionProfile, name: String)
        case table(ConnectionProfile, database: String, table: DatabaseTable)
        case queryFolder(QueryFolder)
        case queryDocument(QueryDocument)
        case placeholder(String)
    }

    var kind: Kind
    var children: [SidebarNode]?
    var childrenLoaded = false

    init(kind: Kind, children: [SidebarNode]? = nil) {
        self.kind = kind
        self.children = children
    }

    /// Non-nil for kinds that should keep the same node instance across a
    /// tree rebuild (preserves expansion/selection); nil for kinds that are
    /// fine to recreate each time.
    var identityKey: String? {
        switch kind {
        case .connection(let profile): return "conn:\(profile.id)"
        case .queryFolder(let folder): return "folder:\(folder.id)"
        case .queryDocument(let document): return "doc:\(document.id)"
        default: return nil
        }
    }

    var title: String {
        switch kind {
        case .sectionHeader(let text): return text
        case .connection(let profile): return profile.name
        case .database(_, let name): return name
        case .table(_, _, let table): return table.name
        case .queryFolder(let folder): return folder.name
        case .queryDocument(let document): return document.name
        case .placeholder(let text): return text
        }
    }

    var isExpandable: Bool {
        switch kind {
        case .sectionHeader, .connection, .database, .queryFolder: return true
        case .table, .queryDocument, .placeholder: return false
        }
    }

    var isGroupHeader: Bool {
        if case .sectionHeader = kind { return true }
        return false
    }
}
