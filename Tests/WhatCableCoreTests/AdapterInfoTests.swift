import XCTest
@testable import WhatCableCore

/// Unit tests for AdapterInfo and AdapterHVCEntry.
final class AdapterInfoTests: XCTestCase {

    // MARK: - AdapterHVCEntry

    func testHVCEntryWatts() {
        let entry = AdapterHVCEntry(voltageMV: 20000, currentMA: 5000)
        XCTAssertEqual(entry.wattsInt, 100)
    }

    func testHVCEntryWattsRounding() {
        // 4990 mA * 20000 mV = 99.8W, rounds to 100
        let entry = AdapterHVCEntry(voltageMV: 20000, currentMA: 4990)
        XCTAssertEqual(entry.wattsInt, 100)
    }

    func testHVCEntryLabel() {
        let entry = AdapterHVCEntry(voltageMV: 20000, currentMA: 4990)
        XCTAssertEqual(entry.label, "20V/4.99A")
    }

    func testHVCEntryLabelLowVoltage() {
        let entry = AdapterHVCEntry(voltageMV: 5000, currentMA: 2960)
        XCTAssertEqual(entry.label, "5V/2.96A")
    }

    func testHVCEntryEquatable() {
        let a = AdapterHVCEntry(voltageMV: 9000, currentMA: 3000)
        let b = AdapterHVCEntry(voltageMV: 9000, currentMA: 3000)
        XCTAssertEqual(a, b)
    }

    func testHVCEntryHashable() {
        let a = AdapterHVCEntry(voltageMV: 5000, currentMA: 3000)
        let b = AdapterHVCEntry(voltageMV: 20000, currentMA: 5000)
        let set: Set<AdapterHVCEntry> = [a, b, a]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - AdapterInfo backward compatibility

    func testMinimalInitStillWorks() {
        // Existing callers pass only (watts, isCharging, source).
        // New fields should all default to nil / empty.
        let info = AdapterInfo(watts: 100, isCharging: true, source: "AC")
        XCTAssertEqual(info.watts, 100)
        XCTAssertEqual(info.isCharging, true)
        XCTAssertEqual(info.source, "AC")
        XCTAssertNil(info.voltageMV)
        XCTAssertNil(info.currentMA)
        XCTAssertNil(info.adapterDescription)
        XCTAssertNil(info.powerTier)
        XCTAssertNil(info.isWireless)
        XCTAssertTrue(info.hvcMenu.isEmpty)
    }

    func testFullInit() {
        let menu = [
            AdapterHVCEntry(voltageMV: 5000, currentMA: 2960),
            AdapterHVCEntry(voltageMV: 9000, currentMA: 2980),
            AdapterHVCEntry(voltageMV: 15000, currentMA: 2990),
            AdapterHVCEntry(voltageMV: 20000, currentMA: 4990),
        ]
        let info = AdapterInfo(
            watts: 100,
            isCharging: nil,
            source: "AC",
            voltageMV: 20000,
            currentMA: 4990,
            adapterDescription: "pd charger",
            powerTier: 2,
            isWireless: false,
            hvcMenu: menu
        )
        XCTAssertEqual(info.watts, 100)
        XCTAssertEqual(info.voltageMV, 20000)
        XCTAssertEqual(info.currentMA, 4990)
        XCTAssertEqual(info.adapterDescription, "pd charger")
        XCTAssertEqual(info.powerTier, 2)
        XCTAssertEqual(info.isWireless, false)
        XCTAssertEqual(info.hvcMenu.count, 4)
        XCTAssertEqual(info.hvcMenu.last?.wattsInt, 100)
    }

    func testEquatableWithHVCMenu() {
        let menu = [AdapterHVCEntry(voltageMV: 20000, currentMA: 5000)]
        let a = AdapterInfo(watts: 100, isCharging: nil, source: "AC", hvcMenu: menu)
        let b = AdapterInfo(watts: 100, isCharging: nil, source: "AC", hvcMenu: menu)
        XCTAssertEqual(a, b)
    }

    func testNotEqualWhenHVCMenuDiffers() {
        let a = AdapterInfo(watts: 100, isCharging: nil, source: "AC",
                            hvcMenu: [AdapterHVCEntry(voltageMV: 20000, currentMA: 5000)])
        let b = AdapterInfo(watts: 100, isCharging: nil, source: "AC",
                            hvcMenu: [AdapterHVCEntry(voltageMV: 20000, currentMA: 3000)])
        XCTAssertNotEqual(a, b)
    }

    func testNilAdapterAllFieldsNil() {
        let info = AdapterInfo(watts: nil, isCharging: nil, source: nil)
        XCTAssertNil(info.watts)
        XCTAssertNil(info.source)
        XCTAssertTrue(info.hvcMenu.isEmpty)
    }
}
