import SwiftUI

/// Shown once to anyone who finished the old, shorter setup. Their targets still run on a single
/// activity multiplier, which is the roughest part of the whole calculation, so this explains what
/// a few more answers buy and offers to ask them.
struct DeeperSetupView: View {
    @Bindable var profile: Profile
    var start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("Plate can be a lot more accurate")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Your current targets came from four questions. There are more now, and each one sharpens a number rather than padding a form.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        gain("figure.walk.motion", "Movement, counted properly",
                             "Everyday life and training are asked separately, so a desk job with four gym sessions is no longer confused with being on your feet all day.")
                        gain("ruler", "Your body, not a population average",
                             "Three tape measurements give a real body fat number, and your resting burn switches to an equation built on lean mass.")
                        gain("target", "A pace that suits you",
                             "How fast you can safely lose depends on how lean you already are. Plate now knows the difference.")
                        gain("figure.strengthtraining.traditional", "What you actually want to change",
                             "Pick the parts of your body you care about and get honest guidance for each.")
                    }

                    Text("It takes about two minutes. Everything you already logged stays exactly where it is, and every answer is editable afterwards.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                Button(action: start) {
                    Text("Answer the questions")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now") { profile.dismissedDeeperSetup = true }
                    .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func gain(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
