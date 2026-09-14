import SwiftUI
import SwiftData

/// The plus button menu. Each option pushes its own flow and ends in ResultEditorView.
struct AddSheet: View {
    var profile: Profile
    var day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Route] = []
    @State private var result: AnalyzedMeal?
    @State private var resultImage: UIImage?

    enum Route: Hashable { case camera(CameraMode), barcode, describe, saved, search }

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
                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .camera(let mode): CameraFlowView(mode: mode) { meal, image in present(meal, image) }
                case .barcode: BarcodeFlowView { meal, image in present(meal, image) }
                case .describe: DescribeView { meal in present(meal, nil) }
                case .saved: SavedFoodsView { meal in present(meal, nil) }
                case .search: SearchFoodsView { meal in present(meal, nil) }
                }
            }
            .sheet(item: $result) { meal in
                ResultEditorView(meal: meal, image: resultImage, profile: profile, day: day) { dismiss() }
            }
        }
        .presentationDetents([.large])
    }

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
        .buttonStyle(.plain)
    }
}

extension AnalyzedMeal: Identifiable {
    var id: String { name + String(items.count) + String(totals.calories) }
}
