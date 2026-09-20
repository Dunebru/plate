import Foundation

/// What can actually be done about a specific part of the body.
///
/// The honest part first, because every other app gets this wrong: you cannot choose where fat
/// comes off. Training a muscle hard does not burn the fat sitting on top of it. Studies that
/// trained one limb for weeks found the fat came off the whole body, not the limb being worked.
/// Where you store fat, and the order it leaves, is set by genetics and hormones.
///
/// What does work is unglamorous and reliable. Lose fat everywhere with a calorie deficit, keep
/// protein high so the weight you lose is fat rather than muscle, and train the muscle underneath
/// so there is a shape worth uncovering. That is what the guidance below says, per area.
enum FocusGuidance {

    struct Plan {
        var area: BodyArea
        var headline: String
        var truth: String
        var training: [String]
        var nutrition: String
        var measure: String
        /// Shown as a warning, for the cases where the right answer is a doctor rather than a gym.
        var caution: String?
        var weeks: String
    }

    static func plan(for area: BodyArea, goal: AreaGoal, sex: Sex) -> Plan {
        switch area {
        case .chest:
            return Plan(
                area: area,
                headline: goal == .bigger ? "Build the chest" : "A flatter, firmer chest",
                truth: "Press ups and bench press build the muscle under the fat, they do not burn the fat on top of it. A softer chest gets firmer through overall fat loss plus the muscle you add underneath, in that order of importance.",
                training: ["Press twice a week: bench press, dumbbell press, or push ups to near failure",
                           "Add an incline press for the upper chest, which is what changes the shape most",
                           "Finish with a fly or cable crossover for the stretch under load",
                           "Two to four sets per exercise, stopping one or two reps short of failure"],
                nutrition: goal == .bigger
                    ? "Eat at or slightly above maintenance with protein at the top of your target. Muscle is built from training and protein, not from extra calories alone."
                    : "Stay in the calorie deficit. Chest fat is usually among the last to go for men, so give it months rather than weeks.",
                measure: "Measure your chest across the nipples and your waist. If the waist is dropping and the chest is holding, you are gaining shape.",
                caution: sex == .male
                    ? "If you can feel a firm, rubbery disc right under the nipple, or it is tender or only on one side, that is likely gynecomastia, which is glandular tissue rather than fat. Diet and training will not shift it. It is common, it is treatable, and it is worth a word with a doctor."
                    : nil,
                weeks: "Visible change in 8 to 16 weeks")

        case .midsection:
            return Plan(
                area: area,
                headline: "A smaller waist",
                truth: "Sit ups build the muscle under the fat. They do not remove it. Waist size follows total body fat, and the fat around the organs tends to go first, which is also the fat that matters most for health.",
                training: ["Train the core twice a week: hanging knee raises, planks, cable crunches",
                           "Carry something heavy. Loaded carries build the deep muscles that hold the waist in",
                           "Keep a walk in most days. It costs little recovery and adds up",
                           "Squats and deadlifts work the midsection harder than most ab exercises"],
                nutrition: "The deficit does the work. Protein and fiber at every meal make it bearable. Alcohol is worth watching here: it is empty calories and it makes the next day's appetite worse.",
                measure: "Waist at the belly button, same time of day, first thing in the morning. Waist divided by height under 0.5 is the target worth aiming at.",
                caution: nil,
                weeks: "Noticeable in 6 to 12 weeks")

        case .arms:
            return Plan(
                area: area,
                headline: goal == .leaner ? "Leaner arms" : "Bigger arms",
                truth: "Arms are two thirds triceps. Most people train biceps twice as hard and wonder why the sleeve does not fill. Upper arm fat, for women especially, is among the last places the body gives up.",
                training: ["Triceps twice a week: close grip press, overhead extension, dips",
                           "Biceps twice a week: curls with a slow lowering phase",
                           "Rows and pull ups train the biceps hard, so count them",
                           "10 to 20 hard sets per muscle per week is where growth happens"],
                nutrition: goal == .bigger
                    ? "Hit your protein target every day and eat at maintenance or a touch above."
                    : "Keep the deficit and the protein. The muscle you keep is what shapes the arm as the fat comes off.",
                measure: "Arm halfway between shoulder and elbow, relaxed, same arm every time.",
                caution: nil,
                weeks: "A centimetre in 10 to 16 weeks is good going")

        case .shoulders:
            return Plan(
                area: area,
                headline: "Wider shoulders",
                truth: "Shoulder width is the fastest way to change how a body reads, because the waist to shoulder ratio is what the eye actually judges. The side delt is the part that widens you, and it responds well to volume.",
                training: ["Side raises three times a week, light, high reps, strict form",
                           "Overhead press twice a week for the front and overall strength",
                           "Rear delt flys or face pulls, which also fix the posture that hides your chest",
                           "Side delts recover fast, so they can take more work than most muscles"],
                nutrition: "Protein at the top of your range. This is a build, so a deficit slows it down.",
                measure: "Shoulder width is hard to tape. Use photos in the same light and posture every four weeks.",
                caution: nil,
                weeks: "Visible in 12 to 20 weeks")

        case .back:
            return Plan(
                area: area,
                headline: "A stronger back",
                truth: "The back is the biggest muscle group in the upper body and the most undertrained. It also holds your posture, which changes how everything else looks without changing a single measurement.",
                training: ["Pull ups or lat pulldowns twice a week for width",
                           "Rows twice a week for thickness: barbell, dumbbell, or cable",
                           "Deadlifts or hip hinges once a week",
                           "Pull with the elbows, not the hands, and pause at the top"],
                nutrition: "Same as any build: protein first, calories at or above maintenance.",
                measure: "Photos from behind, and the weight on your rows. Strength is the honest measure here.",
                caution: nil,
                weeks: "Strength in 4 weeks, shape in 12 to 20")

        case .glutes:
            return Plan(
                area: area,
                headline: "Stronger glutes",
                truth: "Glutes are one of the few places where training genuinely changes the shape, because there is a lot of muscle to build. They need both heavy work and work at full stretch.",
                training: ["Hip thrusts twice a week, heavy, with a pause at the top",
                           "Romanian deadlifts for the stretch under load",
                           "Split squats or lunges, which also fix side to side differences",
                           "Squats help, but they are not enough on their own"],
                nutrition: goal == .bigger
                    ? "Eat at or slightly above maintenance. This is muscle you are asking for, so feed it."
                    : "In a deficit, keep protein high and the training heavy so the shape survives the fat loss.",
                measure: "Hips at the widest point, and the weight on your hip thrust.",
                caution: nil,
                weeks: "Visible in 10 to 20 weeks")

        case .legs:
            return Plan(
                area: area,
                headline: goal == .leaner ? "Leaner legs" : "Stronger legs",
                truth: "Training legs hard will not slim them on its own, and for some people it makes them measure bigger before they look leaner, because the muscle grows while the fat is still there. That is progress, even though the tape disagrees for a while.",
                training: ["Squat or leg press twice a week",
                           "Romanian deadlifts or leg curls for the hamstrings, which most people skip",
                           "Calf raises, slow, with a pause at the bottom",
                           "Walking and cycling for the calories without wrecking recovery"],
                nutrition: goal == .leaner
                    ? "The deficit decides this one. Keep training heavy so what is underneath is worth uncovering."
                    : "Maintenance or slightly above, with protein at the top of your target.",
                measure: "Thigh halfway between hip and knee, same leg, same time of day.",
                caution: nil,
                weeks: "12 to 24 weeks")

        case .faceAndNeck:
            return Plan(
                area: area,
                headline: "A leaner face",
                truth: "There are no exercises for this. Face and neck follow total body fat, and for many people the face is the first place a change shows. Salt, alcohol and poor sleep make it puffy, which is water rather than fat and moves within days.",
                training: ["Nothing specific. Train the body and the face follows",
                           "Sleep is the lever most people are missing"],
                nutrition: "Keep the deficit, keep sodium moderate, drink enough water, and go easy on alcohol. Puffiness usually clears in two or three days once those are steady.",
                measure: "Photos, same light, same time of day, every two weeks.",
                caution: nil,
                weeks: "Often the first place to show, 4 to 8 weeks")

        case .overall:
            return Plan(
                area: area,
                headline: "Overall shape",
                truth: "Shape is fat loss plus muscle, and the order matters less than the consistency. Most people get most of the way there with a modest deficit, high protein, and lifting three times a week for a year.",
                training: ["Lift three times a week, full body or upper and lower",
                           "Walk most days",
                           "Add reps or weight over time. Progression is the whole game"],
                nutrition: "Hit calories and protein. Everything else is detail.",
                measure: "Weight trend, waist, and photos every four weeks.",
                caution: nil,
                weeks: "Real change in 12 weeks, big change in a year")
        }
    }

    /// The one paragraph everyone should read before picking an area.
    static let spotReductionNote =
        "You cannot pick where fat comes off. Training an area builds the muscle under the fat, which changes the shape, but the fat itself leaves from everywhere at once in an order your genetics decide. Anything promising otherwise is selling something."
}
