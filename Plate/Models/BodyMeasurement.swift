import Foundation
import SwiftData

/// A tape measure session. Everything is optional because measuring one thing is better than
/// measuring nothing, and the waist alone already says a lot.
@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double? = nil
    var neckCm: Double? = nil
    var chestCm: Double? = nil
    var waistCm: Double? = nil
    var hipCm: Double? = nil
    var thighCm: Double? = nil
    var armCm: Double? = nil
    var calfCm: Double? = nil
    /// Filled in by the tape formula when the numbers allow it, or typed in from a scan or caliper.
    var bodyFatPercent: Double? = nil
    var bodyFatSourceRaw: String? = nil
    var note: String = ""
    @Attribute(.externalStorage) var photoData: Data? = nil

    init(date: Date = Date()) { self.date = date }

    var bodyFatSource: BodyComposition.Source? {
        get { bodyFatSourceRaw.flatMap(BodyComposition.Source.init(rawValue:)) }
        set { bodyFatSourceRaw = newValue?.rawValue }
    }

    var isEmpty: Bool {
        [weightKg, neckCm, chestCm, waistCm, hipCm, thighCm, armCm, calfCm, bodyFatPercent].allSatisfy { $0 == nil }
    }

    /// Recomputes body fat from the tape when it has not been entered by hand.
    func refreshBodyFat(sex: Sex, heightCm: Double, fallbackWeightKg: Double) {
        guard bodyFatSource != .entered else { return }
        guard let neckCm, let waistCm,
              let percent = BodyComposition.navyBodyFat(sex: sex, heightCm: heightCm, neckCm: neckCm,
                                                        waistCm: waistCm, hipCm: hipCm) else { return }
        bodyFatPercent = percent
        bodyFatSource = .tape
        if weightKg == nil { weightKg = fallbackWeightKg }
    }

    /// The fields worth charting, in the order they are shown.
    static let fields: [Field] = [
        Field(key: "waist", label: "Waist", symbol: "figure.core.training", tip: "Around the belly button, relaxed, at the end of a normal breath out."),
        Field(key: "chest", label: "Chest", symbol: "figure.strengthtraining.traditional", tip: "Across the nipples, arms down, at the end of a normal breath out."),
        Field(key: "hip", label: "Hips", symbol: "figure.stand", tip: "Around the widest part of the seat."),
        Field(key: "neck", label: "Neck", symbol: "person.bust", tip: "Just below the voice box, tape sloping slightly down at the front."),
        Field(key: "arm", label: "Arm", symbol: "dumbbell.fill", tip: "Halfway between shoulder and elbow, arm relaxed by your side."),
        Field(key: "thigh", label: "Thigh", symbol: "figure.walk", tip: "Halfway between hip and knee, standing, weight even."),
        Field(key: "calf", label: "Calf", symbol: "shoe.fill", tip: "Around the widest part, standing."),
    ]

    struct Field: Identifiable, Hashable {
        var id: String { key }
        var key: String
        var label: String
        var symbol: String
        var tip: String
    }

    func value(for key: String) -> Double? {
        switch key {
        case "waist": return waistCm
        case "chest": return chestCm
        case "hip": return hipCm
        case "neck": return neckCm
        case "arm": return armCm
        case "thigh": return thighCm
        case "calf": return calfCm
        default: return nil
        }
    }

    func setValue(_ value: Double?, for key: String) {
        switch key {
        case "waist": waistCm = value
        case "chest": chestCm = value
        case "hip": hipCm = value
        case "neck": neckCm = value
        case "arm": armCm = value
        case "thigh": thighCm = value
        case "calf": calfCm = value
        default: break
        }
    }
}
