import XCTest
@testable import WhatCableCore

/// Tests for the bundled SQLite vendor database. Most user-facing behaviour
/// is covered by VendorDBTests via the curated-then-bundled fallback chain;
/// these tests pin properties of the bundled data itself.
final class CableDBTests: XCTestCase {

    func testLoadsManyEntries() {
        // The bundled DB from USB-IF's March 2026 list has ~13,000
        // vendors. If the resource fails to load (e.g. SPM resource
        // wiring breaks) the count would be 0; pin a generous lower
        // bound so future refreshes that grow the list don't fail
        // this test, but a regression to "nothing loaded" would.
        XCTAssertGreaterThan(CableDB.vendorCount, 10_000)
    }

    func testKnownVIDResolves() {
        XCTAssertEqual(CableDB.vendorName(vid: 0x05AC), "Apple")
    }

    func testZeroVIDReturnsName() {
        // VID 0 is "USB Implementers Forum" in the USB-IF list. CableDB
        // returns the raw name; VendorDB filters it for display purposes.
        XCTAssertNotNil(CableDB.vendorName(vid: 0))
    }

    func testZeroVIDIsUSBIFRegistered() {
        XCTAssertTrue(CableDB.isUSBIFRegistered(0))
    }

    func testUnregisteredVIDReturnsNil() {
        // 0xDEAD (decimal 57005) is not a USB-IF assignment.
        XCTAssertNil(CableDB.vendorName(vid: 0xDEAD))
        XCTAssertFalse(CableDB.isUSBIFRegistered(0xDEAD))
    }

    func testUSBIFSourceTracking() {
        // Apple should be sourced from USB-IF.
        XCTAssertTrue(CableDB.isUSBIFRegistered(0x05AC))
    }

    func testNoControlCharactersInBundledNames() {
        // pdftotext emits form-feed (\u{000C}) at the start of each
        // page, which can land glued onto vendor names if the parser
        // doesn't strip control chars. Pin specific entries that were
        // affected before the parser fix (page-boundary vendors per
        // USB-IF March 2026), and a generic "vendor names contain no
        // ASCII control characters" check on a couple more.
        XCTAssertEqual(VendorDB.name(for: 1011), "Adaptec, Inc.")
        XCTAssertEqual(VendorDB.name(for: 1069), "Micronics")
        XCTAssertEqual(VendorDB.name(for: 1196), "Micro Audiometrics Corp.")
        for vid in [1011, 1069, 1196, 1222, 1480] {
            let name = VendorDB.name(for: vid) ?? ""
            for scalar in name.unicodeScalars {
                XCTAssertFalse(
                    scalar.value < 0x20 || scalar.value == 0x7F,
                    "vendor name for \(String(format: "0x%04X", vid)) contains control char U+\(String(scalar.value, radix: 16))"
                )
            }
        }
    }

    func testCableEmarkerChipVendorsAllResolve() {
        // The six chip vendors observed in real cable reports.
        XCTAssertNotNil(CableDB.vendorName(vid: 0x20C2)) // Sumitomo
        XCTAssertNotNil(CableDB.vendorName(vid: 0x315C)) // Convenientpower
        XCTAssertNotNil(CableDB.vendorName(vid: 0x2095)) // CE LINK
        XCTAssertNotNil(CableDB.vendorName(vid: 0x2E99)) // Hynetek
        XCTAssertNotNil(CableDB.vendorName(vid: 0x201C)) // Freeport
        XCTAssertNotNil(CableDB.vendorName(vid: 0x2B1D)) // Lintes
    }

    func testUSBIDsVendorResolvesName() {
        // VID 0x6666 ("Prototype product Vendor ID") is in the community
        // usb.ids list but not in USB-IF's official registry.
        XCTAssertNotNil(CableDB.vendorName(vid: 0x6666))
    }

    func testUSBIDsVendorNotUSBIFRegistered() {
        // Critical invariant: usb.ids entries resolve names for display
        // but must NOT suppress the vidNotInUSBIFList trust flag.
        XCTAssertFalse(CableDB.isUSBIFRegistered(0x6666))
    }

    func testCuratedCableNotFoundForUnknown() {
        XCTAssertNil(CableDB.curatedCable(vid: 0xDEAD, pid: 0xBEEF, cableVDO: 0))
    }
}
