#!/usr/bin/env swift

// Build the bundled SQLite database from vendor and cable sources.
//
// Reads:
//   - Sources/WhatCableCore/Resources/usbif-vendors.tsv (USB-IF vendor list)
//   - https://usb-ids.gowdy.us/usb.ids (community vendor list, fetched live)
//
// Writes:
//   - Sources/WhatCableCore/Resources/whatcable.db (bundled in the app)
//   - docs/whatcable.db (served on the website)
//
// Run from the repo root:
//   swift scripts/build-cable-db.swift
//
// Requires: macOS (uses system SQLite3 via libsqlite3).

import Foundation
import SQLite3

// MARK: - Paths

let repoRoot = FileManager.default.currentDirectoryPath
let vendorTSV = "\(repoRoot)/Sources/WhatCableCore/Resources/usbif-vendors.tsv"
let dbOutput = "\(repoRoot)/Sources/WhatCableCore/Resources/whatcable.db"
let dbWebCopy = "\(repoRoot)/docs/whatcable.db"

// MARK: - SQLite helpers

var db: OpaquePointer?

func openDB() {
    // Remove existing DB so we always start fresh.
    try? FileManager.default.removeItem(atPath: dbOutput)

    let rc = sqlite3_open(dbOutput, &db)
    guard rc == SQLITE_OK else {
        fputs("error: sqlite3_open failed: \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        exit(1)
    }
    // WAL mode and synchronous=OFF for build-time speed (we're writing
    // once and the file is read-only at runtime).
    runSQL("PRAGMA journal_mode = WAL")
    runSQL("PRAGMA synchronous = OFF")
}

func runSQL(_ sql: String) {
    var err: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &err)
    if rc != SQLITE_OK {
        let msg = err.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(err)
        fputs("error: SQL failed: \(msg)\n  statement: \(sql)\n", stderr)
        exit(2)
    }
}

func closeDB() {
    // Checkpoint WAL into the main db file and remove sidecars.
    runSQL("PRAGMA wal_checkpoint(TRUNCATE)")
    sqlite3_close(db)
    db = nil
    try? FileManager.default.removeItem(atPath: dbOutput + "-shm")
    try? FileManager.default.removeItem(atPath: dbOutput + "-wal")
}

// MARK: - Schema

func createSchema() {
    runSQL("""
        CREATE TABLE vendors (
            vid    INTEGER PRIMARY KEY,
            name   TEXT NOT NULL,
            source TEXT NOT NULL CHECK(source IN ('usbif', 'usbids', 'manual'))
        )
        """)

    runSQL("""
        CREATE TABLE cables (
            vid       INTEGER NOT NULL,
            pid       INTEGER NOT NULL,
            cable_vdo INTEGER NOT NULL DEFAULT 0,
            brand     TEXT NOT NULL,
            speed     TEXT NOT NULL DEFAULT '',
            power     TEXT NOT NULL DEFAULT '',
            type      TEXT NOT NULL DEFAULT 'passive',
            xid       TEXT NOT NULL DEFAULT 'none',
            issue_url TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (vid, pid, cable_vdo)
        )
        """)
}

// MARK: - USB-IF vendor import

func importUSBIFVendors() -> Int {
    guard let text = try? String(contentsOfFile: vendorTSV, encoding: .utf8) else {
        fputs("error: could not read \(vendorTSV)\n", stderr)
        exit(3)
    }

    let insertSQL = "INSERT INTO vendors (vid, name, source) VALUES (?, ?, 'usbif')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("error: prepare failed for vendor insert\n", stderr)
        exit(4)
    }

    runSQL("BEGIN TRANSACTION")
    var count = 0

    for line in text.components(separatedBy: "\n") {
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2, let vid = Int(parts[0]) else { continue }
        let name = parts[1].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(vid))
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            fputs("warn: failed to insert VID \(vid): \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        }
        count += 1
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return count
}

// MARK: - usb.ids community vendor import

let usbidsURL = URL(string: "https://usb-ids.gowdy.us/usb.ids")!

func fetchUSBIDs() -> String? {
    do {
        let data = try Data(contentsOf: usbidsURL)
        // The file is mostly UTF-8 but contains a few invalid bytes.
        // Fall back to Latin-1 (which always succeeds) if strict UTF-8 fails.
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    } catch {
        fputs("warn: usb.ids fetch failed: \(error)\n", stderr)
        return nil
    }
}

func importUSBIDsVendors() -> (inserted: Int, skipped: Int) {
    guard let text = fetchUSBIDs() else {
        fputs("warn: skipping usb.ids (fetch failed)\n", stderr)
        return (0, 0)
    }

    // INSERT OR IGNORE: USB-IF entries take priority (already loaded).
    let insertSQL = "INSERT OR IGNORE INTO vendors (vid, name, source) VALUES (?, ?, 'usbids')"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
        fputs("warn: prepare failed for usb.ids insert\n", stderr)
        return (0, 0)
    }

    runSQL("BEGIN TRANSACTION")
    var inserted = 0
    var skipped = 0

    // Format: lines starting with 4 hex digits + 2 spaces + name are
    // vendor entries. Lines with leading tabs are device/interface
    // entries (ignored). The vendor section ends at "C xx  class_name".
    let re = try! NSRegularExpression(pattern: "^([0-9a-fA-F]{4})  (.+)$")

    for line in text.components(separatedBy: "\n") {
        // Stop at the device class section.
        if line.hasPrefix("C ") { break }
        if line.hasPrefix("#") || line.hasPrefix("\t") || line.isEmpty { continue }

        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              m.numberOfRanges >= 3,
              let vidRange = Range(m.range(at: 1), in: line),
              let nameRange = Range(m.range(at: 2), in: line) else { continue }

        guard let vid = Int(String(line[vidRange]), radix: 16) else { continue }
        let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { continue }

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, Int32(vid))
        sqlite3_bind_text(stmt, 2, (name as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE {
            // sqlite3_changes returns 0 for INSERT OR IGNORE when the
            // row already existed.
            if sqlite3_changes(db) > 0 {
                inserted += 1
            } else {
                skipped += 1
            }
        } else {
            skipped += 1
        }
    }

    runSQL("COMMIT")
    sqlite3_finalize(stmt)
    return (inserted, skipped)
}

// MARK: - Main

openDB()
createSchema()

let vendorCount = importUSBIFVendors()
print("Imported \(vendorCount) USB-IF vendors")

let usbids = importUSBIDsVendors()
print("usb.ids: \(usbids.inserted) new vendors added, \(usbids.skipped) already in USB-IF list")

// Copy to docs/ for the website.
closeDB()

do {
    let fm = FileManager.default
    if fm.fileExists(atPath: dbWebCopy) {
        try fm.removeItem(atPath: dbWebCopy)
    }
    try fm.copyItem(atPath: dbOutput, toPath: dbWebCopy)
    print("Copied to \(dbWebCopy)")
} catch {
    fputs("warn: could not copy to docs/: \(error)\n", stderr)
}

print("Done: \(dbOutput)")
