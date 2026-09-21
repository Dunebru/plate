import SwiftUI
import SwiftData

/// The plus button menu. Each option pushes its own flow and ends in ResultEditorView.
struct AddSheet: View {
    var profile: Profile
    var day: Date
    /// Opened straight onto one flow, for the Action Button and Siri. The menu is still behind it,
    /// so going back lands where it would have.
    var initialRoute: Route? = nil
    @Environment(\.dismiss) private var dismiss
    @Query private var corrections: [FoodCorrection]
    @State private var path: [Route] = []
    @State private var opened = false
    @State private var result: AnalyzedMeal?
    @State private var resultImage: UIImage?

    enum Route: Hashable { case camera(CameraMode), barcode, describe, saved, search, repeatMeal, quickAdd }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    option("Scan food", "camera.fill", .camera(.food))
                    option("Barcode", "barcode.viewfinder", .barcode)
                }
                HStack(spacing: 12) {
                    option("Food label", "doc.text.viewfinder", .camera(.label))
                    option("Describe", "text.bubble.fill", .describe)
                }
                HStack(spacing: 12) {
                    option("Saved foods", "bookmark.fill", .saved)
                    option("Search", "magnifyingglass", .search)
                }
                HStack(spacing: 12) {
                    option("Log it again", "clock.arrow.circlepath", .repeatMeal)
                    option("Quick add", "number", .quickAdd)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .camera(let mode): CameraFlowView(mode: mode, context: analyzerContext) { meal, image in present(meal, image) }
                case .barcode: BarcodeFlowView { meal, image in present(meal, image) }
                case .describe: DescribeView(context: analyzerContext) { meal in present(meal, nil) }
                case .saved: SavedFoodsView { meal in present(meal, nil) }
                case .search: SearchFoodsView { meal in present(meal, nil) }
                case .repeatMeal: RepeatMealView { meal in present(meal, nil) }
                case .quickAdd: QuickAddView { meal in present(meal, nil) }
                }
            }
            .sheet(item: $result) { meal in
                ResultEditorView(meal: meal, image: resultImage, profile: profile, day: day) { dismiss() }
            }
            .onAppear {
                guard !opened else { return }
                opened = true
                #if DEBUG
                // Opens the review editor on a canned estimate, so the correction loop can be walked
                // without spending a scan. The numbers are deliberately wrong in the usual direction:
                // a reference sized chicken breast where a large one was eaten.
                if CommandLine.arguments.contains("--fake-estimate") {
                    present(Self.cannedEstimate, nil)
                    return
                }
                #endif
                guard let initialRoute else { return }
                path = [initialRoute]
            }
        }
        .presentationDetents([.large])
    }

    /// Carries what past corrections taught, so a scan starts from this person's portions rather
    /// than from a reference serving.
    private var analyzerContext: FoodAnalyzer.Context {
        FoodAnalyzer.Context(profile: profile, corrections: corrections)
    }

    #if DEBUG
    static let cannedEstimate = AnalyzedMeal(
        name: "Chicken and rice",
        items: [
            AnalyzedMeal.Item(name: "Chicken breast", quantity: 1, unit: "serving", gramsPerUnit: 120,
                              base: Nutrients(calories: 198, protein: 37, carbs: 0, fat: 4.3,
                                              fiber: 0, sugar: 0, sodium: 89),
                              confidence: 0.7),
            AnalyzedMeal.Item(name: "White rice", quantity: 1, unit: "cup", gramsPerUnit: 158,
                              base: Nutrients(calories: 205, protein: 4.3, carbs: 45, fat: 0.4,
                                              fiber: 0.6, sugar: 0, sodium: 2),
                              confidence: 0.7),
        ],
        notes: "Portions estimated from the photo.",
        healthScore: 8,
        confidence: 0.7,
        source: .photo)
    #endif

    private func present(_ meal: AnalyzedMeal, _ image: UIImage?) {
        resultImage = image
        result = meal
    }

    private func option(_ title: String, _ symbol: String, _ route: Route) -> some View {
        Button { path.append(route) } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.title).foregroundStyle(Color.accentColor)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

extension AnalyzedMeal: Identifiable {
    var id: String { name + String(items.count) + String(totals.calories) }
}
