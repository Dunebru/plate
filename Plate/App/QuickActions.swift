import AppIntents
import SwiftUI

/// Ways into the app that skip the app.
///
/// The fastest logging is the kind that does not involve finding an icon, waiting for a tab to load
/// and tapping through a menu while the food goes cold. These intents put the camera one press away:
/// assign one to the Action Button, say it to Siri, or drop it in a Shortcut.
@MainActor
final class QuickAction: ObservableObject {
    static let shared = QuickAction()

    enum Action: Equatable { case scanMeal, describeMeal, ask }

    /// Read once and cleared, because a pending action that survives being handled would fire again
    /// every time the view it lives on comes back.
    @Published var pending: Action?

    func take() -> Action? {
        defer { pending = nil }
        return pending
    }
}

struct ScanMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a meal"
    static var description = IntentDescription("Opens Plate straight into the camera so a meal can be photographed and logged.")
    /// The camera is the point, so the app has to come forward. Nothing here happens in the background.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.shared.pending = .scanMeal
        return .result()
    }
}

struct DescribeMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Describe a meal"
    static var description = IntentDescription("Opens Plate ready to log a meal by typing or dictating what it was.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.shared.pending = .describeMeal
        return .result()
    }
}

struct AskPlateIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask about my day"
    static var description = IntentDescription("Opens Plate on the Ask tab, where questions are answered from your own numbers.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAction.shared.pending = .ask
        return .result()
    }
}

/// What Siri and the Action Button offer without the user building a Shortcut first.
struct PlateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanMealIntent(),
                    phrases: ["Scan a meal with \(.applicationName)",
                              "Log food with \(.applicationName)",
                              "\(.applicationName) scan"],
                    shortTitle: "Scan a meal",
                    systemImageName: "camera.fill")
        AppShortcut(intent: DescribeMealIntent(),
                    phrases: ["Describe a meal in \(.applicationName)",
                              "Log a meal in \(.applicationName)"],
                    shortTitle: "Describe a meal",
                    systemImageName: "text.bubble.fill")
        AppShortcut(intent: AskPlateIntent(),
                    phrases: ["Ask \(.applicationName) about my day",
                              "How am I doing in \(.applicationName)"],
                    shortTitle: "Ask about my day",
                    systemImageName: "bubble.left.and.text.bubble.right")
    }
}
