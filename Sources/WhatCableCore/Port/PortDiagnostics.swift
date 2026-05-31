import Foundation

public enum PDO: Codable, Sendable, Equatable {
    case fixed(voltage: Int, maxCurrent: Int)
    case battery(minVoltage: Int, maxPower: Int)
    case variable(minVoltage: Int, maxCurrent: Int)
    case apdo(minVoltage: Int, maxVoltage: Int, maxCurrent: Int)

    public static func decode(rawValue: UInt32) -> PDO {
        switch (rawValue >> 30) & 0x3 {
        case 0:
            let voltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxCurrent = Int(rawValue & 0x3FF) * 10
            return .fixed(voltage: voltage, maxCurrent: maxCurrent)
        case 1:
            let minVoltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxPower = Int(rawValue & 0x3FF) * 250
            return .battery(minVoltage: minVoltage, maxPower: maxPower)
        case 2:
            let minVoltage = Int((rawValue >> 10) & 0x3FF) * 50
            let maxCurrent = Int(rawValue & 0x3FF) * 10
            return .variable(minVoltage: minVoltage, maxCurrent: maxCurrent)
        default:
            let maxVoltage = Int((rawValue >> 17) & 0xFF) * 100
            let minVoltage = Int((rawValue >> 8) & 0xFF) * 100
            let maxCurrent = Int(rawValue & 0x7F) * 50
            return .apdo(minVoltage: minVoltage, maxVoltage: maxVoltage, maxCurrent: maxCurrent)
        }
    }
}

public struct PDContract: Codable, Sendable, Equatable {
    public let activeRdo: UInt32
    public let pdoList: [PDO]
    public let pdoCount: Int
    public let maxPower: Int
    public let capMismatch: Bool
    public let srcTypes: Int

    public init(
        activeRdo: UInt32,
        pdoList: [PDO],
        pdoCount: Int,
        maxPower: Int,
        capMismatch: Bool,
        srcTypes: Int
    ) {
        self.activeRdo = activeRdo
        self.pdoList = pdoList
        self.pdoCount = pdoCount
        self.maxPower = maxPower
        self.capMismatch = capMismatch
        self.srcTypes = srcTypes
    }
}

public struct PortHealthCounters: Codable, Sendable, Equatable {
    public let attachCount: Int
    public let detachCount: Int
    public let hardResetCount: Int
    public let shortDetectCount: Int
    public let i2cErrCount: Int
    public let dataRoleSwapCount: Int
    public let dataRoleSwapFailCount: Int
    public let pwrRoleSwapCount: Int
    public let pwrRoleSwapFailCount: Int
    public let vdoFailCount: Int
    public let fetEnableFailCount: Int
    public let fetStatus: UInt8
    public let pdState: UInt8
    public let dnState: UInt8

    public init(
        attachCount: Int,
        detachCount: Int,
        hardResetCount: Int,
        shortDetectCount: Int,
        i2cErrCount: Int,
        dataRoleSwapCount: Int,
        dataRoleSwapFailCount: Int,
        pwrRoleSwapCount: Int,
        pwrRoleSwapFailCount: Int,
        vdoFailCount: Int,
        fetEnableFailCount: Int,
        fetStatus: UInt8,
        pdState: UInt8,
        dnState: UInt8
    ) {
        self.attachCount = attachCount
        self.detachCount = detachCount
        self.hardResetCount = hardResetCount
        self.shortDetectCount = shortDetectCount
        self.i2cErrCount = i2cErrCount
        self.dataRoleSwapCount = dataRoleSwapCount
        self.dataRoleSwapFailCount = dataRoleSwapFailCount
        self.pwrRoleSwapCount = pwrRoleSwapCount
        self.pwrRoleSwapFailCount = pwrRoleSwapFailCount
        self.vdoFailCount = vdoFailCount
        self.fetEnableFailCount = fetEnableFailCount
        self.fetStatus = fetStatus
        self.pdState = pdState
        self.dnState = dnState
    }
}

/// TPS6598x interrupt event types observed in PortControllerEvtBuffer.
/// Codes from the TPS6598x Host Interface TRM and empirical traces.
public enum PDEvent: Codable, Sendable, Equatable {
    case plugInsertOrRemoval
    case prSwapComplete
    case drSwapComplete
    case sourceCapRx
    case statusUpdate
    case pdStatusUpdate
    case usb2Plug
    case powerStatusUpdate
    case appLoaded
    case rxIdSop
    case uvdmStatusUpdate
    case uvdmEnum
    case sleepWake
    case alert
    case unknown(UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x01: self = .plugInsertOrRemoval
        case 0x02: self = .prSwapComplete
        case 0x03: self = .drSwapComplete
        case 0x1a: self = .sourceCapRx
        case 0x30: self = .statusUpdate
        case 0x31: self = .pdStatusUpdate
        case 0x37: self = .usb2Plug
        case 0x3f: self = .powerStatusUpdate
        case 0x40: self = .appLoaded
        case 0x48: self = .rxIdSop
        case 0x5e: self = .uvdmStatusUpdate
        case 0x5f: self = .uvdmEnum
        case 0xf0: self = .sleepWake
        case 0xf1: self = .alert
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .plugInsertOrRemoval: return 0x01
        case .prSwapComplete: return 0x02
        case .drSwapComplete: return 0x03
        case .sourceCapRx: return 0x1a
        case .statusUpdate: return 0x30
        case .pdStatusUpdate: return 0x31
        case .usb2Plug: return 0x37
        case .powerStatusUpdate: return 0x3f
        case .appLoaded: return 0x40
        case .rxIdSop: return 0x48
        case .uvdmStatusUpdate: return 0x5e
        case .uvdmEnum: return 0x5f
        case .sleepWake: return 0xf0
        case .alert: return 0xf1
        case .unknown(let value): return value
        }
    }
}

public struct PDEventTrace: Codable, Sendable, Equatable {
    public let rawBuffer: Data
    public let events: [PDEvent]

    public init(rawBuffer: Data, events: [PDEvent]) {
        self.rawBuffer = rawBuffer
        self.events = events
    }
}

public struct VDMIdentity: Codable, Sendable, Equatable {
    public let vendorId: Int
    public let productId: Int
    public let bcdDevice: Int
    public let specRevision: Int
    public let vdos: [Data]
    public let productType: Int?
    public let productTypeDescription: String?

    public init(
        vendorId: Int,
        productId: Int,
        bcdDevice: Int,
        specRevision: Int,
        vdos: [Data],
        productType: Int?,
        productTypeDescription: String?
    ) {
        self.vendorId = vendorId
        self.productId = productId
        self.bcdDevice = bcdDevice
        self.specRevision = specRevision
        self.vdos = vdos
        self.productType = productType
        self.productTypeDescription = productTypeDescription
    }
}
