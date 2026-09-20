import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var profiles: [Profile]
    @Environment(\.modelContext) private var context
    /// The first appearance is the only one allowed to create or seed a profile. Without this the
    /// query can still read empty on a second pass and a duplicate profile appears.
    @State private var didPrepare = false

    var body: some View {
        Group {
            if let profile = profiles.first {
                if !profile.onboarded {
                    OnboardingView(profile: profile)
                } else if profile.needsDeeperSetup, !profile.dismissedDeeperSetup {
                    DeeperSetupView(profile: profile) { profile.onboarded = false }
                } else {
                    MainTabView(profile: profile)
                }
            } else {
                Color(.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .onAppear {
            guard !didPrepare else { return }
            didPrepare = true
            #if DEBUG
            if DemoData.requested {
                if profiles.first?.onboarded != true { DemoData.seed(into: context) }
                return
            }
            #endif
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
        }
    }
}

struct MainTabView: View {
    @Bindable var profile: Profile
    @State private var tab: TabChoice = .today

    enum TabChoice: String, Hashable { case today, progress, body, settings }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "fork.knife", value: TabChoice.today) {
                HomeView(profile: profile)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: TabChoice.progress) {
                ProgressView_(profile: profile)
            }
            if profile.showBodyTab {
                Tab("Body", systemImage: "figure.stand", value: TabChoice.body) {
                    BodyView(profile: profile)
                }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: TabChoice.settings) {
                SettingsView(profile: profile)
            }
        }
        .task {
            #if DEBUG
            // Lets a screenshot run open straight onto a tab: --tab progress
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--tab"), args.count > index + 1,
               let choice = TabChoice(rawValue: args[index + 1]) {
                tab = choice
            }
            #endif
            if profile.writeToHealth, HealthStore.available {
                await HealthStore.shared.requestAuthorization()
            }
        }
    }
}
