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
            DemoData.seedKeyIfRequested()
            if DemoData.requested {
                if profiles.first?.onboarded != true { DemoData.seed(into: context) }
                return
            }
            #endif
            if profiles.isEmpty {
                context.insert(Profile())
                try? context.save()
            }
            repairLimits()
        }
    }

    /// Sugar and sodium limits arrived after people were already using the app. SwiftData fills a new
    /// column from its property default, and the sugar default is the figure for men, so a woman
    /// upgrading would read 36 g until something happened to rebuild her targets. Only these two
    /// fields are corrected here: a full rebuild would also overwrite calorie and macro targets that
    /// someone may have set by hand.
    private func repairLimits() {
        guard let profile = profiles.first, profile.onboarded else { return }
        let sugar = NutritionMath.addedSugarLimit(calories: Double(profile.calorieTarget), sex: profile.sex)
        let sodium = NutritionMath.sodiumLimit()
        guard profile.sugarLimit != sugar || profile.sodiumLimit != sodium else { return }
        profile.sugarLimit = sugar
        profile.sodiumLimit = sodium
        try? context.save()
    }
}

struct MainTabView: View {
    @Bindable var profile: Profile
    @State private var tab: TabChoice = .today
    @StateObject private var quick = QuickAction.shared
    @State private var launchRoute: AddSheet.Route?

    enum TabChoice: String, Hashable { case today, progress, ask, body, settings }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "fork.knife", value: TabChoice.today) {
                HomeView(profile: profile, launchRoute: $launchRoute)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: TabChoice.progress) {
                ProgressView_(profile: profile)
            }
            Tab("Ask", systemImage: "bubble.left.and.text.bubble.right", value: TabChoice.ask) {
                CoachView(profile: profile)
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
            // Opens a logging flow directly, so screens behind a sheet can be looked at:
            // --open camera | label | describe | quickAdd | repeat
            if let index = args.firstIndex(of: "--open"), args.count > index + 1 {
                switch args[index + 1] {
                case "camera": launchRoute = .camera(.food)
                case "label": launchRoute = .camera(.label)
                case "describe": launchRoute = .describe
                case "quickAdd": launchRoute = .quickAdd
                case "repeat": launchRoute = .repeatMeal
                default: break
                }
            }
            #endif
            if profile.writeToHealth, HealthStore.available {
                await HealthStore.shared.requestAuthorization()
            }
            handleQuickAction()
        }
        // The app may already be running when the Action Button is pressed, so this has to be
        // watched rather than only read once at launch.
        .onChange(of: quick.pending) { _, _ in handleQuickAction() }
    }

    private func handleQuickAction() {
        guard let action = quick.take() else { return }
        switch action {
        case .scanMeal:
            tab = .today
            launchRoute = .camera(.food)
        case .describeMeal:
            tab = .today
            launchRoute = .describe
        case .ask:
            tab = .ask
        }
    }
}
