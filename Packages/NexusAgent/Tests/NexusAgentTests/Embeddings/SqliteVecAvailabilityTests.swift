import CSqliteVec
import Foundation
import SQLite3
import Testing

@Suite struct SqliteVecAvailabilityTests {
    @Test func sqliteVecLoadsIntoInMemoryDatabase() throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer {
            if db != nil {
                sqlite3_close(db)
            }
        }

        var errMsg: UnsafeMutablePointer<Int8>?
        let initRC = sqlite3_vec_init(db, &errMsg, nil)
        #expect(
            initRC == SQLITE_OK,
            "sqlite-vec init failed: \(errMsg.map { String(cString: $0) } ?? "nil")"
        )
        if errMsg != nil {
            sqlite3_free(errMsg)
        }

        let createSQL = "CREATE VIRTUAL TABLE v USING vec0(vector float[4]);"
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, createSQL, -1, &stmt, nil) == SQLITE_OK)
        if let stmt {
            defer { sqlite3_finalize(stmt) }
            #expect(sqlite3_step(stmt) == SQLITE_DONE)
        }
    }
}
