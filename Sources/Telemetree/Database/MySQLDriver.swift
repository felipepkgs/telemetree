import Foundation
import MySQLNIO
import NIOCore
import NIOPosix

/// MySQL implementation of the database abstraction, built on MySQLNIO.
final class MySQLDriver: DatabaseDriver {
    func connect(profile: ConnectionProfile, password: String) async throws -> any DatabaseConnection {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let address = try SocketAddress.makeAddressResolvingHost(profile.host, port: profile.port)
            let connection = try await MySQLConnection.connect(
                to: address,
                username: profile.username,
                database: profile.database,
                password: password,
                tlsConfiguration: profile.useSSL ? .makeClientConfiguration() : nil,
                on: group.next()
            ).get()
            return MySQLDatabaseConnection(connection: connection, eventLoopGroup: group)
        } catch {
            try? await group.shutdownGracefully()
            throw DatabaseError.connectionFailed(FriendlyError.message(for: error))
        }
    }
}

final class MySQLDatabaseConnection: DatabaseConnection {
    private let connection: MySQLConnection
    private let eventLoopGroup: MultiThreadedEventLoopGroup

    init(connection: MySQLConnection, eventLoopGroup: MultiThreadedEventLoopGroup) {
        self.connection = connection
        self.eventLoopGroup = eventLoopGroup
    }

    func execute(sql: String) async throws -> QueryResult {
        do {
            // Prepared-statement protocol (COM_STMT_PREPARE/EXECUTE), not
            // `simpleQuery`'s text protocol (COM_QUERY) — the latter never
            // surfaces DML's real affected-row count, only an OK_Packet
            // reachable through this API's `onMetadata` callback.
            nonisolated(unsafe) var metadata: MySQLQueryMetadata?
            let rows = try await connection.query(sql, onMetadata: { metadata = $0 }).get()
            guard let firstRow = rows.first else {
                return QueryResult(columns: [], rows: [], affectedRows: metadata.map { Int($0.affectedRows) } ?? 0)
            }
            let columns = firstRow.columnDefinitions.map(\.name)
            let resultRows: [[QueryValue]] = rows.map { row in
                zip(row.columnDefinitions, row.values).map { definition, value in
                    let data = MySQLData(
                        type: definition.columnType,
                        format: row.format,
                        buffer: value,
                        isUnsigned: definition.flags.contains(.COLUMN_UNSIGNED)
                    )
                    return data.string.map(QueryValue.text) ?? .null
                }
            }
            return QueryResult(columns: columns, rows: resultRows, affectedRows: rows.count)
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

    func listDatabases() async throws -> [String] {
        let result = try await execute(sql: "SHOW DATABASES")
        return result.rows.compactMap { $0.first?.displayString }
    }

    func listTables(inDatabase database: String) async throws -> [DatabaseTable] {
        let result = try await execute(sql: "SHOW TABLES FROM `\(database)`")
        return result.rows.compactMap { $0.first.map { DatabaseTable(name: $0.displayString) } }
    }

    func listColumns(table: String, inDatabase database: String) async throws -> [String] {
        let result = try await execute(sql: "SHOW COLUMNS FROM `\(database)`.`\(table)`")
        return result.rows.compactMap { $0.first?.displayString }
    }

    func close() async {
        try? await connection.close().get()
        try? await eventLoopGroup.shutdownGracefully()
    }
}
