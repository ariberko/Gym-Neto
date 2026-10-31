import Foundation
import HealthKit

/// Reads personal baselines from Apple Health so effort scoring fits *you*.
enum HealthBaselines {

    /// Most recent resting heart rate in the last 30 days.
    static func latestRestingHeartRate(store: HKHealthStore) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let type = HKQuantityType(.restingHeartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-30 * 86_400), end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 7)
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        return values.reduce(0, +) / Double(values.count)
    }

    static func age(store: HKHealthStore) -> Int? {
        guard let dob = try? store.dateOfBirthComponents(),
              let date = Calendar.current.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }
}
