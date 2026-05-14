import Foundation
import IOKit
import IOKit.ps
import WhatCableCore

/// External power adapter info from the system. Independent of the per-port
/// IOKit views.
public enum SystemPower {
    public static func currentAdapter() -> AdapterInfo? {
        guard let info = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        let w = (info["Watts"] as? NSNumber)?.intValue
        let voltageMV = (info["AdapterVoltage"] as? NSNumber)?.intValue
        let currentMA = (info["Current"] as? NSNumber)?.intValue
        let desc = info["Description"] as? String
        let tier = (info["AdapterPowerTier"] as? NSNumber)?.intValue
        let wireless: Bool? = (info["IsWireless"] as? NSNumber)?.boolValue

        // UsbHvcMenu is an array of dicts, each with "Voltage" (mV) and
        // "Current" (mA) keys describing one combo the charger supports.
        // CF arrays from IOKit don't always bridge cleanly to Swift arrays,
        // so cast through NSArray/NSDictionary (same pattern as
        // PowerSourceWatcher.parseOptions).
        let hvcMenu: [AdapterHVCEntry] = {
            guard let arr = info["UsbHvcMenu"] as? NSArray else { return [] }
            return arr.compactMap { element -> AdapterHVCEntry? in
                let dict: [String: Any]?
                if let d = element as? [String: Any] {
                    dict = d
                } else if let nsd = element as? NSDictionary {
                    var converted: [String: Any] = [:]
                    for case let (key, val) as (String, Any) in nsd {
                        converted[key] = val
                    }
                    dict = converted
                } else {
                    dict = nil
                }
                guard let dict else { return nil }
                let v = (dict["Voltage"] as? NSNumber)?.intValue ?? 0
                let c = (dict["Current"] as? NSNumber)?.intValue ?? 0
                guard v > 0, c > 0 else { return nil }
                return AdapterHVCEntry(voltageMV: v, currentMA: c)
            }
        }()

        return AdapterInfo(
            watts: w,
            isCharging: nil,
            source: "AC",
            voltageMV: voltageMV,
            currentMA: currentMA,
            adapterDescription: desc,
            powerTier: tier,
            isWireless: wireless,
            hvcMenu: hvcMenu
        )
    }
}

extension ChargingDiagnostic {
    /// Convenience: fetches the system adapter via IOKit and constructs
    /// a diagnostic. Callers that need a custom adapter (e.g. tests)
    /// can use the core init that takes `adapter:` explicitly.
    public init?(
        port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity]
    ) {
        self.init(
            port: port,
            sources: sources,
            identities: identities,
            adapter: SystemPower.currentAdapter()
        )
    }
}

