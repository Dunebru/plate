import SwiftUI

/// Text search over Open Food Facts for packaged foods.
struct SearchFoodsView: View {
    var onResult: (AnalyzedMeal) -> Void
    @State private var query = ""
    @State private var results: [OpenFoodFacts.Product] = []
    @State private var searching = false
    @State private var searched = false
    @State private var error: String?

    var body: some View {
        List {
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let error {
                Text(error).foregroundStyle(.red)
            } else if searched && results.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "No matches", message: "Try a brand name, or describe the meal instead.")
            }
            ForEach(results) { product in
                NavigationLink {
                    ProductServingView(product: product, onResult: onResult)
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: product.imageURL) { img in img.resizable().scaledToFit() } placeholder: { Color(.tertiarySystemFill) }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text([product.brand, "\(Int(product.per100g.calories)) kcal per 100 g"].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search packaged foods")
        .onSubmit(of: .search) { search() }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        searching = true
        error = nil
        Task {
            do {
                results = try await OpenFoodFacts.search(q)
            } catch {
                self.error = error.localizedDescription
            }
            searching = false
            searched = true
        }
    }
}
