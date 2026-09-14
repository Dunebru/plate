import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [Profile]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.onboarded {
                    MainTabView(profile: profile)
                } else {
                    OnboardingView(profile: profile)
                }
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .onAppear {
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
        }
    }
}

struct MainTabView: View {
    @Bindable var profile: Profile

    var body: some View {
        TabView {
            Tab("Today", systemImage: "fork.knife") {
                HomeView(profile: profile)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                ProgressView_(profile: profile)
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                SettingsView(profile: profile)
            }
        }
        .task {
            if profile.writeToHealth, HealthStore.available {
                await HealthStore.shared.requestAuthorization()
            }
        }
    }
}
