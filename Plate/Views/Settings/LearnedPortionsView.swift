import SwiftData
import SwiftUI

/// What the app has worked out about this person's portions, and a way to take it back.
///
/// Anything that quietly changes an estimate has to be visible and reversible, or it stops being a
/// tool and starts being a mystery. One bad correction, a meal logged for somebody else, a night that
/// was not typical, and the app would go on applying it forever with nothing on screen to explain why.
struct LearnedPortionsView: View {
    @Query(sort: \FoodCorrection.count, order: .reverse) private var corrections: [FoodCorrection]
    @Environment(\.modelContext) private var context
    @State private var confirmClear = false

    var body: some View {
        Group {
            if corrections.isEmpty {
                EmptyStateView(symbol: "brain",
                               title: "Nothing learned yet",
                               message: "When you correct a portion before saving a scan, the difference is remembered and the next scan of that food starts from your size rather than a reference serving.")
            } else {
                List {
                    Section {
                        ForEach(corrections) { correction in
                            row(correction)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(corrections[index]) }
                        }
                    } header: {
                        Text("\(corrections.count) \(corrections.count == 1 ? "food" : "foods")")
                    } footer: {
                        Text("Only the eight most corrected are sent with a scan, so this costs almost nothing. Swipe to forget one.")
                    }

                    Section {
                        Button("Forget everything", role: .destructive) { confirmClear = true }
                    }
                }
            }
        }
        .navigationTitle("Learned portions")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Forget every learned portion?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Forget everything", role: .destructive) {
                for correction in corrections { context.delete(correction) }
            }
        } message: {
            Text("Scans go back to reference servings until you correct them again.")
        }
    }

    private func row(_ correction: FoodCorrection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(correction.displayName.isEmpty ? correction.key : correction.displayName)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                if let grams = correction.grams, grams > 0 {
                    Text("about \(Int(grams.rounded()))g")
                } else {
                    Text("about \(((correction.ratio * 10).rounded() / 10).formatted()) times a reference serving")
                }
                Text("\u{00B7}")
                Text("corrected \(correction.count) \(correction.count == 1 ? "time" : "times")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
