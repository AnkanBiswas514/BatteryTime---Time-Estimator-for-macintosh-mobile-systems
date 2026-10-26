import Foundation

public struct EnergySample: Codable, Sendable {
    public let time: Date
    public let energyWh: Double
    public init(time: Date, energyWh: Double) { self.time = time; self.energyWh = energyWh }
}

public struct PowerPoint: Codable, Sendable, Identifiable {
    public var id: Date { time }
    public let time: Date
    public let watts: Double
    public init(time: Date, watts: Double) { self.time = time; self.watts = watts }
}

public struct PowerEstimate: Sendable {
    public let watts: Double
    public let seconds: Double
    public let lowerSeconds: Double
    public let upperSeconds: Double
    public let confidence: String
    public let sampleMinutes: Double
}

public enum BatteryMath {
    public static func validWatts(_ watts: Double) -> Bool { watts.isFinite && watts > 0.05 && watts < 100 }

    public static func rate(_ samples: [EnergySample], charging: Bool, minimumMinutes: Double = 3) -> Double? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last else { return nil }
        let hours = last.time.timeIntervalSince(first.time) / 3600
        guard hours >= minimumMinutes / 60 else { return nil }
        let watts = (charging ? last.energyWh - first.energyWh : first.energyWh - last.energyWh) / hours
        return validWatts(watts) ? watts : nil
    }

    public static func estimate(samples: [EnergySample], energyWh: Double, charging: Bool = false,
                                fullWh: Double? = nil, minimumMinutes: Double = 3) -> PowerEstimate? {
        guard energyWh.isFinite, energyWh >= 0, let last = samples.last else { return nil }
        let recent = samples.filter { last.time.timeIntervalSince($0.time) <= 5 * 60 }
        let long = rate(samples, charging: charging, minimumMinutes: minimumMinutes)
        let short = rate(recent, charging: charging, minimumMinutes: min(2, minimumMinutes))
        guard let base = long ?? short else { return nil }
        let watts = short.map { 0.6 * $0 + 0.4 * base } ?? base
        guard validWatts(watts) else { return nil }
        let available = charging ? max(0, (fullWh ?? energyWh) - energyWh) : energyWh
        guard available > 0 else { return nil }
        // Conservative charging taper approximation, not a calibrated charge curve.
        let fraction = charging ? energyWh / max(fullWh ?? energyWh, 0.001) : 0
        let taper = charging ? (fraction > 0.8 ? 1.5 : 1.15) : 1.0
        let seconds = available / watts * 3600 * taper
        guard seconds.isFinite, seconds > 0 else { return nil }
        let disagreement = short.map { abs($0 - base) / max(base, 0.05) } ?? 0.35
        let coverage = samples.last!.time.timeIntervalSince(samples.first!.time) / 60
        let uncertainty = min(0.65, max(0.15, 0.15 + disagreement * 0.5 + (coverage < 10 ? 0.15 : 0)))
        return PowerEstimate(watts: watts, seconds: seconds,
                             lowerSeconds: seconds / (1 + uncertainty),
                             upperSeconds: seconds / max(0.2, 1 - uncertainty),
                             confidence: coverage >= 10 && disagreement < 0.2 ? "Higher" : "Low",
                             sampleMinutes: coverage)
    }

    public static func budgetWatts(energyWh: Double, targetHours: Double) -> Double? {
        guard energyWh.isFinite, energyWh > 0, targetHours.isFinite, targetHours > 0 else { return nil }
        return energyWh / targetHours
    }

    public static func pollInterval(stable: Bool, displayAwake: Bool) -> TimeInterval {
        displayAwake ? (stable ? 30 : 10) : 60
    }
}

public struct EstimatorHistory: Codable, Sendable {
    public var power: [PowerPoint] = []
    public var predictionErrors: [Double] = []
    public init() {}
    public mutating func record(_ point: PowerPoint) {
        guard BatteryMath.validWatts(point.watts) else { return }
        power.append(point)
        power = power.filter { point.time.timeIntervalSince($0.time) <= 24 * 3600 }.suffix(1000).map { $0 }
    }
    public mutating func recordError(predictedSeconds: Double, actualSeconds: Double) {
        guard predictedSeconds > 0, actualSeconds > 0 else { return }
        predictionErrors.append(abs(predictedSeconds - actualSeconds) / actualSeconds)
        predictionErrors = Array(predictionErrors.suffix(100))
    }
    public var meanAbsolutePercentageError: Double? {
        predictionErrors.isEmpty ? nil : predictionErrors.reduce(0, +) / Double(predictionErrors.count) * 100
    }
}
