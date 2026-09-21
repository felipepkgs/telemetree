import Foundation

/// A row in the sidebar outline view. Reference type on purpose: NSOutlineView
/// tracks expansion state by item identity, so the same node instance must be
/// reused across reloads.
final class SidebarNode {
    enum Kind {
        case connection(ConnectionProfile)
        case database(ConnectionProfile, name: String)
        case table(ConnectionProfile, database: String, table: DatabaseTable)
        case placeholder(String)
    }

    let kind: Kind
    var children: [SidebarNode]?
    var childrenLoaded = false

    init(kind: Kind, children: [SidebarNode]? = nil) {
        self.kind = kind
        self.children = children
    }

    var title: String {
        switch kind {
        case .connection(let profile): return profile.name
        case .database(_, let name): return name
        case .table(_, _, let table): return table.name
        case .placeholder(let text): return text
        }
    }

    var isExpandable: Bool {
        switch kind {
        case .connection, .database: return true
        case .table, .placeholder: return false
        }
    }
}
