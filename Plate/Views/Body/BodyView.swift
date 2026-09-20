import SwiftUI
import SwiftData
import PhotosUI

/// Composition, tape measurements, photos, and what can actually be done about a specific area.
///
/// Weight is one number and a bad one on its own. This tab is the honest version: body fat with the
/// confidence attached, lean and fat mass separately, and measurements that move before the scale does.
struct BodyView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]

    @State private var measuring = false
    @State private var statInfo: BodyStatInfo?
    @State private var trendField: BodyMeasurement.Field?
    @State private var planArea: BodyArea?
    @State private var pickingAreas = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoSaves = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    compositionSection
                    tilesSection
                    measurementsSection
                    measureButton
                    photosSection
                    focusSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body")
            .sheet(isPresented: $measuring) { MeasureSheet(profile: profile) }
            .sheet(item: $statInfo) { info in BodyStatExplainerSheet(info: info) }
            .sheet(item: $trendField) { field in
                BodyMeasureTrendSheet(field: field, entries: measurements,
                                      units: profile.units, areaGoal: profile.areaGoal)
            }
            .sheet(item: $planArea) { area in
                NavigationStack {
                    FocusPlanView(area: area, profile: profile)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { planArea = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $pickingAreas) { BodyFocusPickerSheet(profile: profile) }
            .onChange(of: photoItem) { _, item in addPhoto(item) }
            .sensoryFeedback(.success, trigger: photoSaves)
        }
    }

    // MARK: Composition

    @ViewBuilder private var compositionSection: some View {
        if let estimate = profile.bodyFat {
            BodyCompositionHeader(estimate: estimate, sex: profile.sex)
        } else {
            compositionInvite
        }
    }

    private var compositionInvite: some View {
        let needed = profile.sex == .female ? ["neck", "waist", "hips"] : ["neck", "waist"]
        return VStack(spacing: 12) {
            Image(systemName: "ruler")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Three numbers and a tape measure")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Your \(BodyText.list(needed)), with the height you already gave, estimate body fat within about three to four points of a DEXA scan. It takes two minutes and costs nothing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Take measurements") { measuring = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }

    // MARK: Stat tiles

    /// Every number the composition gives, minus the ones whose inputs are missing.
    private var stats: [BodyStatInfo] {
        var out: [BodyStatInfo] = []
        if let estimate = profile.bodyFat {
            let lean = BodyComposition.leanMassKg(weightKg: profile.weightKg, bodyFatPercent: estimate.percent)
            let fat = BodyComposition.fatMassKg(weightKg: profile.weightKg, bodyFatPercent: estimate.percent)
            out.append(BodyStatInfo(
                title: "Lean mass",
                value: Units.weightString(lean, profile.units),
                caption: "Muscle, bone, organs, water",
                symbol: "figure.arms.open",
                tint: .accentColor,
                meaning: "Everything you are carrying that is not fat. While you are losing weight this is the number to hold steady, and high protein plus lifting is how you hold it.",
                versusBMI: "BMI cannot see this. It treats a kilogram of muscle and a kilogram of fat as the same thing, so two people at the same BMI can be in completely different shape."))
            out.append(BodyStatInfo(
                title: "Fat mass",
                value: Units.weightString(fat, profile.units),
                caption: "The part you are trying to change",
                symbol: "drop.fill",
                tint: .fat,
                meaning: "The weight of the fat itself. Watching this next to lean mass is the only way to tell whether a lower number on the scale was fat or muscle.",
                versusBMI: "A scale weight or a BMI falling tells you nothing about which of the two left. Splitting the weight in two does."))
            let ffmi = BodyComposition.normalizedFFMI(leanMassKg: lean, heightCm: profile.heightCm)
            out.append(BodyStatInfo(
                title: "FFMI",
                value: String(format: "%.1f", ffmi),
                caption: BodyComposition.ffmiLabel(ffmi, sex: profile.sex),
                symbol: "dumbbell.fill",
                tint: .protein,
                meaning: "Fat free mass index: your lean mass for your height, adjusted to a 1.8 m frame so heights can be compared. Drug free lifters usually top out near 25 for men and 22 for women.",
                versusBMI: "It is BMI's useful cousin. Same idea, but built on lean mass instead of total weight, which is why it does not call a muscular person overweight."))
        }
        if let waist = latestWaistCm,
           let ratio = BodyComposition.waistToHeight(waistCm: waist, heightCm: profile.heightCm) {
            out.append(BodyStatInfo(
                title: "Waist to height",
                value: String(format: "%.2f", ratio),
                caption: BodyComposition.waistToHeightLabel(ratio),
                symbol: "figure.core.training",
                tint: .carbs,
                meaning: "Your waist divided by your height. Under 0.5 is the target, at any height and for either sex, and one tape measure is all it needs.",
                versusBMI: "It picks up the fat stored around your organs, which is the fat that moves health markers. BMI misses it, because two people at the same BMI can have very different waists."))
        }
        return out
    }

    /// The waist the profile is carrying, or the last one that was measured.
    private var latestWaistCm: Double? {
        profile.waistCm ?? measurements.compactMap(\.waistCm).last
    }

    @ViewBuilder private var tilesSection: some View {
        let items = stats
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(items) { info in
                    BodyStatTile(info: info) { statInfo = info }
                }
            }
        }
    }

    // MARK: Measurements

    /// Fields with at least one logged value, newest value first and the change since the first one.
    private var loggedFields: [(field: BodyMeasurement.Field, latest: Double, change: Double?)] {
        BodyMeasurement.fields.compactMap { field in
            let values = measurements.compactMap { $0.value(for: field.key) }
            guard let latest = values.last else { return nil }
            // A change too small to show as a tenth is noise, not progress.
            let moved = values.count >= 2 ? latest - values[0] : 0
            return (field, latest, abs(moved) >= 0.05 ? moved : nil)
        }
    }

    private var measurementsSection: some View {
        let rows = loggedFields
        return VStack(spacing: 10) {
            BodySectionHeader(title: "Measurements")
            if rows.isEmpty {
                EmptyStateView(symbol: "ruler",
                               title: "Nothing measured yet",
                               message: "The tape notices a smaller waist weeks before the scale agrees. One session is enough to start.")
                    .card()
            } else {
                ForEach(rows, id: \.field.key) { row in
                    BodyMeasureRow(field: row.field, latestCm: row.latest, changeCm: row.change,
                                   units: profile.units, areaGoal: profile.areaGoal) {
                        trendField = row.field
                    }
                }
            }
        }
    }

    private var measureButton: some View {
        Button {
            measuring = true
        } label: {
            Label("New measurement", systemImage: "ruler")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }

    // MARK: Photos

    private var photosSection: some View {
        let photos = Array(measurements.filter { $0.photoData != nil }.reversed())
        return VStack(alignment: .leading, spacing: 10) {
            BodySectionHeader(title: "Progress photos")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) { addPhotoTile }
                        .accessibilityLabel("Add progress photo")
                    ForEach(photos) { entry in
                        if let data = entry.photoData, let image = UIImage(data: data) {
                            BodyPhotoCard(image: image, date: entry.date)
                                .contextMenu {
                                    Button("Delete photo", systemImage: "trash", role: .destructive) {
                                        deletePhoto(entry)
                                    }
                                }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text(photos.isEmpty
                 ? "Same light, same pose, every four weeks. Photos stay on this iPhone and are never uploaded."
                 : "Photos stay on this iPhone and are never uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addPhotoTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text("Add")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 108, height: 140)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Focus areas

    /// Duplicates cannot come out of the picker, but the stored list is text, so it is cheap to be sure.
    private var focusAreas: [BodyArea] {
        var seen = Set<BodyArea>()
        return profile.focusAreas.filter { seen.insert($0).inserted }
    }

    private var focusSection: some View {
        let areas = focusAreas
        return VStack(alignment: .leading, spacing: 10) {
            if areas.isEmpty {
                BodySectionHeader(title: "Focus areas")
                focusInvite
            } else {
                BodySectionHeader(title: "Focus areas", actionLabel: "Edit") { pickingAreas = true }
                ForEach(areas) { area in
                    Button {
                        planArea = area
                    } label: {
                        BodyFocusCard(area: area, headline: plan(for: area).headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(area.label). \(plan(for: area).headline)")
                    .accessibilityHint("Opens the plan for this area")
                }
            }
        }
    }

    private var focusInvite: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick the parts you care about")
                .font(.subheadline.weight(.semibold))
            Text("Plate will tell you what genuinely changes each one, what only overall fat loss can do, and roughly how long it takes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose areas") { pickingAreas = true }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func plan(for area: BodyArea) -> FocusGuidance.Plan {
        FocusGuidance.plan(for: area, goal: profile.areaGoal, sex: profile.sex)
    }

    // MARK: Photo handling

    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            guard let raw, let shrunk = BodyPhoto.shrink(raw) else { return }
            let entry = BodyMeasurement(date: Date())
            entry.photoData = shrunk
            context.insert(entry)
            photoSaves += 1
        }
    }

    private func deletePhoto(_ entry: BodyMeasurement) {
        entry.photoData = nil
        // A session that only ever held a photo has nothing left to show, so it goes with it.
        if entry.isEmpty, entry.note.isEmpty {
            context.delete(entry)
        }
    }
}
