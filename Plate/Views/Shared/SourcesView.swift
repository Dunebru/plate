import SwiftUI

/// Where every number in the app comes from. Linked from the plan screen, Settings, and anywhere
/// the app gives an opinion about a body.
struct SourcesView: View {
    struct Source: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let url: String
    }

    struct Group: Identifiable {
        let id = UUID()
        let name: String
        let sources: [Source]
    }

    static let groups: [Group] = [
        Group(name: "Energy", sources: [
            Source(title: "Resting burn, Mifflin-St Jeor",
                   detail: "Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. American Journal of Clinical Nutrition, 1990; 51(2): 241-247. Used when body fat is unknown.",
                   url: "https://doi.org/10.1093/ajcn/51.2.241"),
            Source(title: "Resting burn from lean mass, Katch-McArdle",
                   detail: "Katch FI, McArdle WD. Exercise Physiology: Energy, Nutrition and Human Performance. Used instead of the equation above once a body fat figure exists, because it measures the tissue that actually burns energy.",
                   url: "https://doi.org/10.1249/00005768-199601000-00019"),
            Source(title: "Everyday movement multipliers",
                   detail: "FAO, WHO and UNU. Human energy requirements: report of a joint expert consultation, 2004. Physical activity levels for sedentary through to heavy occupational work.",
                   url: "https://www.fao.org/4/y5686e/y5686e00.htm"),
            Source(title: "Training burn, MET values",
                   detail: "Ainsworth BE, et al. 2011 Compendium of Physical Activities. Medicine and Science in Sports and Exercise, 2011; 43(8): 1575-1581. Plate subtracts one MET before converting, because resting burn is already counted.",
                   url: "https://doi.org/10.1249/MSS.0b013e31821ece12"),
            Source(title: "About 7,700 kcal in a kilogram",
                   detail: "Hall KD. What is the required energy deficit per unit weight loss? International Journal of Obesity, 2008; 32: 573-576. An average, not a constant.",
                   url: "https://doi.org/10.1038/sj.ijo.0803720"),
            Source(title: "Why the forecast curve flattens",
                   detail: "Hall KD, et al. Quantification of the effect of energy imbalance on bodyweight. The Lancet, 2011; 378: 826-837. And Muller MJ, Bosy-Westphal A. Adaptive thermogenesis with weight loss in humans. Obesity, 2013; 21(2): 218-228. Burn falls as body mass falls, and by a little more than size alone explains, so a straight line forecast always overpromises.",
                   url: "https://doi.org/10.1016/S0140-6736(11)60812-X"),
        ]),
        Group(name: "How fast is safe", sources: [
            Source(title: "Rate of fat loss",
                   detail: "Garthe I, et al. Effect of two different weight loss rates on body composition and strength in elite athletes. International Journal of Sport Nutrition and Exercise Metabolism, 2011; 21(2): 97-104. Slower loss kept more lean mass and more strength.",
                   url: "https://doi.org/10.1123/ijsnem.21.2.97"),
            Source(title: "Leaner bodies need slower deficits",
                   detail: "Helms ER, Aragon AA, Fitschen PJ. Evidence based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. Journal of the International Society of Sports Nutrition, 2014; 11: 20.",
                   url: "https://doi.org/10.1186/1550-2783-11-20"),
            Source(title: "How fast muscle can actually be built",
                   detail: "Slater GJ, et al. Is an energy surplus required to maximize skeletal muscle hypertrophy associated with resistance training? Frontiers in Nutrition, 2019; 6: 131. Plate caps the surplus at what training age allows, because anything faster arrives as fat.",
                   url: "https://doi.org/10.3389/fnut.2019.00131"),
            Source(title: "Lowest daily calories",
                   detail: "National Heart, Lung, and Blood Institute. Clinical Guidelines on the Identification, Evaluation, and Treatment of Overweight and Obesity in Adults, 1998. Plate never sets a target below 1,200 kcal for women or 1,500 kcal for men.",
                   url: "https://www.nhlbi.nih.gov/files/docs/guidelines/ob_gdlns.pdf"),
        ]),
        Group(name: "Macros", sources: [
            Source(title: "Protein for muscle",
                   detail: "Morton RW, et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. British Journal of Sports Medicine, 2018; 52: 376-384.",
                   url: "https://doi.org/10.1136/bjsports-2017-097608"),
            Source(title: "More protein while in a deficit",
                   detail: "Helms ER, Zinn C, Rowlands DS, Brown SR. A systematic review of dietary protein during caloric restriction in resistance trained lean athletes. International Journal of Sport Nutrition and Exercise Metabolism, 2014; 24(2): 127-138. This is why Plate measures protein against lean mass when it can.",
                   url: "https://doi.org/10.1123/ijsnem.2013-0054"),
            Source(title: "A little more protein on a plant based diet",
                   detail: "Berrazaga I, et al. The role of the anabolic properties of plant versus animal based protein sources in supporting muscle mass maintenance. Nutrients, 2019; 11(8): 1825. Plant protein digests less completely and carries less leucine per gram.",
                   url: "https://doi.org/10.3390/nu11081825"),
            Source(title: "Fat and carbohydrate ranges",
                   detail: "Institute of Medicine. Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids, 2005. Acceptable ranges: protein 10 to 35 percent, fat 20 to 35 percent, carbohydrate 45 to 65 percent.",
                   url: "https://nap.nationalacademies.org/catalog/10490"),
            Source(title: "Fiber and water",
                   detail: "Institute of Medicine, as above: 14 g of fiber per 1,000 calories, and total water of 3.7 litres a day for men and 2.7 for women including the water in food.",
                   url: "https://nap.nationalacademies.org/catalog/10925"),
        ]),
        Group(name: "Sugar and sodium", sources: [
            Source(title: "Sugar as a share of what you eat",
                   detail: "World Health Organization. Guideline: sugars intake for adults and children, 2015. Free sugars under 10 percent of total energy, with a conditional further reduction below 5 percent. Plate uses the 10 percent figure. The 5 percent one is conditional and rests on thinner evidence, so it is not what you are measured against.",
                   url: "https://www.who.int/publications/i/item/9789241549028"),
            Source(title: "Sugar as a flat daily amount",
                   detail: "Johnson RK, et al. Dietary sugars intake and cardiovascular health: a scientific statement from the American Heart Association. Circulation, 2009; 120(11): 1011-1020. No more than 36 g of added sugar a day for men and 25 g for women. Plate takes whichever of this and the 10 percent figure is stricter, so a big appetite does not buy a bigger sugar allowance.",
                   url: "https://doi.org/10.1161/CIRCULATIONAHA.109.192627"),
            Source(title: "Total sugar is not added sugar",
                   detail: "US Food and Drug Administration. Added sugars on the Nutrition Facts label. Added sugar is what goes in during processing or at the table. The sugar already in fruit, vegetables and plain milk is not counted. Plate reads total sugar, which is all most food data carries, so fruit and dairy push your number up against a limit that was never written for them.",
                   url: "https://www.fda.gov/food/nutrition-facts-label/added-sugars-nutrition-facts-label"),
            Source(title: "Sodium",
                   detail: "National Academies of Sciences, Engineering, and Medicine. Dietary Reference Intakes for Sodium and Potassium, 2019. A Chronic Disease Risk Reduction intake of 2,300 mg a day for adults, meaning intake above it is expected to raise chronic disease risk. The American Heart Association's ideal is lower still at 1,500 mg. Plate uses 2,300 mg, and it does not move with your size or your calories because the evidence behind it is about blood pressure rather than energy.",
                   url: "https://nap.nationalacademies.org/catalog/25353"),
        ]),
        Group(name: "Body composition", sources: [
            Source(title: "Body fat from a tape measure",
                   detail: "Hodgdon JA, Beckett MB. Prediction of percent body fat for US Navy men and women from body circumferences and height. Naval Health Research Center, 1984. Lands within about three to four points of a DEXA scan.",
                   url: "https://apps.dtic.mil/sti/citations/ADA143890"),
            Source(title: "Body fat estimated from BMI",
                   detail: "Deurenberg P, Weststrate JA, Seidell JC. Body mass index as a measure of body fatness. British Journal of Nutrition, 1991; 65(2): 105-114. The fallback when there is no tape measure. It cannot tell muscle from fat, so it reads high on people who lift.",
                   url: "https://doi.org/10.1079/BJN19910073"),
            Source(title: "Fat free mass index",
                   detail: "Kouri EM, et al. Fat free mass index in users and nonusers of anabolic androgenic steroids. Clinical Journal of Sport Medicine, 1995; 5(4): 223-228. The source of the height adjustment and of the drug free ceiling around 25.",
                   url: "https://doi.org/10.1097/00042752-199510000-00003"),
            Source(title: "Waist divided by height",
                   detail: "Ashwell M, Gunn P, Gibson S. Waist to height ratio is a better screening tool than waist circumference and BMI for adult cardiometabolic risk factors. Obesity Reviews, 2012; 13(3): 275-286. Keeping it under 0.5 is the simplest target there is.",
                   url: "https://doi.org/10.1111/j.1467-789X.2011.00952.x"),
            Source(title: "Body fat categories",
                   detail: "American Council on Exercise body fat percentage categories for men and women.",
                   url: "https://www.acefitness.org/resources/everyone/blog/112/what-are-the-guidelines-for-percentage-of-body-fat-loss/"),
            Source(title: "Body mass index categories",
                   detail: "Centers for Disease Control and Prevention. Adult BMI categories: under 18.5 underweight, 18.5 to 24.9 healthy, 25 to 29.9 overweight, 30 and above obesity. BMI describes a population, not a person, so Plate never uses it alone.",
                   url: "https://www.cdc.gov/bmi/adult-calculator/bmi-categories.html"),
        ]),
        Group(name: "Changing a specific part of your body", sources: [
            Source(title: "You cannot choose where fat comes off",
                   detail: "Ramirez-Campillo R, et al. Regional fat changes induced by localized muscle endurance resistance training. Journal of Strength and Conditioning Research, 2013; 27(8): 2219-2224. And Vispute SS, et al. The effect of abdominal exercise on abdominal fat. Journal of Strength and Conditioning Research, 2011; 25(9): 2559-2564. Both trained one area hard for weeks and found no extra fat loss there.",
                   url: "https://doi.org/10.1519/JSC.0b013e31827e8681"),
            Source(title: "How much training builds muscle",
                   detail: "Schoenfeld BJ, Ogborn D, Krieger JW. Dose response relationship between weekly resistance training volume and increases in muscle mass. Journal of Sports Sciences, 2017; 35(11): 1073-1082. Roughly 10 or more hard sets per muscle per week.",
                   url: "https://doi.org/10.1080/02640414.2016.1210197"),
            Source(title: "Chest tissue that diet will not shift",
                   detail: "Braunstein GD. Gynecomastia. New England Journal of Medicine, 2007; 357: 1229-1237. Glandular breast tissue in men is common, is not fat, and does not respond to diet or exercise. A firm disc under the nipple, tenderness, or one side only is worth showing to a doctor.",
                   url: "https://doi.org/10.1056/NEJMcp070677"),
        ]),
        Group(name: "Tracking", sources: [
            Source(title: "Why the trend line, not the scale",
                   detail: "Walker J. The Hacker's Diet, 1991. Daily weight is mostly water and gut contents. Plate smooths the readings and carries the slope, so the line does not lag behind a real change the way a moving average does.",
                   url: "https://www.fourmilab.ch/hackdiet/"),
            Source(title: "Measuring your own maintenance",
                   detail: "Energy balance: what you ate, minus what the trend line did, is your real maintenance. It beats any prediction equation once there are a few weeks of honest logging, which is why Plate blends it in only as far as your logging record justifies.",
                   url: "https://doi.org/10.1038/sj.ijo.0803720"),
            Source(title: "Food data",
                   detail: "Open Food Facts, the open database of food products, licensed under the Open Database License. Used for barcodes and search.",
                   url: "https://world.openfoodfacts.org"),
        ]),
    ]

    var body: some View {
        List {
            Section {
                Text("Plate works out your calories from your resting burn, your everyday movement and your training, then sets macros around them. Nothing here is guessed. Every formula and every claim is listed below with where it came from.")
                    .font(.footnote)
            } header: {
                Text("How the numbers are worked out")
            }

            ForEach(SourcesView.groups) { group in
                Section(group.name) {
                    ForEach(group.sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title).font(.subheadline.weight(.semibold))
                            Text(source.detail).font(.footnote).foregroundStyle(.secondary)
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Label(url.host ?? source.url, systemImage: "link").font(.footnote)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Text("These targets are general guidance for healthy adults and are not medical advice. If you are pregnant or breastfeeding, under 18, have a medical condition, are recovering from an eating disorder, or take medication that affects appetite or weight, talk to a doctor or registered dietitian before changing what you eat.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Not medical advice")
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
