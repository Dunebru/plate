<p align="center">
  <img src="packaging/icon-1024.png" width="128" alt="Plate icon">
</p>

<h1 align="center">Plate</h1>

<p align="center">
  Photograph a meal, get calories and macros, fix what the camera got wrong, done. A calorie tracker for iPhone with no subscription and no account.
</p>

<p align="center">
  <a href="https://github.com/Dunebru/plate/releases/latest"><img src="https://img.shields.io/github/v/release/Dunebru/plate?style=flat-square&color=2f9e60" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/iOS-18%2B-black?style=flat-square&logo=apple" alt="iOS 18+">
  <img src="https://img.shields.io/badge/Swift-5-orange?style=flat-square&logo=swift" alt="Swift 5">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Dunebru/plate?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" width="900" alt="Plate screens">
</p>

Cal AI, MyFitnessPal Premium, and the other photo trackers charge $50 to $80 a year, keep your food photos on their servers, and hide the barcode scanner behind a paywall. Plate does the same job with your own model API key (Google Gemini Flash-Lite answers in about two seconds; its free tier allows about 20 scans a day per model and Plate moves to the next model when one runs out, or with billing on $10 covers roughly 5,000 scans; Anthropic is the pricier option at about three cents a photo), Open Food Facts for barcodes, and Apple Health for everything else. Your log lives in SwiftData on the phone and in Health, nowhere else.

<details>
<summary>Table of contents</summary>

- [Features](#features)
- [Install](#install)
- [Usage](#usage)
- [How the numbers are made](#how-the-numbers-are-made)
- [FAQ](#faq)
- [Build from source](#build-from-source)
- [License](#license)
- [Acknowledgements](#acknowledgements)

</details>

## Features

### Logging
- **Scan food**: one photo becomes a list of components with portions, calories, protein, carbs, fat, fiber, sugar, and sodium. Hidden oil and sauces are counted
- **Fix results**: tell it "that was brown rice, about two cups" and the whole meal is re-estimated around your correction. Every portion is a stepper, and totals always follow the items
- **Barcode and label**: packaged food from Open Food Facts, or photograph the nutrition facts panel and let the model read it
- **Describe**: type "two eggs, sourdough with butter, black coffee"
- **Saved foods and search**: re-log anything in two taps, create custom foods, search Open Food Facts by name
- **Knows how you eat**: your diet and the foods you never touch are given to the analyzer, so it does not put chicken on a vegan plate

### Targets worth trusting
- **Resting burn from lean mass** when you have measured your body fat, and Mifflin-St Jeor when you have not. Two people at the same weight do not burn the same
- **Everyday movement and training counted separately**, so a desk job with four gym sessions is not confused with being on your feet all day
- **A pace that is capped for your body**. Lean people are held to a slower deficit than heavy people, because past a certain speed the weight coming off is muscle
- **Macros with floors**: protein against lean mass, enough fat for hormones, carbs for training, fiber at 14 g per 1,000 calories
- **Four goals**: lose fat, maintain, build muscle, or recomposition, each with its own arithmetic
- **Uneven days**: eat more on training days or at the weekend, with the same weekly total

### Your body, not just your weight
- **Body fat from a tape measure** with the US Navy method, plus lean mass, fat mass, FFMI, and waist to height
- **Measurements over time** for waist, chest, hips, neck, arms, thighs, and calves, each with a chart and a tip on where to put the tape
- **Progress photos** kept on the phone
- **Focus areas**: pick the parts you want to change and get honest guidance for each, including what training can do and what only fat loss can

### Knowing whether it is working
- **A trend line, not the scale**. Daily weight is mostly water. Plate smooths the readings and carries the slope, so the line does not lag a real change the way a moving average does
- **Your real maintenance calories**, measured from what you logged against what the trend did, and blended toward the prediction only as far as your logging record deserves
- **A verdict** that compares your actual rate with the plan and says what to change
- **A forecast that flattens**, because burn falls as you get lighter. Straight line predictions always overpromise
- **Apple Health**: every meal written as dietary energy and nutrients (edits and deletes sync too). Steps, active energy, and weight read back
- **Export**: your whole log as CSV

## Install

Plate is not on the App Store. Build it with Xcode and put it on your phone with your free Apple developer account (a paid account is not needed for your own devices).

```bash
brew install xcodegen
git clone https://github.com/Dunebru/plate.git && cd plate
xcodegen generate
open Plate.xcodeproj
```

In Xcode: select the Plate target, Signing & Capabilities, pick your team, then Run with your iPhone selected. Or from the terminal with the phone plugged in:

```bash
scripts/install-device.sh <YOUR_TEAM_ID>
```

Requires iOS 18 or newer. Photo, label, and description logging need an API key, entered once in Settings and kept in the keychain: a free Gemini key from aistudio.google.com, or an Anthropic key from console.anthropic.com. Barcodes, search, saved foods, and manual entry work without one.

## Usage

1. Answer the onboarding questions. Plate shows the plan it computed and why.
2. Tap the plus. Scan a plate, a barcode, or a label, or describe the meal.
3. Check the portions on the review screen. Correct anything wrong, then Log.
4. Log your weight a few times a week on the Progress tab. After two weeks Plate can measure your real maintenance calories and offer to move the target.
5. Take a tape measure to yourself every few weeks on the Body tab. Waist and weight together tell you far more than either alone.

## How the numbers are made

- **Resting burn**: Katch-McArdle from lean mass when a body fat figure exists, Mifflin-St Jeor otherwise.
- **Daily burn**: resting burn times a movement factor for life outside workouts, plus the measured cost of your training. Training uses MET values net of rest, because resting burn is already counted once.
- **Pace**: capped at 0.6 to 1.1 percent of body weight a week for fat loss depending on how lean you are, and at what training age allows for muscle gain. The deficit never exceeds a quarter of your daily burn, and never drops below 1,500 kcal for men or 1,200 for women.
- **Macros**: protein per kilogram of lean mass when known and per kilogram of body weight otherwise, more on a plant based diet. Fat at 28 percent of calories with a floor for hormones, carbs taking the rest, fiber at 14 g per 1,000 calories.
- **Body fat**: the US Navy tape method, which lands within about three to four points of a DEXA scan. BMI is only a fallback and is never allowed to drive the calorie target.
- **Weight trend**: the readings are smoothed with a level and a slope, so the line does not trail a real change. The rate you see is a least squares fit across three weeks of readings, not the difference between two days.
- **Measured maintenance**: what you ate minus what the trend did, over the last four weeks, blended toward the prediction according to how completely you logged. Needs 14 days and 10 logged days, and is discarded when the numbers say the log is wrong rather than the metabolism.
- **Forecast**: simulated a week at a time, recomputing burn as body mass falls and applying up to a tenth of metabolic adaptation, which is why the curve flattens instead of running straight.

Every formula is cited in the app under Settings, Sources.

## FAQ

**How accurate is a photo?**
Usually within 10 to 30 percent, worse for stews, curries, and restaurant food where oil is invisible. That is the same range as every photo tracker, which is why the review screen exists. Consistency beats precision: the weekly trend and the reality check are what you should trust.

**Which model does it use?**
Google Gemini Flash-Lite by default, the fastest and cheapest model that reads photos. Plate falls back to the full size Flash models when Lite is busy, and picks current models on its own, so it keeps working when Google retires an older one. Switch to Anthropic in Settings for Claude Opus 5 or Sonnet 5. Requests go straight from the phone to the provider with your key. Nothing goes through any other server.

**Why does it need Apple Health?**
It does not. Turn it off in Settings and everything stays local to the app. With it on, other apps and your watch see your nutrition, and Plate can add workout calories to the budget.

**Can I use it without a key at all?**
Yes. Barcodes, search, saved foods, and custom foods never touch the model.

**Can I target belly fat, or chest fat?**
No, and nothing can. Training an area builds the muscle under the fat, which changes the shape, but the fat leaves from everywhere at once in an order your genetics decide. Studies that trained one limb hard for weeks found the fat came off the whole body. Plate gives honest per area guidance instead of a promise it cannot keep.

**How accurate is the tape measure body fat?**
Within about three to four points of a DEXA scan, which is not good enough to quote as a fact but is plenty to watch a trend. Measure at the same time of day, first thing, and care about the direction rather than the number.

**Why does the forecast curve flatten?**
Because a lighter body burns less, and burn falls by slightly more than size alone explains. Holding the same calories means the gap between burn and intake narrows every week. Any app drawing you a straight line is overpromising.

**Why does it ask so many questions?**
Because every answer sharpens a number. Sex, age, height and weight set the resting burn; body fat replaces that estimate with a better one; movement and training set the daily burn; goal and pace set the deficit; diet sets the macro split. You can skip anything, and every answer is editable in Settings afterwards.

## Build from source

```bash
brew install xcodegen
git clone https://github.com/Dunebru/plate.git && cd plate
xcodegen generate
xcodebuild -project Plate.xcodeproj -scheme Plate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Plate is a plain SwiftUI app: SwiftData for storage, Swift Charts, HealthKit, VisionKit for barcodes, AVFoundation for the camera. No third-party packages.

## License

[MIT](LICENSE) © dunebru

## Acknowledgements

- [Open Food Facts](https://world.openfoodfacts.org) for the product database, ODbL
- Every formula, from the resting burn equations to the body fat method and the rate of loss caps, is listed with its source in the app under Settings, Sources
