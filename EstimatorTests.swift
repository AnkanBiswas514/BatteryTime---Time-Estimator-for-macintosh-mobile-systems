import XCTest
@testable import BatteryCore

final class EstimatorTests: XCTestCase {
    func testDischargeRate() {
        let now = Date(timeIntervalSince1970: 10000)
        let samples = (0...10).map { EnergySample(time: now.addingTimeInterval(Double($0) * 60), energyWh: 40 - Double($0) / 6) }
        XCTAssertEqual(BatteryMath.rate(samples, charging: false)!, 10, accuracy: 0.001)
        let result = BatteryMath.estimate(samples: samples, energyWh: 38)!
        XCTAssertEqual(result.watts, 10, accuracy: 0.001)
        XCTAssertEqual(result.seconds, 13680, accuracy: 1)
        XCTAssertLessThan(result.lowerSeconds, result.seconds)
        XCTAssertGreaterThan(result.upperSeconds, result.seconds)
    }
    func testChargeTaper() {
        let now = Date(timeIntervalSince1970: 10000)
        let samples = (0...10).map { EnergySample(time: now.addingTimeInterval(Double($0) * 60), energyWh: 42 + Double($0) / 6) }
        let result = BatteryMath.estimate(samples: samples, energyWh: 43.6666667, charging: true, fullWh: 50)!
        XCTAssertGreaterThan(result.seconds, (50 - 43.6666667) / 10 * 3600)
    }
    func testBadSamplesAndBudget() {
        XCTAssertNil(BatteryMath.rate([EnergySample(time: Date(), energyWh: 5)], charging: false))
        XCTAssertNil(BatteryMath.budgetWatts(energyWh: 20, targetHours: 0))
        XCTAssertEqual(BatteryMath.budgetWatts(energyWh: 30, targetHours: 5)!, 6)
    }
    func testHistoryBounds() {
        var history = EstimatorHistory()
        for _ in 0..<150 { history.recordError(predictedSeconds: 110, actualSeconds: 100) }
        XCTAssertEqual(history.predictionErrors.count, 100)
        XCTAssertEqual(history.meanAbsolutePercentageError!, 10, accuracy: 0.001)
    }
}
