import SwiftData
import SwiftUI

struct RootView: View {
    @Query private var profiles: [Profile]
    @Environment(\.modelContext) private var context
    /// The first appearance is the only one allowed to create or seed a profile. Without this the
    /// query can still read empty on a second pass and a duplicate profile appears.
    @State private var didPrepare = false
    /// The profile currently being set up. Onboarding marks a profile done as soon as the essential
    /// questions are answered, so someone who stops there is fully set up, which means the flag
    /// alone can no longer say whether the optional questions after it are still on screen. Holding
    /// the identity rather than a plain switch keeps a profile replaced underneath us, as the demo
    /// seed does, from pinning the flow open.
    @State private var settingUp: PersistentIdentifier?

    var body: some View {
        Group {
            if let profile = profiles.first {
                if !profile.onboarded || settingUp == profile.persistentModelID {
                    OnboardingView(profile: profile) { settingUp = nil }
                        .onAppear { settingUp = profile.persistentModelID }
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
