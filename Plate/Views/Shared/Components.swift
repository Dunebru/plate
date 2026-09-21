import SwiftUI

extension Color {
    /// One colour for each thing the app measures, defined in one place.
    ///
    /// Two rules hold this together. Nothing else in the app may be the accent colour, so the accent
    /// always means calories. And green is reserved for one meaning only, which is that a target has
    /// been reached; it is not the brand, it is a verdict. When green was also the accent those two
    /// meanings were the same colour and neither read.
    ///
    /// Each is given a light and a dark value rather than one compromise. A mid blue that holds its
    /// own against white is muddy on black, and a blue bright enough for black glares on white.
    private static func adaptive(light: (Double, Double, Double),
                                 dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let calories = Color.accentColor

    static let protein = adaptive(light: (0.851, 0.290, 0.290), dark: (1.000, 0.420, 0.420))
    static let carbs = adaptive(light: (0.878, 0.565, 0.063), dark: (1.000, 0.718, 0.302))
    /// Fat used to be blue. It cannot be, now that the accent is: two different meanings a shade
    /// apart on the same screen is how a dashboard stops being readable.
    static let fat = adaptive(light: (0.478, 0.353, 0.973), dark: (0.655, 0.545, 0.980))

    static let fiber = adaptive(light: (0.180, 0.620, 0.345), dark: (0.290, 0.871, 0.502))
    static let sugar = adaptive(light: (0.839, 0.255, 0.494), dark: (0.957, 0.447, 0.714))
    static let sodium = adaptive(light: (0.055, 0.549, 0.549), dark: (0.176, 0.831, 0.749))

    /// A target met. The only thing this colour is allowed to say.
    static let reached = adaptive(light: (0.180, 0.620, 0.345), dark: (0.290, 0.871, 0.502))
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

/// The ring on the home screen. Fills toward the target and turns red when over.
///
/// Everything inside is sized from the ring itself rather than from fixed points, because a four
/// figure calorie target has to fit the same circle as a three figure one. The number also shrinks
/// on its own as a last resort, so nothing ever clips.
struct CalorieRing: View {
    var eaten: Double
    var target: Double
    var lineWidth: CGFloat = 14
    /// Animates the fill up from empty the first time the ring appears.
    @State private var shown: Double = 0

    private var fraction: Double { target > 0 ? min(eaten / target, 1) : 0 }
    private var over: Bool { eaten > target && target > 0 }
    private var remaining: Int { Int((target - eaten).rounded()) }
    private var headline: String { "\(abs(remaining))" }
    private var caption: String { over ? "over" : "left" }
    private var tint: Color { over ? .red : .calories }

    var body: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.width, geo.size.height)
            let stroke = min(lineWidth, diameter * 0.13)
            // Keep the text clear of the stroke and of the curve on either side.
            let inner = diameter - stroke * 2 - diameter * 0.16

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(tint, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: diameter * 0.01) {
                    Text(headline)
                        .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(diameter * -0.008)     // large numerals read better pulled in
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .foregroundStyle(over ? Color.red : Color.primary)
                    Text(caption)
                        .font(.system(size: max(10, diameter * 0.095), weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(over ? Color.red : Color.secondary)
                }
                .frame(width: inner)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.6, dampingFraction: 1), value: shown)
        .onAppear { shown = fraction }
        .onChange(of: fraction) { _, new in shown = new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(over
            ? "\(abs(remaining)) calories over your target of \(Int(target))"
            : "\(abs(remaining)) calories left of \(Int(target))")
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
                Text("/ \(Int(target))g")
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
    var gramsString: String { "\(Int(self.rounded()))g" }
}

extension Date {
    var dayTitle: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
