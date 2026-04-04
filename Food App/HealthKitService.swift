import Foundation
import Combine

#if canImport(HealthKit)
import HealthKit
#endif

enum HealthAuthorizationState: String {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case notAuthorized
    case authorizationFailed(String)
    case saveFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is unavailable on this device."
        case .notAuthorized:
            return "Apple Health permission is not granted."
        case let .authorizationFailed(message):
            return "Apple Health permission request failed: \(message)"
        case let .saveFailed(message):
            return "Failed to sync nutrition data to Apple Health: \(message)"
        case let .readFailed(message):
            return "Failed to read Apple Health data: \(message)"
        }
    }
}

struct BodyMassSample: Identifiable, Hashable {
    let date: Date
    let kilograms: Double
    let sourceName: String?

    var id: String {
        "\(date.timeIntervalSince1970)-\(sourceName ?? "unknown")-\(kilograms)"
    }
}

@MainActor
final class HealthKitService: ObservableObject {
#if canImport(HealthKit)
    private let store = HKHealthStore()
#endif

    @Published private(set) var authorizationState: HealthAuthorizationState = .notDetermined

    init() {
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        let statuses = nutritionQuantityTypes.map { store.authorizationStatus(for: $0) }
        if statuses.isEmpty {
            authorizationState = .unavailable
            return
        }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            authorizationState = .authorized
        } else if statuses.contains(.sharingDenied) {
            authorizationState = .denied
        } else {
            authorizationState = .notDetermined
        }
#else
        authorizationState = .unavailable
#endif
    }

    func requestNutritionAuthorization() async throws -> Bool {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            throw HealthKitServiceError.unavailable
        }

        let shareTypes = Set(nutritionQuantityTypes)
        let readTypes: Set<HKObjectType> = Set(
            nutritionQuantityTypes.map { $0 as HKObjectType } + extraReadTypes
        )

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: HealthKitServiceError.authorizationFailed(error.localizedDescription))
                        return
                    }
                    continuation.resume(returning: success)
                }
            }
        } catch {
            if let healthError = error as? HealthKitServiceError {
                throw healthError
            }
            throw HealthKitServiceError.authorizationFailed(error.localizedDescription)
        }

        refreshAuthorizationState()
        return authorizationState == .authorized
#else
        authorizationState = .unavailable
        throw HealthKitServiceError.unavailable
#endif
    }

    func fetchBodyMassSamples(from startDate: Date, to endDate: Date) async throws -> [BodyMassSample] {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }
        guard authorizationState == .authorized else {
            throw HealthKitServiceError.notAuthorized
        }
        guard let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: bodyMassType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: sortDescriptors
                ) { _, results, error in
                    if let error {
                        continuation.resume(throwing: HealthKitServiceError.readFailed(error.localizedDescription))
                        return
                    }
                    let quantitySamples = (results as? [HKQuantitySample]) ?? []
                    continuation.resume(returning: quantitySamples)
                }
                self.store.execute(query)
            }

            return samples.map { sample in
                BodyMassSample(
                    date: sample.startDate,
                    kilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                    sourceName: sample.sourceRevision.source.name
                )
            }
        } catch {
            if let healthError = error as? HealthKitServiceError {
                throw healthError
            }
            throw HealthKitServiceError.readFailed(error.localizedDescription)
        }
#else
        throw HealthKitServiceError.unavailable
#endif
    }

    func fetchTodayStepCount() async throws -> Double {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.readFailed(error.localizedDescription))
                    return
                }
                let sum = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: sum)
            }
            self.store.execute(query)
        }
#else
        throw HealthKitServiceError.unavailable
#endif
    }

    func fetchTodayActiveEnergy() async throws -> Double {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.readFailed(error.localizedDescription))
                    return
                }
                let sum = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: sum)
            }
            self.store.execute(query)
        }
#else
        throw HealthKitServiceError.unavailable
#endif
    }

    static func displayWeightValue(kilograms: Double, units: UnitsOption) -> Double {
        switch units {
        case .metric:
            return kilograms
        case .imperial:
            return kilograms * 2.2046226218
        }
    }

    static func weightUnitLabel(for units: UnitsOption) -> String {
        switch units {
        case .metric:
            return "kg"
        case .imperial:
            return "lb"
        }
    }

    func writeNutritionTotals(_ totals: NutritionTotals, loggedAt: Date) async throws -> Bool {
#if canImport(HealthKit)
        guard authorizationState == .authorized else {
            throw HealthKitServiceError.notAuthorized
        }

        let endDate = loggedAt.addingTimeInterval(1)
        var samples: [HKQuantitySample] = []

        if totals.calories > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: totals.calories)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: loggedAt, end: endDate))
        }

        if totals.protein > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: totals.protein)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: loggedAt, end: endDate))
        }

        if totals.carbs > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: totals.carbs)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: loggedAt, end: endDate))
        }

        if totals.fat > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: totals.fat)
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: loggedAt, end: endDate))
        }

        guard !samples.isEmpty else {
            return false
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.save(samples) { success, error in
                    if let error {
                        continuation.resume(throwing: HealthKitServiceError.saveFailed(error.localizedDescription))
                        return
                    }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthKitServiceError.saveFailed("Unknown Apple Health save error"))
                    }
                }
            }
            return true
        } catch {
            if let healthError = error as? HealthKitServiceError {
                throw healthError
            }
            throw HealthKitServiceError.saveFailed(error.localizedDescription)
        }
#else
        throw HealthKitServiceError.unavailable
#endif
    }
}

#if canImport(HealthKit)
private extension HealthKitService {
    var nutritionQuantityTypes: [HKQuantityType] {
        [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKObjectType.quantityType(forIdentifier: .dietaryProtein),
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
        ].compactMap { $0 }
    }

    var extraReadTypes: [HKObjectType] {
        [
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .bodyMass)
        ].compactMap { $0 }
    }
}
#endif
