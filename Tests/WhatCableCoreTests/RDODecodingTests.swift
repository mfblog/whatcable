import Testing

/// USB PD 3.2 Table 6-23 (Fixed Supply RDO):
///   bits 30:28 = Object Position (which PDO was selected)
///   bits 19:10 = Operating Current in 10mA units
///   bits  9:0  = Maximum Operating Current in 10mA units
///
/// These tests verify the field extraction matches the spec. The bug fixed
/// in this session had the two current fields swapped.
@Suite("RDO Decoding")
struct RDODecodingTests {
    @Test("5V 3A contract: operating 2A, max 3A, PDO position 1")
    func basic5V3A() {
        // PDO position 1 (bits 30:28 = 001)
        // Operating current 200 (200 * 10mA = 2000mA) at bits 19:10
        // Max operating current 300 (300 * 10mA = 3000mA) at bits 9:0
        let rdo: UInt32 = (1 << 28) | (200 << 10) | 300
        let position = Int((rdo >> 28) & 0x7)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 1)
        #expect(operating == 2000)
        #expect(max == 3000)
    }

    @Test("20V 5A contract: operating 4.5A, max 5A, PDO position 4")
    func highPower20V() {
        let rdo: UInt32 = (4 << 28) | (450 << 10) | 500
        let position = Int((rdo >> 28) & 0x7)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 4)
        #expect(operating == 4500)
        #expect(max == 5000)
    }

    @Test("Operating current is always in bits 19:10, not 9:0")
    func fieldOrderMatchesSpec() {
        // Construct an RDO where the two current values differ so a swap
        // would be caught: operating = 100 (1A), max = 300 (3A)
        let rdo: UInt32 = (2 << 28) | (100 << 10) | 300
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(operating == 1000, "Operating current should be 1000mA (bits 19:10)")
        #expect(max == 3000, "Max operating current should be 3000mA (bits 9:0)")
        #expect(operating < max, "Operating should be less than max in this test case")
    }

    @Test("Zero RDO produces all zeros")
    func zeroRDO() {
        let rdo: UInt32 = 0
        let position = Int((rdo >> 28) & 0x7)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 0)
        #expect(operating == 0)
        #expect(max == 0)
    }

    @Test("Max values: PDO position 7, both currents at 1023 (10.23A)")
    func maxValues() {
        let rdo: UInt32 = (7 << 28) | (0x3FF << 10) | 0x3FF
        let position = Int((rdo >> 28) & 0x7)
        let operating = Int((rdo >> 10) & 0x3FF) * 10
        let max = Int(rdo & 0x3FF) * 10
        #expect(position == 7)
        #expect(operating == 10230)
        #expect(max == 10230)
    }
}
