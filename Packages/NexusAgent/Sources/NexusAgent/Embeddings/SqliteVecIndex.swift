import CSqliteVec
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SqliteVecHit: Equatable, Sendable {
    public let itemID: UUID
    public let distance: Double

    public init(itemID: UUID, distance: Double) {
        self.itemID = itemID
        self.distance = distance
    }
}

public enum SqliteVecIndexError: Error, Equatable, Sendable {
    case invalidDimension(Int)
    case invalidLimit(Int)
    case openFailed(Int32)
    case extensionInitFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case dimensionMismatch(expectedBytes: Int, actualBytes: Int)
}

/// Small sqlite-vec wrapper for the local per-device embedding index.
///
/// `sqlite3` handles are not independently thread-safe for concurrent statement use, so every public
/// operation is serialized through `lock`.
public final class SqliteVecIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dimension: Int
    private let lock = NSRecursiveLock()

    public static func inMemory(dimension: Int = NLEmbeddingClient.requiredDimension) throws -> SqliteVecIndex {
        try SqliteVecIndex(path: ":memory:", dimension: dimension)
    }

    public init(path: String, dimension: Int = NLEmbeddingClient.requiredDimension) throws {
        guard dimension > 0 else {
            throw SqliteVecIndexError.invalidDimension(dimension)
        }

        var handle: OpaquePointer?
        let openRC = sqlite3_open(path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw SqliteVecIndexError.openFailed(openRC)
        }

        self.db = handle
        self.dimension = dimension

        do {
            try initializeVecExtension()
            try runStatement("CREATE VIRTUAL TABLE IF NOT EXISTS embeddings USING vec0(id TEXT PRIMARY KEY, vector float[\(dimension)]);")
        } catch {
            sqlite3_close(handle)
            db = nil
            throw error
        }
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }

        if let db {
            sqlite3_close(db)
        }
    }

    public func upsert(id: UUID, vector: Data) throws {
        try validateVector(vector)

        try locked {
            try deleteUnlocked(id: id)

            let sql = "INSERT INTO embeddings (id, vector) VALUES (?, ?);"
            try withStatement(sql) { stmt in
                try bindText(id.uuidString, at: 1, in: stmt)
                try bindBlob(vector, at: 2, in: stmt)
                try stepDone(stmt)
            }
        }
    }

    public func delete(id: UUID) throws {
        try locked {
            try deleteUnlocked(id: id)
        }
    }

    public func search(query: Data, limit: Int) throws -> [SqliteVecHit] {
        try validateVector(query)
        guard limit > 0 else {
            throw SqliteVecIndexError.invalidLimit(limit)
        }

        return try locked {
            let sql = "SELECT id, distance FROM embeddings WHERE vector MATCH ? AND k = ? ORDER BY distance;"
            return try withStatement(sql) { stmt in
                try bindBlob(query, at: 1, in: stmt)
                try bindInt(limit, at: 2, in: stmt)

                var hits = [SqliteVecHit]()
                while true {
                    let stepRC = sqlite3_step(stmt)
                    if stepRC == SQLITE_ROW {
                        guard let idCString = sqlite3_column_text(stmt, 0) else {
                            continue
                        }
                        let idString = String(cString: idCString)
                        guard let id = UUID(uuidString: idString) else {
                            continue
                        }
                        hits.append(SqliteVecHit(itemID: id, distance: sqlite3_column_double(stmt, 1)))
                    } else if stepRC == SQLITE_DONE {
                        return hits
                    } else {
                        throw SqliteVecIndexError.stepFailed(errorMessage)
                    }
                }
            }
        }
    }

    private func initializeVecExtension() throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        let initRC = sqlite3_vec_init(db, &errMsg, nil)
        defer {
            if errMsg != nil {
                sqlite3_free(errMsg)
            }
        }

        guard initRC == SQLITE_OK else {
            throw SqliteVecIndexError.extensionInitFailed(errMsg.map { String(cString: $0) } ?? "unknown")
        }
    }

    private func validateVector(_ vector: Data) throws {
        let expectedBytes = dimension * MemoryLayout<Float>.size
        guard vector.count == expectedBytes else {
            throw SqliteVecIndexError.dimensionMismatch(expectedBytes: expectedBytes, actualBytes: vector.count)
        }
    }

    private func runStatement(_ sql: String) throws {
        try locked {
            try withStatement(sql) { stmt in
                try stepDone(stmt)
            }
        }
    }

    private func deleteUnlocked(id: UUID) throws {
        let sql = "DELETE FROM embeddings WHERE id = ?;"
        try withStatement(sql) { stmt in
            try bindText(id.uuidString, at: 1, in: stmt)
            try stepDone(stmt)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepRC == SQLITE_OK, let stmt else {
            throw SqliteVecIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        return try body(stmt)
    }

    private func bindText(_ text: String, at index: Int32, in stmt: OpaquePointer) throws {
        let bindRC = sqlite3_bind_text(stmt, index, text, -1, sqliteTransient)
        guard bindRC == SQLITE_OK else {
            throw SqliteVecIndexError.bindFailed(errorMessage)
        }
    }

    private func bindBlob(_ data: Data, at index: Int32, in stmt: OpaquePointer) throws {
        let bindRC = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, index, rawBuffer.baseAddress, Int32(data.count), sqliteTransient)
        }
        guard bindRC == SQLITE_OK else {
            throw SqliteVecIndexError.bindFailed(errorMessage)
        }
    }

    private func bindInt(_ value: Int, at index: Int32, in stmt: OpaquePointer) throws {
        let bindRC = sqlite3_bind_int(stmt, index, Int32(value))
        guard bindRC == SQLITE_OK else {
            throw SqliteVecIndexError.bindFailed(errorMessage)
        }
    }

    private func stepDone(_ stmt: OpaquePointer) throws {
        let stepRC = sqlite3_step(stmt)
        guard stepRC == SQLITE_DONE else {
            throw SqliteVecIndexError.stepFailed(errorMessage)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        return try body()
    }

    private var errorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }
}
