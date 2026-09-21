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
    /// What a wearable last told us. Empty until the user switches the feature on and something
    /// answers, which on a phone with no band and no watch is never.
    @Published var signals = HealthSignals.Snapshot()

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

    /// Summed from the one source Plate trusts most rather than from all of them.
    ///
    /// Health does not deduplicate across sources the way its own app does, so a band and a phone
    /// both recording the same walk would be added together and the day would read roughly twice
    /// the truth. That matters most for energy, which is budgeted against.
    private func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let type = HKQuantityType(id)
        let start = Calendar.current.startOfDay(for: Date())
        var predicate: NSPredicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        if let best = await preferredSource(for: type, start: start, end: Date()) {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate, HKQuery.predicateForObjects(from: [best.source]),
            ])
        }
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

// MARK: - Reading a wearable

/// A Whoop, an Apple Watch or any app that writes to Health can fill this in. Plate asks for these
/// only when the switch in Settings is turned on, and it asks for nothing it does not display.
extension HealthStore {

    private var signalReadTypes: Set<HKObjectType> {
        Set([
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ])
    }

    /// Asks at the moment the feature is switched on, never at launch.
    ///
    /// The result says only that the sheet was shown without error. Health deliberately refuses to
    /// tell an app which read permissions were granted, so that a refusal cannot be detected and
    /// nagged about. A denied type simply returns nothing, exactly like a type nobody has data for,
    /// and everything downstream treats those two the same way.
    @discardableResult
    func requestSignalAuthorization() async -> Bool {
        guard Self.available else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: signalReadTypes)
            return true
        } catch {
            return false
        }
    }

    /// Reads what a wearable has written and leaves the snapshot empty when nothing has.
    func refreshSignals(prediction: HealthSignals.Prediction, windowDays: Int = 28) async {
        guard Self.available, UserDefaults.standard.bool(forKey: HealthSignals.defaultsKey) else {
            signals = HealthSignals.Snapshot()
            return
        }
        let cal = Calendar.current
        // Today is still accruing, so a partial day of resting burn would drag every average down.
        // Whole days only.
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -windowDays, to: end) ?? end

        var snapshot = HealthSignals.Snapshot(readAt: Date())
        // The list runs up to this minute, because a session finished an hour ago should be on
        // screen. The arithmetic below keeps to whole days, so a session today is not divided
        // across a window it does not belong to yet.
        snapshot.workouts = await recentWorkouts(from: start, to: Date())
        snapshot.training = HealthSignals.trainingWeek(snapshot.workouts, overDays: windowDays)
        snapshot.burn = await measuredBurn(from: start, to: end,
                                           workouts: snapshot.workouts.filter { $0.end < end },
                                           prediction: prediction,
                                           windowDays: windowDays)
        snapshot.recovery = await recovery()
        signals = snapshot
    }

    // MARK: Burn

    private func measuredBurn(from start: Date, to end: Date,
                              workouts: [HealthSignals.Workout],
                              prediction: HealthSignals.Prediction,
                              windowDays: Int) async -> HealthSignals.MeasuredBurn? {
        var days: [HealthSignals.DayEnergy] = []
        var source = HealthSignals.Source.other("Apple Health")

        if let active = await preferredSource(for: HKQuantityType(.activeEnergyBurned), start: start, end: end) {
            source = active.kind
            let activeByDay = await dailySums(.activeEnergyBurned, unit: .kilocalorie(),
                                              from: active.source, start: start, end: end)
            // The device reporting movement and the device reporting resting burn need not be the
            // same one, so the resting half gets its own pick of source.
            var basalByDay: [Date: Double] = [:]
            if let basal = await preferredSource(for: HKQuantityType(.basalEnergyBurned), start: start, end: end) {
                basalByDay = await dailySums(.basalEnergyBurned, unit: .kilocalorie(),
                                             from: basal.source, start: start, end: end)
            }
            days = activeByDay.keys.sorted().map { day in
                HealthSignals.DayEnergy(date: day, activeKcal: activeByDay[day] ?? 0, basalKcal: basalByDay[day])
            }
        }
        return HealthSignals.measuredBurn(days: days, workouts: workouts, source: source,
                                          prediction: prediction, windowDays: windowDays)
    }

    private func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                           from source: HKSource, start: Date, end: Date) async -> [Date: Double] {
        let cal = Calendar.current
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            HKQuery.predicateForObjects(from: [source]),
        ])
        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id),
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: cal.startOfDay(for: start),
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit), sum > 0 {
                        out[cal.startOfDay(for: stats.startDate)] = sum
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(query)
        }
    }

    // MARK: Training

    private func recentWorkouts(from start: Date, to end: Date) async -> [HealthSignals.Workout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKWorkout] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: 200, sortDescriptors: [sort]) { _, found, _ in
                cont.resume(returning: (found as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        let energy = HKQuantityType(.activeEnergyBurned)
        let list = samples.map { workout in
            HealthSignals.Workout(id: workout.uuid,
                                  date: workout.startDate,
                                  end: workout.endDate,
                                  kind: HealthSignals.workoutName(workout.workoutActivityType),
                                  minutes: Int((workout.duration / 60).rounded()),
                                  kcal: workout.statistics(for: energy)?.sumQuantity()
                                      .map { Int($0.doubleValue(for: .kilocalorie()).rounded()) },
                                  source: Self.kind(of: workout.sourceRevision))
        }
        return HealthSignals.deduplicate(list)
    }

    // MARK: Recovery context

    private func recovery() async -> HealthSignals.Recovery {
        var out = HealthSignals.Recovery()
        let perMinute = HKUnit.count().unitDivided(by: .minute())

        if let latest = await latestQuantity(.restingHeartRate, unit: perMinute) {
            out.restingHeartRate = Int(latest.value.rounded())
            out.restingHeartRateSource = latest.source
        }
        if let latest = await latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)) {
            out.hrvMs = Int(latest.value.rounded())
            out.hrvSource = latest.source
            out.hrvDate = latest.date
        }
        if let latest = await latestQuantity(.respiratoryRate, unit: perMinute) {
            out.respiratoryRate = (latest.value * 10).rounded() / 10
            out.respiratoryRateSource = latest.source
        }
        if let sleep = await lastNightSleep() {
            out.sleepHours = sleep.hours
            out.sleepSource = sleep.source
            out.sleepEnd = sleep.end
        }
        return out
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier,
                                unit: HKUnit) async -> (value: Double, source: HealthSignals.Source, date: Date)? {
        // Older than a week is history rather than context, and showing it beside today's numbers
        // would read as though it were current.
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: (sample.quantity.doubleValue(for: unit),
                                        Self.kind(of: sample.sourceRevision),
                                        sample.endDate))
            }
            store.execute(query)
        }
    }

    private func lastNightSleep() async -> (hours: Double, source: HealthSignals.Source, end: Date)? {
        // Wide enough for a late night and a long lie in, narrow enough that it cannot reach back
        // and count the night before as well.
        let start = Calendar.current.date(byAdding: .hour, value: -30, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, found, _ in
                cont.resume(returning: (found as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        // In bed is not asleep, and lying awake at four in the morning is not either. Only the
        // stages that mean sleep are counted.
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
        guard let last = asleep.max(by: { $0.endDate < $1.endDate }) else { return nil }

        let minutes = HealthSignals.unionMinutes(asleep.map { (start: $0.startDate, end: $0.endDate) })
        guard minutes > 0 else { return nil }
        let source = asleep.map { Self.kind(of: $0.sourceRevision) }.min { $0.rank < $1.rank } ?? Self.kind(of: last.sourceRevision)
        return ((minutes / 60 * 10).rounded() / 10, source, last.endDate)
    }

    // MARK: Sources

    nonisolated static func kind(of revision: HKSourceRevision) -> HealthSignals.Source {
        HealthSignals.classify(bundleIdentifier: revision.source.bundleIdentifier,
                               productType: revision.productType,
                               name: revision.source.name)
    }

    /// The one source Plate will believe for a type, out of however many are writing it.
    fileprivate func preferredSource(for type: HKSampleType, start: Date,
                                     end: Date) async -> (source: HKSource, kind: HealthSignals.Source)? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let found: Set<HKSource> = await withCheckedContinuation { cont in
            let query = HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, _ in
                cont.resume(returning: sources ?? [])
            }
            store.execute(query)
        }
        var best: (source: HKSource, kind: HealthSignals.Source)?
        for source in found {
            // Only a sample carries the hardware model, and the model is the only thing that tells
            // an Apple Watch from the phone it syncs to.
            let kind = await firstSampleKind(from: source, type: type)
            if best == nil || kind.rank < best!.kind.rank { best = (source, kind) }
        }
        return best
    }

    private func firstSampleKind(from source: HKSource, type: HKSampleType) async -> HealthSignals.Source {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let revision: HKSourceRevision? = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForObjects(from: [source]),
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: samples?.first?.sourceRevision)
            }
            store.execute(query)
        }
        guard let revision else {
            return HealthSignals.classify(bundleIdentifier: source.bundleIdentifier,
                                          productType: nil, name: source.name)
        }
        return Self.kind(of: revision)
    }
}
