import SwiftUI
import UIKit
import Charts

// MARK: Small shared pieces

/// Section title with an optional action on the right, so sections read the same everywhere.
struct BodySectionHeader: View {
    var title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer(minLength: 8)
            if let actionLabel, let action {
                Button(actionLabel, action: action).font(.subheadline)
            }
        }
        .padding(.top, 6)
    }
}

/// A tinted panel for a paragraph that should not be skimmed past.
struct BodyCallout: View {
    var symbol: String
    var title: String?
    var text: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if let title {
                    Text(title).font(.subheadline.weight(.semibold))
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One labeled paragraph in a card. Used for the parts of a focus plan.
struct BodyInfoCard: View {
    var symbol: String
    var title: String
    var text: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

enum BodyText {
    /// "neck", "neck and waist", "neck, waist and hips".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }

    static func lengthUnit(_ units: UnitSystem) -> String { units == .metric ? "cm" : "in" }
    static func weightUnit(_ units: UnitSystem) -> String { units == .metric ? "kg" : "lb" }
    static func spokenLengthUnit(_ units: UnitSystem) -> String { units == .metric ? "centimeters" : "inches" }
    static func spokenWeightUnit(_ units: UnitSystem) -> String { units == .metric ? "kilograms" : "pounds" }

    static func lengthChange(_ cm: Double, _ units: UnitSystem) -> String {
        let shown = units == .metric ? cm : Units.cmToInches(cm)
        return String(format: "%+.1f %@", shown, lengthUnit(units))
    }
}

/// Whether a change in a tape measurement is the direction the user asked for.
/// Nil means it depends on things the app cannot know, so the change is shown plainly.
enum BodyDirection {
    static func isWanted(change: Double, key: String, areaGoal: AreaGoal) -> Bool? {
        guard abs(change) > 0.05 else { return nil }
        switch key {
        case "waist":
            return change < 0
        case "arm", "chest", "thigh", "calf":
            switch areaGoal {
            case .leaner: return change < 0
            case .bigger: return change > 0
            case .both: return nil
            }
        default:
            return nil
        }
    }

    static func color(change: Double, key: String, areaGoal: AreaGoal) -> Color {
        isWanted(change: change, key: key, areaGoal: areaGoal) == true ? Color.reached : .secondary
    }
}

// MARK: Body fat band scale

/// The body fat bands side by side with a marker where the user sits.
///
/// Segments are equal width rather than proportional to their range, because the bands people care
/// about most are the narrow ones and a proportional scale squeezes them into nothing.
struct BodyBandScale: View {
    var percent: Double
    var sex: Sex
    var showsLabels: Bool = true

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 14

    private var bands: [BodyComposition.Band] { BodyComposition.bands(for: sex) }
    private var currentIndex: Int { BodyBandScale.bandIndex(for: percent, sex: sex) }

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                bar
                    .overlay(alignment: .leading) {
                        marker
                            .offset(x: markerOffset(in: geo.size.width))
                            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: percent)
                    }
            }
            .frame(height: barHeight + 10)
            if showsLabels { labels }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body fat bands")
        .accessibilityValue(spokenValue)
    }

    private var bar: some View {
        HStack(spacing: 2) {
            ForEach(Array(bands.enumerated()), id: \.element.id) { index, _ in
                Capsule()
                    .fill(BodyBandScale.color(for: index).opacity(index == currentIndex ? 1 : 0.35))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight)
        .frame(maxHeight: .infinity)
    }

    private var marker: some View {
        ZStack {
            Capsule()
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: 9, height: barHeight + 10)
            Capsule()
                .fill(Color.primary)
                .frame(width: 3.5, height: barHeight + 6)
        }
    }

    private var labels: some View {
        HStack(spacing: 2) {
            ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                Text(band.name)
                    .font(.caption2.weight(index == currentIndex ? .bold : .regular))
                    .foregroundStyle(index == currentIndex ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func markerOffset(in width: CGFloat) -> CGFloat {
        let raw = width * CGFloat(BodyBandScale.fraction(for: percent, sex: sex)) - 4.5
        return min(max(raw, 0), max(width - 9, 0))
    }

    private var spokenValue: String {
        let all = bands
            .map { "\($0.name), \(Int($0.range.lowerBound)) to \(Int($0.range.upperBound)) percent" }
            .joined(separator: ". ")
        let current = bands.indices.contains(currentIndex) ? bands[currentIndex].name : ""
        return String(format: "%.1f percent, in the %@ band. All bands: %@", percent, current, all)
    }

    /// A calm ramp from blue through green to orange. System colors, so dark mode is handled.
    static func color(for index: Int) -> Color {
        let ramp: [Color] = [.blue, .teal, .green, .yellow, .orange]
        return ramp[min(max(index, 0), ramp.count - 1)]
    }

    /// The band a percentage sits in. `BodyComposition.band(for:)` falls back to the last band when a
    /// value lands in one of the small gaps between the published ranges, which would read as a much
    /// worse number than it is, so a gap resolves to the band the value is on its way into.
    static func band(for percent: Double, sex: Sex) -> BodyComposition.Band? {
        if let exact = BodyComposition.band(for: percent, sex: sex), exact.range.contains(percent) { return exact }
        let bands = BodyComposition.bands(for: sex)
        guard !bands.isEmpty else { return nil }
        return bands[bandIndex(for: percent, sex: sex)]
    }

    /// The band a percentage belongs to. The published bands leave small gaps between them, so this
    /// picks the first band the value has not passed rather than asking for an exact match.
    static func bandIndex(for percent: Double, sex: Sex) -> Int {
        let bands = BodyComposition.bands(for: sex)
        if let index = bands.firstIndex(where: { percent <= $0.range.upperBound }) { return index }
        return max(bands.count - 1, 0)
    }

    /// Where the marker sits, 0 at the left edge of the scale and 1 at the right.
    static func fraction(for percent: Double, sex: Sex) -> Double {
        let bands = BodyComposition.bands(for: sex)
        guard !bands.isEmpty else { return 0 }
        let slice = 1.0 / Double(bands.count)
        let index = bandIndex(for: percent, sex: sex)
        let band = bands[index]
        let span = band.range.upperBound - band.range.lowerBound
        let inner = span > 0 ? (percent - band.range.lowerBound) / span : 0.5
        return (Double(index) + min(max(inner, 0), 1)) * slice
    }
}

// MARK: Composition header

/// The screen's centerpiece: one number, how much to trust it, and where it sits.
struct BodyCompositionHeader: View {
    var estimate: BodyComposition.Estimate
    var sex: Sex

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 54

    private var band: BodyComposition.Band? { BodyBandScale.band(for: estimate.percent, sex: sex) }
    private var tint: Color { BodyBandScale.color(for: BodyBandScale.bandIndex(for: estimate.percent, sex: sex)) }

    private var sourceSymbol: String {
        switch estimate.source {
        case .tape: return "ruler"
        case .entered: return "pencil"
        case .estimated: return "chart.bar"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Body fat")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", estimate.percent))
                            .font(.system(size: numberSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("%")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let band { bandChip(band) }
            }
            BodyBandScale(percent: estimate.percent, sex: sex)
            VStack(alignment: .leading, spacing: 4) {
                Label(estimate.source.label, systemImage: sourceSymbol)
                    .font(.footnote.weight(.semibold))
                Text(estimate.source.confidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let band {
                    Text(band.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // Same metrics as .card(), with a wash of the band color. This is the card the owner opens
        // the app for, so it earns the extra paint.
        .padding(16)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                RadialGradient(colors: [tint.opacity(0.16), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 230)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func bandChip(_ band: BodyComposition.Band) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(band.name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.18), in: Capsule())
        .accessibilityLabel("\(band.name) band")
    }
}

// MARK: Stat tiles

/// One number worth knowing, plus the explainer behind it.
struct BodyStatInfo: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var caption: String?
    var symbol: String
    var tint: Color
    var meaning: String
    var versusBMI: String
}

struct BodyStatTile: View {
    var info: BodyStatInfo
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: info.symbol)
                        .font(.caption)
                        .foregroundStyle(info.tint)
                    Text(info.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(info.value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption = info.caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Explains what this number means")
    }
}

struct BodyStatExplainerSheet: View {
    var info: BodyStatInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: info.symbol)
                            .font(.headline)
                            .foregroundStyle(info.tint)
                            .accessibilityHidden(true)
                        Text(info.value)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                    }
                    if let caption = info.caption {
                        Text(caption)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(info.meaning)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    BodyCallout(symbol: "scalemass", title: "Why it beats BMI", text: info.versusBMI, tint: info.tint)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: Measurement rows and charts

struct BodyMeasureRow: View {
    var field: BodyMeasurement.Field
    var latestCm: Double
    var changeCm: Double?
    var units: UnitSystem
    var areaGoal: AreaGoal
    var action: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 34

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: field.symbol)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(field.label)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Units.lengthString(latestCm, units))
                        .font(.system(.headline, design: .rounded))
                        .monospacedDigit()
                    if let changeCm {
                        HStack(spacing: 2) {
                            Image(systemName: changeCm < 0 ? "arrow.down" : "arrow.up")
                                .font(.caption2.weight(.bold))
                            Text(BodyText.lengthChange(changeCm, units))
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(BodyDirection.color(change: changeCm, key: field.key, areaGoal: areaGoal))
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Shows the chart over time")
    }

    private var spokenLabel: String {
        let shown = units == .metric ? latestCm : Units.cmToInches(latestCm)
        var text = String(format: "%@, %.1f %@", field.label, shown, BodyText.spokenLengthUnit(units))
        if let changeCm {
            let delta = abs(units == .metric ? changeCm : Units.cmToInches(changeCm))
            let word = changeCm < 0 ? "down" : "up"
            text += String(format: ", %@ %.1f %@ since your first measurement", word, delta, BodyText.spokenLengthUnit(units))
        }
        return text
    }
}

/// One measurement over time, with the history under the chart.
struct BodyMeasureTrendSheet: View {
    var field: BodyMeasurement.Field
    var entries: [BodyMeasurement]
    var units: UnitSystem
    var areaGoal: AreaGoal

    @Environment(\.dismiss) private var dismiss

    struct Point: Identifiable {
        var id: Int
        var date: Date
        var value: Double
    }

    private var points: [Point] {
        entries
            .compactMap { entry in entry.value(for: field.key).map { (entry.date, display($0)) } }
            .enumerated()
            .map { Point(id: $0.offset, date: $0.element.0, value: $0.element.1) }
    }

    private var rows: [(point: Point, change: Double?)] {
        let all = points
        let mapped = all.enumerated().map { index, point in
            (point: point, change: index > 0 ? point.value - all[index - 1].value : nil)
        }
        return Array(mapped.reversed())
    }

    private var unitWord: String { BodyText.lengthUnit(units) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if points.count >= 2 {
                        chart
                    } else {
                        Text("One measurement so far. Log another in a couple of weeks and the trend appears here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let summary { Text(summary).font(.footnote).foregroundStyle(.secondary) }
                }
                if !rows.isEmpty {
                    Section("History") {
                        ForEach(rows, id: \.point.id) { row in
                            HStack {
                                Text(row.point.date.formatted(.dateTime.year().month(.abbreviated).day()))
                                    .font(.subheadline)
                                Spacer()
                                if let change = row.change, abs(change) > 0.05 {
                                    Text(String(format: "%+.1f", change))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Text(String(format: "%.1f %@", row.point.value, unitWord))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Text(field.tip).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("How to measure it")
                }
            }
            .navigationTitle(field.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date), y: .value(unitWord, point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value(unitWord, point.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Date", point.date), y: .value(unitWord, point.value))
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(26)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 180)
        .padding(.vertical, 6)
        .accessibilityLabel("\(field.label) over time")
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.25, 1)
        return (low - pad)...(high + pad)
    }

    private var summary: String? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        let change = last.value - first.value
        let word = change < 0 ? "down" : "up"
        return String(format: "%.1f %@ on %@, %.1f %@ now, %@ %.1f %@.",
                      first.value, unitWord,
                      first.date.formatted(.dateTime.month(.abbreviated).day()),
                      last.value, unitWord,
                      word, abs(change), unitWord)
    }

    private func display(_ cm: Double) -> Double {
        units == .metric ? cm : Units.cmToInches(cm)
    }
}

// MARK: Entry field

/// A number in the user's units that stays empty until something is typed, because a measurement
/// nobody took is not the same as a zero.
struct BodyEntryField: View {
    enum Kind { case length, weight }

    var label: String
    var symbol: String
    var tip: String? = nil
    var kind: Kind = .length
    var units: UnitSystem
    @Binding var value: Double?

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(label)
                Spacer(minLength: 8)
                // No placeholder: the unit already sits to the right of the field.
                TextField("", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 74)
                    .accessibilityLabel("\(label) in \(spokenUnit)")
                Text(unitWord)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let tip {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if text.isEmpty, let value { text = String(format: "%.1f", toDisplay(value)) }
        }
        .onChange(of: text) { _, new in
            guard let typed = Double(new.replacingOccurrences(of: ",", with: ".")), typed > 0 else {
                value = nil
                return
            }
            value = fromDisplay(typed)
        }
    }

    private var unitWord: String {
        kind == .length ? BodyText.lengthUnit(units) : BodyText.weightUnit(units)
    }

    private var spokenUnit: String {
        kind == .length ? BodyText.spokenLengthUnit(units) : BodyText.spokenWeightUnit(units)
    }

    private func toDisplay(_ stored: Double) -> Double {
        guard units == .imperial else { return stored }
        return kind == .length ? Units.cmToInches(stored) : Units.kgToLb(stored)
    }

    private func fromDisplay(_ shown: Double) -> Double {
        guard units == .imperial else { return shown }
        return kind == .length ? Units.inchesToCm(shown) : Units.lbToKg(shown)
    }
}

// MARK: Photos

struct BodyPhotoCard: View {
    var image: UIImage
    var date: Date

    @ScaledMetric(relativeTo: .caption2) private var width: CGFloat = 108

    var body: some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: width * 1.3)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress photo, \(date.formatted(.dateTime.year().month(.wide).day()))")
    }
}

enum BodyPhoto {
    /// Progress photos are only ever looked at on this phone, so a long edge of 1600 points is plenty
    /// and it keeps the store from filling up.
    static func shrink(_ data: Data, maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image.jpegData(compressionQuality: quality) ?? data }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: Focus areas

struct BodyFocusCard: View {
    var area: BodyArea
    var headline: String

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: area.symbol)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(area.label)
                    .font(.subheadline.weight(.semibold))
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
    }
}

/// Picks the areas someone cares about, and whether they want them leaner or bigger.
struct BodyFocusPickerSheet: View {
    @Bindable var profile: Profile
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [BodyArea] = []
    @State private var goal: AreaGoal = .leaner

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(BodyArea.allCases) { area in
                        Button {
                            toggle(area)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: area.symbol)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(area.label).foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if selection.contains(area) {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(selection.contains(area) ? [.isSelected] : [])
                    }
                } header: {
                    Text("Where you want to see a change")
                }
                Section {
                    Picker("What you want there", selection: $goal) {
                        ForEach(AreaGoal.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } footer: {
                    Text(FocusGuidance.spotReductionNote)
                }
            }
            .navigationTitle("Focus areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.focusAreas = selection
                        profile.areaGoal = goal
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selection = profile.focusAreas
                goal = profile.areaGoal
            }
        }
    }

    private func toggle(_ area: BodyArea) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            if let index = selection.firstIndex(of: area) {
                selection.remove(at: index)
            } else {
                selection.append(area)
            }
        }
    }
}
