import Foundation
import HealthKit

/// Apple Health bridge. Writes what the user logs, reads what the phone already knows.
@MainActor
final class HealthStore: ObservableObject {
    static let shared = HealthStore()
    let store = HKHealthStore()
    @Published var authorized = false
    @Published var activeEnergyToday: Double = 0
    @Published var stepsToday: Int = 0

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var writeTypes: Set<HKSampleType> {
        let ids: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
                                               .dietaryFatTotal, .dietaryFiber, .dietarySugar, .dietarySodium, .bodyMass]
        return Set(ids.map { HKQuantityType($0) })
    }

    private var readTypes: Set<HKObjectType> {
        Set([HKQuantityType(.activeEnergyBurned), HKQuantityType(.stepCount), HKQuantityType(.bodyMass)])
    }

    func requestAuthorization() async {
        guard Self.available else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            authorized = true
            await refreshToday()
        } catch {
            authorized = false
        }
    }

    func refreshToday() async {
        guard Self.available else { return }
        activeEnergyToday = await sumToday(.activeEnergyBurned, unit: .kilocalorie())
        stepsToday = Int(await sumToday(.stepCount, unit: .count()))
    }

    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let type = HKQuantityType(id)
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    /// Latest body mass sample in kilograms, if any.
    func latestWeight() async -> (Date, Double)? {
        guard Self.available else { return nil }
        let type = HKQuantityType(.bodyMass)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let s = samples?.first as? HKQuantitySample {
                    cont.resume(returning: (s.startDate, s.quantity.doubleValue(for: .gramUnit(with: .kilo))))
                } else {
                    cont.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    /// Saves or replaces the nutrition samples for a meal. Sync identifiers make re-saves update instead of duplicate.
    func write(meal: MealEntry) async {
        guard Self.available else { return }
        let t = meal.totals
        let pairs: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, t.calories, .kilocalorie()),
            (.dietaryProtein, t.protein, .gram()),
            (.dietaryCarbohydrates, t.carbs, .gram()),
            (.dietaryFatTotal, t.fat, .gram()),
            (.dietaryFiber, t.fiber, .gram()),
            (.dietarySugar, t.sugar, .gram()),
            (.dietarySodium, t.sodium, .gramUnit(with: .milli)),
        ]
        let version = Int(Date().timeIntervalSince1970)
        var samples: [HKQuantitySample] = []
        for (id, value, unit) in pairs where value > 0 {
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: "com.dunebru.plate.\(meal.id.uuidString).\(id.rawValue)",
                HKMetadataKeySyncVersion: version,
                HKMetadataKeyFoodType: meal.name,
            ]
            samples.append(HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                                            start: meal.date, end: meal.date, metadata: metadata))
        }
        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    func delete(meal: MealEntry) async {
        guard Self.available else { return }
        let ids: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
                                               .dietaryFatTotal, .dietaryFiber, .dietarySugar, .dietarySodium]
        for id in ids {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                        allowedValues: ["com.dunebru.plate.\(meal.id.uuidString).\(id.rawValue)"])
            _ = try? await store.deleteObjects(of: HKQuantityType(id), predicate: predicate)
        }
    }

    func write(weightKg: Double, date: Date) async {
        guard Self.available else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass),
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg),
                                      start: date, end: date)
        try? await store.save(sample)
    }
}
