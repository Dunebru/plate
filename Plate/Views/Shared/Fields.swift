import SwiftUI

/// Form rows shared by onboarding and settings. They all deal with the same annoyance: the app
/// stores metric because the formulas are metric, while the person may think in feet and pounds.

struct HeightField: View {
    @Bindable var profile: Profile
    @State private var feet: Int
    @State private var inches: Int

    init(profile: Profile) {
        self.profile = profile
        let (f, i) = Units.cmToFeetInches(profile.heightCm)
        self._feet = State(initialValue: f)
        self._inches = State(initialValue: i)
    }

    var body: some View {
        HStack {
            Text("Height")
            Spacer()
            if profile.units == .metric {
                NumberField(title: "cm", value: $profile.heightCm).frame(width: 70)
                Text("cm").foregroundStyle(.secondary)
            } else {
                Picker("Feet", selection: $feet) { ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) } }.labelsHidden()
                Picker("Inches", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) } }.labelsHidden()
            }
        }
        .onChange(of: feet) { _, _ in profile.heightCm = Units.feetInchesToCm(feet, inches) }
        .onChange(of: inches) { _, _ in profile.heightCm = Units.feetInchesToCm(feet, inches) }
        .onChange(of: profile.units) { _, _ in
            let (f, i) = Units.cmToFeetInches(profile.heightCm)
            feet = f; inches = i
        }
    }
}

struct WeightField: View {
    var title: String
    @Binding var kg: Double
    var units: UnitSystem
    @State private var shown: Double

    init(title: String, kg: Binding<Double>, units: UnitSystem) {
        self.title = title
        self._kg = kg
        self.units = units
        self._shown = State(initialValue: units == .metric ? kg.wrappedValue : Units.kgToLb(kg.wrappedValue))
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            NumberField(title: units == .metric ? "kg" : "lb", value: $shown, decimals: 1).frame(width: 80)
            Text(units == .metric ? "kg" : "lb").foregroundStyle(.secondary)
        }
        .onAppear { shown = units == .metric ? kg : Units.kgToLb(kg) }
        .onChange(of: units) { _, u in shown = u == .metric ? kg : Units.kgToLb(kg) }
        .onChange(of: shown) { _, v in
            let newKg = units == .metric ? v : Units.lbToKg(v)
            if abs(newKg - kg) > 0.01 { kg = newKg }
        }
        .onChange(of: kg) { _, k in
            let expected = units == .metric ? k : Units.kgToLb(k)
            if abs(expected - shown) > 0.05 { shown = expected }
        }
    }
}

/// A tape measurement in the user's units, stored in centimeters.
///
/// It keeps its own text rather than a number, so an unmeasured field shows a placeholder instead
/// of a misleading zero, and clearing it writes nil rather than zero.
struct LengthField: View {
    var title: String
    @Binding var cm: Double?
    var units: UnitSystem
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(units == .metric ? "cm" : "in", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(width: 80)
            Text(units == .metric ? "cm" : "in").foregroundStyle(.secondary)
        }
        .onAppear { text = format(cm) }
        .onChange(of: units) { _, _ in text = format(cm) }
        .onChange(of: text) { _, new in
            let cleaned = new.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(cleaned), value > 0 else { cm = nil; return }
            cm = units == .metric ? value : Units.inchesToCm(value)
        }
        .onChange(of: cm) { _, value in
            if !focused, format(value) != text { text = format(value) }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        let shown = units == .metric ? value : Units.cmToInches(value)
        return String(format: "%.1f", shown)
    }
}

/// Pace, with the safety cap made visible rather than silently applied later.
struct PaceSlider: View {
    @Bindable var profile: Profile

    private var capped: Double { NutritionMath.cappedPace(profile.inputs) }
    private var isCapped: Bool { profile.goal.changesWeight && capped < profile.paceKgPerWeek - 0.001 }

    private var paceLabel: String {
        profile.units == .metric
            ? String(format: "%.2f kg a week", profile.paceKgPerWeek)
            : String(format: "%.1f lb a week", Units.kgToLb(profile.paceKgPerWeek))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pace").font(.subheadline)
                Spacer()
                Text(paceLabel).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            Slider(value: $profile.paceKgPerWeek, in: 0.1...1.2, step: 0.05)
            HStack {
                Text("Steady").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(hint).font(.caption).foregroundStyle(isCapped ? .orange : .secondary)
                Spacer()
                Text("Aggressive").font(.caption).foregroundStyle(.secondary)
            }
            if isCapped {
                Text("Plate will use \(Units.weightString(capped, profile.units, decimals: 2)) a week. Faster than that and the scale still moves, but muscle goes with the fat.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var hint: String {
        if isCapped { return "Faster than is useful" }
        switch profile.paceKgPerWeek {
        case ..<0.3: return "Easy to live with"
        case ..<0.6: return "Recommended"
        case ..<0.8: return "Hard but doable"
        default: return "Hungry work"
        }
    }
}

/// Result of testing an API key, shared by onboarding and settings.
enum APIKeyStatus: Equatable {
    case idle, checking, ok
    case failed(String)
}
