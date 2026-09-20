import SwiftUI

// MARK: Motion

extension Animation {
    /// One spring for the whole flow, so every screen and every selection feels like the same object.
    static let flow: Animation = .spring(response: 0.35, dampingFraction: 1.0)
    static let press: Animation = .spring(response: 0.25, dampingFraction: 0.85)
}

// MARK: Page shell

/// One question per screen. Scrolls only when the answer does not fit, which on a tall phone is rare.
struct OnboardingPage<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, _ subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: Selection chrome

/// Tinted fill and a ring when chosen, a quiet card when not. Shared so every choice on every screen
/// reads the same way.
struct SelectionBackground: View {
    var selected: Bool
    var cornerRadius: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.13) : Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.05),
                                  lineWidth: selected ? 2 : 1)
            }
            .shadow(color: .black.opacity(selected ? 0.07 : 0.03), radius: selected ? 9 : 4, y: 2)
    }
}

struct SelectionMark: View {
    var selected: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.3))
            .symbolEffect(.bounce, value: selected)
    }
}

/// Buttons that give a little under the thumb.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.press, value: configuration.isPressed)
    }
}

/// The footer button. Tall, rounded, one accent.
struct FlowButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.accentColor.opacity(0.12))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.press, value: configuration.isPressed)
    }
}

// MARK: Choices

/// A full width answer. Symbol and detail are both optional so the same row works for a one word
/// answer and for a paragraph.
struct ChoiceRow: View {
    var symbol: String? = nil
    var label: String
    var detail: String? = nil
    var selected: Bool
    var emphasis: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(emphasis ? .title2 : .title3)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .frame(width: emphasis ? 38 : 30)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(emphasis ? .system(.title3, design: .rounded).weight(.bold) : .body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                SelectionMark(selected: selected)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, emphasis ? 16 : 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SelectionBackground(selected: selected))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A card for a grid of short answers.
struct ChoiceCard: View {
    var symbol: String
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(height: 26)
                Text(label)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 6)
            .background(SelectionBackground(selected: selected, cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A pill. Used wherever the answers are short and there are a lot of them.
struct ChoiceChip: View {
    var label: String
    var symbol: String? = nil
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.semibold))
                }
                Text(label).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                Capsule()
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground))
                    .overlay {
                        Capsule().strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.05),
                                               lineWidth: selected ? 1.5 : 1)
                    }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A switch with room to explain itself.
struct ToggleCard: View {
    var symbol: String
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Toggle(title, isOn: $isOn)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(SelectionBackground(selected: isOn))
    }
}

// MARK: Readouts

/// The answer, in the size it deserves. Rounded monospaced digits so it does not jitter as it changes.
struct BigNumber: View {
    var value: String
    var caption: String? = nil
    var size: CGFloat = 46

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A quiet line of guidance. Tinted when it is a caution.
struct Callout: View {
    var symbol: String
    var text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.footnote)
                .foregroundStyle(tint == .secondary ? Color.secondary : tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint == .secondary ? Color(.secondarySystemGroupedBackground) : tint.opacity(0.12))
        }
    }
}

struct StatBlock: View {
    var title: String
    var value: String
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One macro as a ring. The fill is the share of the day's calories, which is the honest thing to
/// compare across three numbers measured in different units.
struct MacroRing: View {
    var name: String
    var grams: Int
    var share: Double
    var color: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                Circle()
                    .trim(from: 0, to: min(max(share, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.9), value: share)
                Text("\(grams)")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            Text(name).font(.caption.weight(.semibold))
            Text("\(Int((share * 100).rounded()))% of calories")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(grams) grams, \(Int((share * 100).rounded())) percent of calories")
    }
}

// MARK: Progress

struct FlowProgressBar: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.45, dampingFraction: 1.0), value: progress)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// A bar that sweeps while the plan is worked out. Decoration only, the arithmetic is instant.
struct ShimmerBar: View {
    var width: CGFloat
    @State private var phase: CGFloat = -1.2

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: 9)
            .overlay {
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color.accentColor.opacity(0.4), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * 0.6)
                    .offset(x: phase * width)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1.2 }
            }
            .accessibilityHidden(true)
    }
}

/// The wait before the plan. Long enough to read one line, short enough not to feel like a stall.
struct GeneratingView: View {
    var lines: [String]
    var onDone: () -> Void

    @State private var index = 0
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.14), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 146, height: 146)

            Text(lines.isEmpty ? "" : lines[min(index, lines.count - 1)])
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .id(index)
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 9) {
                ShimmerBar(width: 210)
                ShimmerBar(width: 156)
                ShimmerBar(width: 184)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !lines.isEmpty else { onDone(); return }
            for i in lines.indices {
                withAnimation(.flow) {
                    index = i
                    progress = Double(i + 1) / Double(lines.count)
                }
                try? await Task.sleep(for: .milliseconds(680))
            }
            onDone()
        }
    }
}

// MARK: Layout

/// Chips wrap because they hold user text, which no fixed grid can size.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, limit), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            view.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: Height and weight

/// Wheels rather than a keyboard: fewer taps, and nobody types their height wrong.
struct HeightWheels: View {
    @Bindable var profile: Profile

    private var cm: Binding<Int> {
        Binding(get: { Int(profile.heightCm.rounded()) },
                set: { profile.heightCm = Double($0) })
    }
    private var feet: Binding<Int> {
        Binding(get: { Units.cmToFeetInches(profile.heightCm).0 },
                set: { profile.heightCm = Units.feetInchesToCm($0, Units.cmToFeetInches(profile.heightCm).1) })
    }
    private var inches: Binding<Int> {
        Binding(get: { Units.cmToFeetInches(profile.heightCm).1 },
                set: { profile.heightCm = Units.feetInchesToCm(Units.cmToFeetInches(profile.heightCm).0, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Height").font(.subheadline.weight(.semibold))
                Spacer()
                Text(Units.heightString(profile.heightCm, profile.units))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 4)
            if profile.units == .metric {
                Picker("Height in centimeters", selection: cm) {
                    ForEach(120...230, id: \.self) { Text("\($0) cm").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 132)
                .clipped()
            } else {
                HStack(spacing: 0) {
                    Picker("Feet", selection: feet) {
                        ForEach(3...7, id: \.self) { Text("\($0) ft").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    Picker("Inches", selection: inches) {
                        ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
                .frame(height: 132)
            }
        }
        .padding(10)
        .background(SelectionBackground(selected: false, cornerRadius: 20))
    }
}

struct WeightWheel: View {
    @Bindable var profile: Profile
    var title: String = "Weight"

    private var kg: Binding<Int> {
        Binding(get: { Int(profile.weightKg.rounded()) },
                set: { profile.weightKg = Double($0) })
    }
    private var pounds: Binding<Int> {
        Binding(get: { Int(Units.kgToLb(profile.weightKg).rounded()) },
                set: { profile.weightKg = Units.lbToKg(Double($0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Units.weightString(profile.weightKg, profile.units, decimals: 0))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 4)
            if profile.units == .metric {
                Picker("Weight in kilograms", selection: kg) {
                    ForEach(30...250, id: \.self) { Text("\($0) kg").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 132)
                .clipped()
            } else {
                Picker("Weight in pounds", selection: pounds) {
                    ForEach(66...550, id: \.self) { Text("\($0) lb").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 132)
                .clipped()
            }
        }
        .padding(10)
        .background(SelectionBackground(selected: false, cornerRadius: 20))
    }
}

/// One tape measurement, with the tip attached. A waist measured in the wrong place is worse than no
/// waist at all, so the instruction is never hidden behind a tap. The number itself is the shared
/// LengthField, so onboarding and the body screens convert inches the same way.
struct TapeField: View {
    var field: BodyMeasurement.Field
    @Binding var cm: Double?
    var units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Image(systemName: field.symbol)
                    .font(.title3)
                    .foregroundStyle(cm == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 26)
                LengthField(title: field.label, cm: $cm, units: units)
                    .font(.body.weight(.semibold))
            }
            Text(field.tip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(SelectionBackground(selected: cm != nil))
    }
}
