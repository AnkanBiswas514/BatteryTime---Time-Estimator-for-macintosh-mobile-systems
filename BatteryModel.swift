import AppKit
import Combine
import Foundation
import BatteryCore

@MainActor
final class BatteryModel: ObservableObject {
    private struct Sample {
        let date: Date
        let energyWh: Double
    }

    @Published private(set) var reading = BatteryReading(percent: nil, hasInternalBattery: false,
                                                          remainingEnergyWh: nil, fullEnergyWh: nil,
                                                          powerState: .unknown, systemEstimateSeconds: -1)
    @Published private(set) var estimateText = "Unavailable"
    @Published private(set) var estimateCaption = "estimated active time remaining"
    @Published private(set) var powerText = "—"
    @Published private(set) var powerCaption = "Power draw"
    @Published private(set) var statusText = "Waiting for battery data"
    @Published private(set) var isDisplayAwake = true
    @Published private(set) var lowPowerModeEnabled: Bool?
    @Published private(set) var isChangingLowPowerMode = false
    @Published private(set) var lowPowerModeStatus = ""

    private var dischargeSamples: [Sample] = []
    private var chargeSamples: [Sample] = []
    private var timer: Timer?
    @Published private(set) var confidenceText = "Learning"
    @Published private(set) var rangeText = "—"
    @Published private(set) var drainAlert = ""
    @Published private(set) var workloadText = "Learning"
    @Published private(set) var budgetText = "Waiting for energy data"
    @Published private(set) var history = EstimatorHistory()
    @Published private(set) var batteryHealthText = "Not available"
    @Published private(set) var refreshSeconds = 10
    private var previousPower: Double?
    private var lastHistoryWrite = Date.distantPast
    private var lastHealthWrite = Date.distantPast
    private var predictionStart: (date: Date, seconds: Double, energy: Double)?
    private let historyKey = "batteryTimeHistoryV2"


    private var window: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "sampleWindowMinutes")
        return TimeInterval(minutes == 0 ? 20 : minutes) * 60
    }
    private var minimumLearningInterval: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: "minimumLearningMinutes")
        return TimeInterval(minutes == 0 ? 5 : minutes) * 60
    }

    private let maximumSampleGap: TimeInterval = 90
    private let cacheMaxAge: TimeInterval = 30 * 24 * 60 * 60

    var menuBarTitle: String {
        guard let percent = reading.percent else { return "🔋 —" }
        return "🔋 \(percent)% · \(estimateText) · \(powerText)"
    }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(displayDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode(EstimatorHistory.self, from: data) { history = saved }
        refresh()
        scheduleRefresh()
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func sampleTimerDidFire(_ timer: Timer) {
        refresh()
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        let stable = drainAlert.isEmpty && confidenceText == "Higher"
        refreshSeconds = Int(BatteryMath.pollInterval(stable: stable, displayAwake: isDisplayAwake))
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(refreshSeconds),
                                     target: self, selector: #selector(sampleTimerDidFire(_:)),
                                     userInfo: nil, repeats: false)
    }

    private func resetAnalytics() {
        confidenceText = "Learning"
        rangeText = "—"
        drainAlert = ""
        previousPower = nil
        predictionStart = nil
    }

    private func updateInsights(_ estimate: PowerEstimate, energy: Double, charging: Bool) {
        confidenceText = estimate.confidence
        rangeText = "\(Self.duration(estimate.lowerSeconds))–\(Self.duration(estimate.upperSeconds))"
        if !charging {
            let previous = previousPower
            drainAlert = previous.map { estimate.watts > $0 * 1.6 && estimate.watts - $0 > 3
                ? "Power use jumped from \(Self.watts($0)) to \(Self.watts(estimate.watts))." : "" } ?? ""
            previousPower = estimate.watts
            workloadText = estimate.watts < 7 ? "Light" : estimate.watts < 15 ? "Moderate" : "Heavy"
            let hours = max(1, UserDefaults.standard.double(forKey: "batteryBudgetHours") == 0 ? 5 : UserDefaults.standard.double(forKey: "batteryBudgetHours"))
            if let budget = BatteryMath.budgetWatts(energyWh: energy, targetHours: hours) {
                budgetText = String(format: "%.1f W allowed for %.1f h · %@", budget, hours,
                                    estimate.watts <= budget ? "On target" : "Above budget")
            }
            if let start = predictionStart, Date().timeIntervalSince(start.date) > 900,
               start.energy > energy, estimate.watts > 0 {
                let elapsed = Date().timeIntervalSince(start.date)
                let observed = (start.energy - energy) / (elapsed / 3600)
                if BatteryMath.validWatts(observed) {
                    history.recordError(predictedSeconds: start.seconds,
                                        actualSeconds: start.energy / observed * 3600)
                }
                predictionStart = nil
            }
            if predictionStart == nil { predictionStart = (Date(), estimate.seconds, energy) }
        }
        if Date().timeIntervalSince(lastHistoryWrite) >= 60 {
            history.record(PowerPoint(time: Date(), watts: estimate.watts))
            if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: historyKey) }
            lastHistoryWrite = Date()
        }
    }

    @objc private func displayDidSleep() {
        isDisplayAwake = false
        dischargeSamples.removeAll()
        chargeSamples.removeAll()
        resetAnalytics()
        refresh()
    }

    @objc private func displayDidWake() {
        isDisplayAwake = true
        dischargeSamples.removeAll()
        chargeSamples.removeAll()
        resetAnalytics()
        refresh()
    }

    private func refresh() {
        let latest = BatteryReading.read()
        reading = latest
        if let full = latest.fullEnergyWh, full > 0 {
            batteryHealthText = String(format: "Full-charge capacity: %.1f Wh", full)
            if Date().timeIntervalSince(lastHealthWrite) > 24 * 3600 {
                var values = UserDefaults.standard.array(forKey: "capacityHistory") as? [[String: Double]] ?? []
                values.append(["time": Date().timeIntervalSince1970, "wh": full])
                values = Array(values.suffix(365))
                UserDefaults.standard.set(values, forKey: "capacityHistory")
                lastHealthWrite = Date()
            }
        }

        guard latest.hasInternalBattery else {
            dischargeSamples.removeAll()
            chargeSamples.removeAll()
            resetAnalytics()
            estimateCaption = ""
            estimateText = ""
            powerCaption = "Power draw"
            powerText = "Unavailable"
            statusText = "This Mac has no internal battery. macOS does not provide system-wide power draw through the battery APIs used by BatteryTime."
            lowPowerModeEnabled = nil
            lowPowerModeStatus = "Low Power Mode is unavailable without an internal battery."
            return
        }

        refreshLowPowerMode(for: latest.powerState)

        switch latest.powerState {
        case .discharging:
            estimateCaption = "estimated active time remaining"
            powerCaption = "Power draw"
            chargeSamples.removeAll()
            updateDischargeEstimate(latest)
        case .charging:
            estimateCaption = "estimated time to full"
            powerCaption = "Charging rate"
            dischargeSamples.removeAll()
            updateChargeEstimate(latest)
        case .plugged:
            dischargeSamples.removeAll()
            chargeSamples.removeAll()
            powerCaption = "Battery power rate"
            powerText = "—"
            if latest.percent == 100 {
                estimateCaption = "battery status"
                estimateText = "Fully charged"
                statusText = "The Mac is connected to power."
            } else {
                estimateCaption = "estimated time to full"
                estimateText = "Not charging"
                statusText = "The Mac is connected to power, but the battery is not currently charging."
            }
        case .unknown:
            dischargeSamples.removeAll()
            chargeSamples.removeAll()
            estimateCaption = "battery status"
            estimateText = "Unavailable"
            powerCaption = "Power rate"
            powerText = "—"
            statusText = "macOS did not report whether the Mac is charging or using battery power."
        }
    }

    private func refreshLowPowerMode(for powerState: BatteryReading.PowerState) {
        let source: String
        switch powerState {
        case .discharging: source = "Battery Power:"
        case .charging, .plugged: source = "AC Power:"
        case .unknown:
            lowPowerModeEnabled = nil
            lowPowerModeStatus = "Connect or disconnect the charger to identify the active power source."
            return
        }

        var process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                lowPowerModeEnabled = nil
                lowPowerModeStatus = "Could not read the macOS Low Power Mode setting."
                return
            }
            var inActiveSection = false
            for line in text.components(separatedBy: .newlines) {
                if line.hasSuffix(" Power:") {
                    inActiveSection = line == source
                } else if inActiveSection {
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    if parts.count >= 2, parts[0] == "lowpowermode" {
                        lowPowerModeEnabled = parts[1] == "1"
                        lowPowerModeStatus = "Applies to the current power source."
                        return
                    }
                }
            }
            lowPowerModeEnabled = nil
            lowPowerModeStatus = "Low Power Mode is unavailable on this Mac or macOS version."
        } catch {
            lowPowerModeEnabled = nil
            lowPowerModeStatus = "Could not read the macOS Low Power Mode setting."
        }
    }

    func setLowPowerMode(_ enabled: Bool) {
        guard !isChangingLowPowerMode else { return }
        let powerFlag: String
        switch reading.powerState {
        case .discharging: powerFlag = "-b"
        case .charging, .plugged: powerFlag = "-c"
        case .unknown:
            lowPowerModeStatus = "BatteryTime could not identify the current power source."
            return
        }

        isChangingLowPowerMode = true
        lowPowerModeStatus = "macOS may ask for an administrator password."
        let setting = enabled ? "1" : "0"
        let script = NSAppleScript(source: "do shell script \"/usr/bin/pmset \(powerFlag) lowpowermode \(setting)\" with administrator privileges")
        var errorInfo: NSDictionary?
        let result = script?.executeAndReturnError(&errorInfo)
        isChangingLowPowerMode = false

        if result == nil || errorInfo != nil {
            lowPowerModeStatus = (errorInfo?[NSAppleScript.errorMessage] as? String)
                ?? "macOS did not apply the Low Power Mode change."
            refreshLowPowerMode(for: reading.powerState)
            return
        }

        refreshLowPowerMode(for: reading.powerState)
        lowPowerModeStatus = lowPowerModeEnabled == enabled
            ? "Low Power Mode updated for the current power source."
            : "macOS did not confirm the Low Power Mode change."
    }

    private func updateDischargeEstimate(_ latest: BatteryReading) {
        guard isDisplayAwake else {
            dischargeSamples.removeAll()
            estimateText = "Display asleep"
            powerText = "—"
            statusText = "Sleeping display time is excluded from the active-use estimate."
            return
        }

        guard let energy = latest.remainingEnergyWh else {
            estimateText = systemFallback(latest.systemEstimateSeconds) ?? "Unavailable"
            powerText = cachedRate(for: "lastGoodAveragePowerWatts", dateKey: "lastGoodAveragePowerDate")
                .map { Self.watts($0) } ?? "—"
            statusText = "This Mac did not provide current battery energy, so BatteryTime cannot calculate its own time estimate."
            return
        }

        let now = Date()
        if let previous = dischargeSamples.last, now.timeIntervalSince(previous.date) > maximumSampleGap {
            dischargeSamples.removeAll()
        }
        if let previous = dischargeSamples.last, energy > previous.energyWh + 0.02 {
            dischargeSamples.removeAll()
        }
        dischargeSamples.append(Sample(date: now, energyWh: energy))
        dischargeSamples.removeAll { now.timeIntervalSince($0.date) > window }

        if let result = BatteryMath.estimate(samples: dischargeSamples.map { EnergySample(time: $0.date, energyWh: $0.energyWh) },
                                              energyWh: energy, minimumMinutes: minimumLearningInterval / 60) {
            saveRate(result.watts, key: "lastGoodAveragePowerWatts", dateKey: "lastGoodAveragePowerDate")
            estimateText = Self.duration(result.seconds)
            powerText = Self.watts(result.watts)
            updateInsights(result, energy: energy, charging: false)
            statusText = "Based on recent active battery discharge. Confidence intervals are heuristic, not guarantees."
            return
        }
        if let first = dischargeSamples.first, let last = dischargeSamples.last,
           dischargeSamples.count >= 3, last.date.timeIntervalSince(first.date) >= minimumLearningInterval {
            let elapsedHours = last.date.timeIntervalSince(first.date) / 3600
            let watts = (first.energyWh - last.energyWh) / elapsedHours
            let estimatedSeconds = energy / watts
            if watts > 0.05, watts < 100, estimatedSeconds >= 60, estimatedSeconds.isFinite {
                saveRate(watts, key: "lastGoodAveragePowerWatts", dateKey: "lastGoodAveragePowerDate")
                estimateText = Self.duration(estimatedSeconds)
                powerText = Self.watts(watts)
                statusText = "Time and power use are estimated from recent awake, unplugged activity. Workload and brightness affect the result."
                return
            }
        }

        if let watts = cachedRate(for: "lastGoodAveragePowerWatts", dateKey: "lastGoodAveragePowerDate") {
            let estimatedSeconds = energy / watts
            if estimatedSeconds >= 60, estimatedSeconds.isFinite {
                estimateText = Self.duration(estimatedSeconds)
                powerCaption = "Recent power draw"
                powerText = Self.watts(watts)
                statusText = "Showing your saved recent power-use rate while current samples are collected."
                return
            }
            showLearningFallback(latest, energy: energy)
        } else if let seconds = usableSystemEstimate(latest.systemEstimateSeconds) {
            let impliedWatts = energy / (seconds / 3600)
            if seconds >= 60, impliedWatts > 0.05, impliedWatts < 100 {
                estimateText = Self.duration(seconds)
                powerCaption = "Estimated power"
                powerText = Self.watts(impliedWatts)
                statusText = "Showing macOS's time estimate and its implied average power rate while BatteryTime measures your recent use."
            } else {
                showLearningFallback(latest, energy: energy)
            }
        } else {
            showLearningFallback(latest, energy: energy)
        }
    }

    private func showLearningFallback(_ latest: BatteryReading, energy: Double) {
        if let seconds = usableSystemEstimate(latest.systemEstimateSeconds), seconds >= 60 {
            estimateText = Self.duration(seconds)
            let impliedWatts = energy / (seconds / 3600)
            powerCaption = "Estimated power"
            powerText = impliedWatts > 0.05 && impliedWatts < 100 ? Self.watts(impliedWatts) : "—"
            statusText = "Showing macOS's most recent time estimate while BatteryTime collects reliable samples."
        } else {
            estimateText = "Calculating…"
            powerCaption = "Power draw"
            powerText = "—"
            statusText = "BatteryTime is collecting reliable awake, unplugged samples. A very short or zero estimate was ignored."
        }
    }

    private func updateChargeEstimate(_ latest: BatteryReading) {
        guard let energy = latest.remainingEnergyWh else {
            chargeSamples.removeAll()
            estimateText = "Unavailable"
            powerText = "—"
            statusText = "This Mac did not provide current battery energy, so charge time cannot be calculated."
            return
        }

        let fullEnergy = latest.fullEnergyWh
            ?? latest.percent.flatMap { percent in percent > 0 ? energy * 100 / Double(percent) : nil }
        guard let fullEnergy, fullEnergy > energy else {
            chargeSamples.removeAll()
            let isFull = latest.percent == 100
            estimateText = isFull ? "Fully charged" : "Calculating…"
            powerText = "—"
            statusText = isFull
                ? "The battery is full and connected to power."
                : "Waiting for usable current and full-charge capacity readings."
            return
        }

        let now = Date()
        if let previous = chargeSamples.last, now.timeIntervalSince(previous.date) > maximumSampleGap {
            chargeSamples.removeAll()
        }
        if let previous = chargeSamples.last, energy < previous.energyWh - 0.02 {
            chargeSamples.removeAll()
        }
        chargeSamples.append(Sample(date: now, energyWh: energy))
        chargeSamples.removeAll { now.timeIntervalSince($0.date) > window }

        if let result = BatteryMath.estimate(samples: chargeSamples.map { EnergySample(time: $0.date, energyWh: $0.energyWh) },
                                              energyWh: energy, charging: true, fullWh: fullEnergy,
                                              minimumMinutes: minimumLearningInterval / 60) {
            saveRate(result.watts, key: "lastGoodChargeRateWatts", dateKey: "lastGoodChargeRateDate")
            estimateText = Self.duration(result.seconds)
            powerText = Self.watts(result.watts)
            updateInsights(result, energy: energy, charging: true)
            statusText = "Charging estimate includes an approximate taper adjustment; actual charging varies."
            return
        }
        if let first = chargeSamples.first, let last = chargeSamples.last,
           chargeSamples.count >= 3, last.date.timeIntervalSince(first.date) >= minimumLearningInterval {
            let elapsedHours = last.date.timeIntervalSince(first.date) / 3600
            let watts = (last.energyWh - first.energyWh) / elapsedHours
            let estimatedSeconds = (fullEnergy - energy) / watts
            if watts > 0.05, watts < 100, estimatedSeconds >= 60, estimatedSeconds.isFinite {
                saveRate(watts, key: "lastGoodChargeRateWatts", dateKey: "lastGoodChargeRateDate")
                estimateText = Self.duration(estimatedSeconds)
                powerText = Self.watts(watts)
                statusText = "Charge time uses the recent battery-capacity increase. Charging slows near full, so this estimate can change."
                return
            }
        }

        if let watts = cachedRate(for: "lastGoodChargeRateWatts", dateKey: "lastGoodChargeRateDate") {
            let estimatedSeconds = (fullEnergy - energy) / watts
            if estimatedSeconds >= 60, estimatedSeconds.isFinite {
                estimateText = Self.duration(estimatedSeconds)
                powerText = Self.watts(watts)
                statusText = "Using your saved recent charging rate while current charge samples are collected. Charging may slow near full."
            } else {
                estimateText = "Calculating…"
                powerText = "—"
                statusText = "BatteryTime is waiting for a reliable time-to-full estimate."
            }
        } else {
            estimateText = "Calculating…"
            powerText = "—"
            statusText = "BatteryTime is measuring how quickly the battery charges. Leave the charger connected for a few minutes."
        }
    }

    private func cachedRate(for key: String, dateKey: String) -> Double? {
        let defaults = UserDefaults.standard
        let watts = defaults.double(forKey: key)
        guard let savedAt = defaults.object(forKey: dateKey) as? Date else { return nil }
        let age = Date().timeIntervalSince(savedAt)
        guard age >= 0, age < cacheMaxAge, watts > 0.05, watts < 100 else { return nil }
        return watts
    }

    private func saveRate(_ watts: Double, key: String, dateKey: String) {
        UserDefaults.standard.set(watts, forKey: key)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }

    private func systemFallback(_ seconds: Double) -> String? {
        guard usableSystemEstimate(seconds) != nil, seconds >= 60 else { return nil }
        return Self.duration(seconds)
    }

    private func usableSystemEstimate(_ seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Unavailable" }
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}
