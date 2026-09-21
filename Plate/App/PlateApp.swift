import SwiftUI
import SwiftData

@main
struct PlateApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Profile.self, MealEntry.self, MealItem.self, SavedFood.self, WeightEntry.self, BodyMeasurement.self, FoodCorrection.self])
    }
}
