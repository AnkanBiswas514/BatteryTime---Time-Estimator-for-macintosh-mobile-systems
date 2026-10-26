import SwiftUI

struct PreferencesView: View {
    @AppStorage("showMenuIcon") private var showMenuIcon = true
    @AppStorage("showMenuEstimate") private var showMenuEstimate = true
    @AppStorage("showMenuPower") private var showMenuPower = true
    @AppStorage("sampleWindowMinutes") private var sampleWindowMinutes = 20
    @AppStorage("minimumLearningMinutes") private var minimumLearningMinutes = 5

    @AppStorage("batteryBudgetHours") private var batteryBudgetHours = 5.0

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show icon", isOn: $showMenuIcon)
                Toggle("Show time estimate", isOn: $showMenuEstimate)
                Toggle("Show power draw or charging rate", isOn: $showMenuPower)
                Text("The percentage is displayed inside the battery icon. Green means charging; yellow means Low Power Mode (yellow takes priority).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Battery budget") {
                Stepper(value: $batteryBudgetHours, in: 1...24, step: 0.5) {
                    Text("Target runtime: \(batteryBudgetHours, specifier: "%.1f") hours")
                }
                Text("BatteryTime compares your measured power draw with the maximum average draw that would meet your target.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Estimate") {
                Stepper("Averaging window: \(sampleWindowMinutes) minutes",
                        value: $sampleWindowMinutes, in: 10...30, step: 5)
                Picker("Start estimating after", selection: $minimumLearningMinutes) {
                    Text("3 minutes").tag(3)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
                Text("BatteryTime adjusts sampling between 10 and 60 seconds. It calculates active battery time while unplugged and time to full while charging. A longer averaging window smooths out short workload changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .frame(width: 430)
    }
}
