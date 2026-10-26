import SwiftUI
import Charts

struct BatteryPopover: View {
    @ObservedObject var model: BatteryModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.reading.hasInternalBattery {
                HStack {
                    Text("BatteryTime").font(.headline)
                    Spacer()
                    Text("Desktop Mac").font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Label("Power draw", systemImage: "bolt.fill")
                    Spacer()
                    Text(model.powerText).monospacedDigit()
                }
                .font(.callout)

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                HStack {
                    Spacer()
                    Button("Settings…") { openSettings() }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                }
            } else {
            HStack(alignment: .firstTextBaseline) {
                Text("BatteryTime").font(.headline)
                Spacer()
                Text(model.reading.powerState.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.reading.percent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Battery").font(.caption).foregroundStyle(.secondary)
                }
                Divider().frame(height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.estimateText)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text(model.estimateCaption).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Label(model.powerCaption, systemImage: "bolt.fill")
                Spacer()
                Text(model.powerText).monospacedDigit()
            }
            .font(.callout)

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Prediction confidence", systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Text(model.confidenceText)
                }
                Text("Likely range: \(model.rangeText)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Workload: \(model.workloadText)")
                    Spacer()
                    Text("\(model.refreshSeconds)s refresh")
                }.font(.caption).foregroundStyle(.secondary)
                if !model.drainAlert.isEmpty {
                    Label(model.drainAlert, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("Battery budget", systemImage: "target").font(.headline)
                Text(model.budgetText).font(.caption)
                Text(model.batteryHealthText).font(.caption).foregroundStyle(.secondary)
            }
            if !model.history.power.isEmpty {
                Divider()
                Text("Battery power trend · last 24h").font(.caption).foregroundStyle(.secondary)
                Chart(model.history.power) { point in
                    LineMark(x: .value("Time", point.time), y: .value("W", point.watts))
                }
                .frame(height: 85)
                if let error = model.history.meanAbsolutePercentageError {
                    Text(String(format: "Observed prediction error: %.1f%% (limited samples)", error))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Label("Low Power Mode", systemImage: "leaf.fill")
                Spacer()
                if model.isChangingLowPowerMode {
                    ProgressView().controlSize(.small)
                } else {
                    Toggle("Low Power Mode", isOn: Binding(
                        get: { model.lowPowerModeEnabled ?? false },
                        set: { model.setLowPowerMode($0) }
                    ))
                    .labelsHidden()
                    .disabled(model.lowPowerModeEnabled == nil || model.isChangingLowPowerMode)
                }
            }
            .font(.callout)
            Text(model.lowPowerModeStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            HStack {
                Text("Battery sampling adapts to activity")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Settings…") { openSettings() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
