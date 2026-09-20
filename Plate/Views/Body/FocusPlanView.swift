import SwiftUI

/// What can and cannot be done about one part of the body.
///
/// The order is deliberate: the honest paragraph comes before the training list, so nobody reads a
/// list of exercises and believes it burns the fat sitting on top of the muscle.
struct FocusPlanView: View {
    var area: BodyArea
    var profile: Profile

    @State private var showSources = false
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 44
    @ScaledMetric(relativeTo: .footnote) private var stepSize: CGFloat = 26

    private var plan: FocusGuidance.Plan {
        FocusGuidance.plan(for: area, goal: profile.areaGoal, sex: profile.sex)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                BodyCallout(symbol: "hand.raised.fill", title: "The honest version", text: plan.truth)
                training
                BodyInfoCard(symbol: "fork.knife", title: "Eating", text: plan.nutrition)
                BodyInfoCard(symbol: "ruler", title: "How to measure it", text: plan.measure)
                BodyInfoCard(symbol: "calendar", title: "How long it takes", text: plan.weeks,
                             footnote: "That assumes most weeks go to plan, not every week.")
                if let caution = plan.caution {
                    BodyCallout(symbol: "exclamationmark.triangle.fill", title: "Worth knowing",
                                text: caution, tint: .orange)
                }
                sourcesLink
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(area.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSources) {
            NavigationStack { SourcesView() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: area.symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(area.label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(plan.headline)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var training: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training that works", systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            ForEach(Array(plan.training.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: stepSize, height: stepSize)
                        .background(Color.accentColor.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                    Text(step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(step)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var sourcesLink: some View {
        Button {
            showSources = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "book")
                    .foregroundStyle(Color.accentColor)
                Text("Where these numbers come from")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Where these numbers come from")
    }
}
