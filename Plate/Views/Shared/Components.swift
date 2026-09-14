import SwiftUI

extension Color {
    static let calories = Color.accentColor
    static let protein = Color(red: 0.93, green: 0.35, blue: 0.35)
    static let carbs = Color(red: 0.98, green: 0.66, blue: 0.20)
    static let fat = Color(red: 0.30, green: 0.60, blue: 0.95)
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// The big ring on the home screen. Fills toward the target and turns red when over.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var lineWidth: CGFloat = 14

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }
    private var over: Bool { eaten > target && target > 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(over ? Color.red : Color.calories, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.9), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int(max(target - eaten, 0).rounded()))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(over ? "over by \(Int((eaten - target).rounded()))" : "left")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(over ? .red : .secondary)
            }
        }
    }
}

struct MacroCard: View {
    var title: String
    var eaten: Double
    var target: Double
    var color: Color

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(eaten.rounded()))")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("/ \(Int(target)) g")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: geo.size.width * fraction)
                        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: fraction)
                }
            }
            .frame(height: 6)
        }
        .card()
    }
}

/// A text field bound to a Double that keeps the keyboard numeric and tolerates commas.
struct NumberField: View {
    var title: String
    @Binding var value: Double
    var decimals: Int = 0
    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, value: Binding<Double>, decimals: Int = 0) {
        self.title = title
        self._value = value
        self.decimals = decimals
        let v = value.wrappedValue
        self._text = State(initialValue: decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v))
    }

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onChange(of: value) { _, new in if !focused { text = format(new) } }
            .onChange(of: text) { _, new in
                if let d = Double(new.replacingOccurrences(of: ",", with: ".")) { value = d }
            }
            .onChange(of: focused) { _, f in if !f { text = format(value) } }
    }

    private func format(_ v: Double) -> String {
        decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

extension Double {
    var kcalString: String { "\(Int(self.rounded())) kcal" }
    var gramsString: String { "\(Int(self.rounded())) g" }
}

extension Date {
    var dayTitle: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
