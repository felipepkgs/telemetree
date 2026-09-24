import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

/// PostgreSQL implementation of the database abstraction, built on
/// PostgresNIO. Unlike MySQL, Postgres has no session-level `USE` — a
/// connection is bound to one database for its whole lifetime, so
/// `listTables`/`listColumns` ignore the `database` parameter and just
/// query the connected database's `public` schema. Switching databases
/// means opening a new connection with a different profile, not
/// something this driver tries to paper over.
final class PostgresDriver: DatabaseDriver {
    func connect(profile: ConnectionProfile, password: String) async throws -> any DatabaseConnection {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let tls: PostgresConnection.Configuration.TLS = profile.useSSL
                ? .require(try NIOSSLContext(configuration: .makeClientConfiguration()))
                : .disable
            let configuration = PostgresConnection.Configuration(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: password.isEmpty ? nil : password,
                database: profile.database.isEmpty ? nil : profile.database,
                tls: tls
            )
            let connection = try await PostgresConnection.connect(
                configuration: configuration,
                id: 1,
                logger: Logger(label: "com.telemetree.app.postgres")
            )
            return PostgresDatabaseConnection(connection: connection, eventLoopGroup: group)
        } catch {
            try? await group.shutdownGracefully()
            throw DatabaseError.connectionFailed(FriendlyError.message(for: error))
        }
    }
}

final class PostgresDatabaseConnection: DatabaseConnection {
    private let connection: PostgresConnection
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let logger = Logger(label: "com.telemetree.app.postgres")

    init(connection: PostgresConnection, eventLoopGroup: MultiThreadedEventLoopGroup) {
        self.connection = connection
        self.eventLoopGroup = eventLoopGroup
    }

    func execute(sql: String) async throws -> QueryResult {
        do {
            let result = try await connection.query(sql).get()
            guard let firstRow = result.rows.first else {
                return QueryResult(columns: [], rows: [], affectedRows: result.metadata.rows ?? 0)
            }
            let columns = firstRow.map { $0.columnName }
            let resultRows: [[QueryValue]] = result.rows.map { row in
                row.map(Self.value(for:))
            }
            return QueryResult(columns: columns, rows: resultRows, affectedRows: result.rows.count)
        } catch let error as DatabaseError {
            throw error
        } catch {
            let friendly = FriendlyError.message(for: error)
            if FriendlyError.isConnectionLost(error) {
                throw DatabaseError.connectionLost(friendly)
            }
            throw DatabaseError.queryFailed(friendly)
        }
    }

    /// Postgres cells arrive typed (int4, timestamptz, uuid, ...), not as
    /// plain text like MySQL's simple-query protocol — `PostgresData` (the
    /// library's older, loosely-typed struct) already knows how to render
    /// the common types to a display string, so this reuses that instead
    /// of hand-rolling per-type formatting.
    private static func value(for cell: PostgresCell) -> QueryValue {
        guard let bytes = cell.bytes else { return .null }
        let data = PostgresData(type: cell.dataType, formatCode: cell.format, value: bytes)
        if let string = data.string { return .text(string) }
        if let bool = data.bool { return .text(bool ? "true" : "false") }
        return .text("<\(cell.dataType) not displayable>")
    }

    func listDatabases() async throws -> [String] {
        let result = try await execute(sql: "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname")
        return result.rows.compactMap { $0.first?.displayString }
    }

    func listTables(inDatabase database: String) async throws -> [DatabaseTable] {
        let result = try await execute(sql: "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")
        return result.rows.compactMap { $0.first.map { DatabaseTable(name: $0.displayString) } }
    }

    func listColumns(table: String, inDatabase database: String) async throws -> [String] {
        // `table` lands inside a string literal, not as an identifier —
        // needs SQL string-literal escaping (doubled '), not
        // DatabaseEngine.quoteIdentifier (that's for identifier position,
        // a different escaping rule). A table with an apostrophe in its
        // name would otherwise break this query outright.
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let result = try await execute(sql: """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = '\(escapedTable)'
            ORDER BY ordinal_position
            """)
        return result.rows.compactMap { $0.first?.displayString }
    }

    func primaryKeyColumns(table: String, inDatabase database: String) async throws -> [String] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let result = try await execute(sql: """
            SELECT kcu.column_name FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'public' AND tc.table_name = '\(escapedTable)'
            ORDER BY kcu.ordinal_position
            """)
        return result.rows.compactMap { $0.first?.displayString }
    }

    func foreignKeys(table: String, inDatabase database: String) async throws -> [ForeignKeyReference] {
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let result = try await execute(sql: """
            SELECT kcu.column_name, ccu.table_name AS referenced_table, ccu.column_name AS referenced_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
              ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public' AND tc.table_name = '\(escapedTable)'
            """)
        return result.rows.compactMap { row in
            guard row.count >= 3 else { return nil }
            return ForeignKeyReference(column: row[0].displayString, referencedTable: row[1].displayString, referencedColumn: row[2].displayString)
        }
    }

    func activeSessions() async throws -> QueryResult {
        try await execute(sql: """
            SELECT pid, usename, client_addr, datname, state, query, query_start
            FROM pg_stat_activity
            ORDER BY query_start DESC NULLS LAST
            """)
    }

    func close() async {
        try? await connection.close()
        try? await eventLoopGroup.shutdownGracefully()
    }
}
