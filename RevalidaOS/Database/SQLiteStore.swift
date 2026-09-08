import Foundation
import SQLite3

final class SQLiteStore {
    private var db: OpaquePointer?
    private let dbURL: URL

    init() throws {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("RevalidaOS", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        dbURL = folder.appendingPathComponent("revalida.sqlite3")
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw SQLiteError.message(lastError())
        }
        try execute("PRAGMA foreign_keys = ON;")
        _ = try query("PRAGMA journal_mode = WAL;")
    }

    deinit { sqlite3_close(db) }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SQLiteError.message(lastError()) }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteError.message(lastError()) }
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw SQLiteError.message(lastError()) }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[String: SQLiteValue]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: SQLiteValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = .int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: row[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT: row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_NULL: row[name] = .null
                default:
                    if let bytes = sqlite3_column_blob(statement, index) {
                        let count = Int(sqlite3_column_bytes(statement, index))
                        row[name] = .blob(Data(bytes: bytes, count: count))
                    } else { row[name] = .null }
                }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction(_ block: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do { try block(); try execute("COMMIT;") }
        catch { try? execute("ROLLBACK;"); throw error }
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let idx = Int32(offset + 1)
            let result: Int32
            switch value {
            case .int(let v): result = sqlite3_bind_int64(statement, idx, v)
            case .double(let v): result = sqlite3_bind_double(statement, idx, v)
            case .text(let v): result = v.withCString { sqlite3_bind_text(statement, idx, $0, -1, SQLITE_TRANSIENT) }
            case .blob(let data): result = data.withUnsafeBytes { ptr in sqlite3_bind_blob(statement, idx, ptr.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            case .null: result = sqlite3_bind_null(statement, idx)
            }
            if result != SQLITE_OK { throw SQLiteError.message(lastError()) }
        }
    }

    private func lastError() -> String {
        guard let db, let message = sqlite3_errmsg(db) else { return "Erro desconhecido do SQLite" }
        return String(cString: message)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteValue {
    case int(Int64), double(Double), text(String), blob(Data), null
    var string: String? { if case .text(let v) = self { return v }; return nil }
    var int: Int64? { if case .int(let v) = self { return v }; return nil }
    var double: Double? { if case .double(let v) = self { return v }; return nil }
}

enum SQLiteError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return "Erro do banco" }
}
