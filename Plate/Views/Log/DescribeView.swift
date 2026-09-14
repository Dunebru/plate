import SwiftUI

/// Type what you ate. Good for meals with no photo, or things the camera cannot see.
struct DescribeView: View {
    var onResult: (AnalyzedMeal) -> Void
    @State private var text = ""
    @State private var analyzing = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Two scrambled eggs, a slice of sourdough with butter, black coffee", text: $text, axis: .vertical)
                .lineLimit(4...10)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focused)
                .disabled(analyzing)
            Text("Include amounts when you know them. \"A big bowl\" and \"cooked in oil\" both change the number.")
                .font(.footnote).foregroundStyle(.secondary)
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            Button {
                analyze()
            } label: {
                HStack {
                    if analyzing { ProgressView().tint(.white) }
                    Text(analyzing ? "Estimating" : "Estimate").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(text.trimmingCharacters(in: .whitespaces).count < 3 || analyzing)
            Spacer()
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Describe a meal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func analyze() {
        analyzing = true
        error = nil
        Task {
            do {
                let meal = try await FoodAnalyzer().analyzeDescription(text)
                analyzing = false
                onResult(meal)
            } catch {
                analyzing = false
                self.error = error.localizedDescription
            }
        }
    }
}
