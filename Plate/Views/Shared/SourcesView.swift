import SwiftUI

/// Where the calorie and macro numbers come from. Linked from the plan screen and Settings.
struct SourcesView: View {
    struct Source: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let url: String
    }

    static let sources: [Source] = [
        Source(title: "Resting energy: Mifflin-St Jeor equation",
               detail: "Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. American Journal of Clinical Nutrition, 1990; 51(2): 241-247.",
               url: "https://doi.org/10.1093/ajcn/51.2.241"),
        Source(title: "Activity multipliers",
               detail: "FAO/WHO/UNU. Human energy requirements: report of a joint expert consultation. Physical activity level factors, 2004.",
               url: "https://www.fao.org/4/y5686e/y5686e00.htm"),
        Source(title: "Macronutrient ranges",
               detail: "Institute of Medicine. Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids. Acceptable Macronutrient Distribution Ranges: protein 10 to 35 percent, fat 20 to 35 percent, carbohydrate 45 to 65 percent, 2005.",
               url: "https://nap.nationalacademies.org/catalog/10490"),
        Source(title: "Protein of 1.6 to 2.2 grams per kilogram",
               detail: "Morton RW, et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. British Journal of Sports Medicine, 2018; 52: 376-384.",
               url: "https://doi.org/10.1136/bjsports-2017-097608"),
        Source(title: "Higher protein while in a deficit",
               detail: "Helms ER, Zinn C, Rowlands DS, Brown SR. A systematic review of dietary protein during caloric restriction in resistance trained lean athletes. International Journal of Sport Nutrition and Exercise Metabolism, 2014; 24(2): 127-138.",
               url: "https://doi.org/10.1123/ijsnem.2013-0054"),
        Source(title: "About 7,700 kcal per kilogram of body weight",
               detail: "Hall KD. What is the required energy deficit per unit weight loss? International Journal of Obesity, 2008; 32: 573-576. The figure is an average; real loss slows over time.",
               url: "https://doi.org/10.1038/sj.ijo.0803720"),
        Source(title: "Minimum daily calories",
               detail: "National Heart, Lung, and Blood Institute. Clinical Guidelines on the Identification, Evaluation, and Treatment of Overweight and Obesity in Adults, 1998. Plate never sets a target below 1,200 kcal for women or 1,500 kcal for men.",
               url: "https://www.nhlbi.nih.gov/files/docs/guidelines/ob_gdlns.pdf"),
        Source(title: "Body mass index categories",
               detail: "Centers for Disease Control and Prevention. Adult BMI categories: underweight below 18.5, healthy 18.5 to 24.9, overweight 25 to 29.9, obesity 30 and above.",
               url: "https://www.cdc.gov/bmi/adult-calculator/bmi-categories.html"),
        Source(title: "Nutrition data for barcodes and search",
               detail: "Open Food Facts, the open database of food products, licensed under the Open Database License.",
               url: "https://world.openfoodfacts.org"),
    ]

    var body: some View {
        List {
            Section {
                Text("Plate estimates your resting energy with the Mifflin-St Jeor equation, multiplies it by an activity factor for maintenance, then adds or removes calories for your weekly pace. Protein is set per kilogram of body weight, fat at about 28 percent of calories with a floor of 0.6 grams per kilogram, and carbohydrates fill the rest, never below 50 grams.")
                    .font(.footnote)
            } header: {
                Text("How the numbers are calculated")
            }
            Section("Sources") {
                ForEach(SourcesView.sources) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.subheadline.weight(.semibold))
                        Text(s.detail).font(.footnote).foregroundStyle(.secondary)
                        if let u = URL(string: s.url) {
                            Link(destination: u) {
                                Label(u.host ?? s.url, systemImage: "link").font(.footnote)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                Text("These targets are general guidance for healthy adults and are not medical advice. If you are pregnant, under 18, have a medical condition, or take medication that affects appetite or weight, talk to a doctor or registered dietitian before changing what you eat.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Not medical advice")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
