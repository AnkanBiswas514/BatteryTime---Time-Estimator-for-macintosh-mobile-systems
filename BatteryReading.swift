import Foundation
import IOKit
import IOKit.ps

struct BatteryReading {
    enum PowerState: String {
        case discharging = "Discharging"
        case charging = "Charging"
        case plugged = "On power"
        case unknown = "Unknown"
    }

    let percent: Int?
    let hasInternalBattery: Bool
    let remainingEnergyWh: Double?
    let fullEnergyWh: Double?
    let powerState: PowerState
    let systemEstimateSeconds: Double

    static func read() -> BatteryReading {
        var percent: Int?
        var hasInternalBattery = false
        var energyWh: Double?
        var fullEnergyWh: Double?
        var state: PowerState = .unknown

        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            let providingType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as? String
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
                hasInternalBattery = true
                if let current = description[kIOPSCurrentCapacityKey] as? Int,
                   let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                    percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
                }
                let sourceState = description[kIOPSPowerSourceStateKey] as? String
                let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
                // The providing source is authoritative; the per-battery charging flag can lag
                // briefly after the charger is unplugged.
                if providingType == (kIOPSBatteryPowerValue as String) {
                    state = .discharging
                } else if providingType == (kIOPSACPowerValue as String) {
                    state = isCharging ? .charging : .plugged
                } else if sourceState == (kIOPSBatteryPowerValue as String) {
                    state = .discharging
                } else if sourceState == (kIOPSACPowerValue as String) {
                    state = isCharging ? .charging : .plugged
                } else if isCharging {
                    state = .charging
                } else {
                    state = .unknown
                }
                break
            }
        }

        // AppleSmartBattery exposes capacities in mAh and voltage in mV on many, but not all, Macs.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            hasInternalBattery = true
            defer { IOObjectRelease(service) }
            var propertiesRef: Unmanaged<CFMutableDictionary>?
            let result = IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0)
            if result == KERN_SUCCESS,
               let properties = propertiesRef?.takeRetainedValue() as? [String: Any],
               let voltage = (properties["Voltage"] as? NSNumber)?.doubleValue,
               voltage > 0 {
                let current = (properties["AppleRawCurrentCapacity"] as? NSNumber)?.doubleValue
                    ?? (properties["CurrentCapacity"] as? NSNumber)?.doubleValue
                let maximum = (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
                    ?? (properties["MaxCapacity"] as? NSNumber)?.doubleValue
                if let current, current > 0 {
                    energyWh = current * voltage / 1_000_000.0
                }
                if let maximum, maximum > 0 {
                    fullEnergyWh = maximum * voltage / 1_000_000.0
                }
            }
        }

        let estimate = IOPSGetTimeRemainingEstimate()
        return BatteryReading(percent: percent, hasInternalBattery: hasInternalBattery,
                              remainingEnergyWh: energyWh, fullEnergyWh: fullEnergyWh,
                              powerState: state, systemEstimateSeconds: estimate)
    }
}
