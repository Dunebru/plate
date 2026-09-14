import SwiftUI
import VisionKit

/// Live barcode scanner backed by VisionKit, then an Open Food Facts lookup and a serving picker.
struct BarcodeFlowView: View {
    var onResult: (AnalyzedMeal, UIImage?) -> Void
    @State private var code: String?
    @State private var product: OpenFoodFacts.Product?
    @State private var loading = false
    @State private var error: String?
    @State private var manualCode = ""

    var body: some View {
        Group {
            if let product {
                ProductServingView(product: product, onResult: { onResult($0, nil) })
            } else {
                scanner
            }
        }
        .navigationTitle("Barcode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scanner: some View {
        VStack(spacing: 14) {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    BarcodeScanner { found in handle(found) }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                        .overlay(Text("Live scanning is not available on this device. Type the barcode below.").font(.footnote).padding())
                }
                if loading {
                    ProgressView("Looking up").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                TextField("Or type the barcode", text: $manualCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Look up") { handle(manualCode) }.disabled(manualCode.count < 8)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Text("Data from Open Food Facts. If a product is missing, scan its nutrition label instead.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
    }

    private func handle(_ found: String) {
        guard !loading, code != found else { return }
        code = found
        loading = true
        error = nil
        Task {
            do {
                product = try await OpenFoodFacts.product(barcode: found)
            } catch {
                self.error = error.localizedDescription
                code = nil
            }
            loading = false
        }
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39, .qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: (String) -> Void
        private var last: String?
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue, value != last {
                    last = value
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onFound(value)
                }
            }
        }
    }
}

/// Pick how much of a database product was eaten.
struct ProductServingView: View {
    var product: OpenFoodFacts.Product
    var onResult: (AnalyzedMeal) -> Void
    @State private var servings: Double = 1
    @State private var grams: Double = 100
    @State private var byServing = true

    private var canUseServing: Bool { product.servingGrams != nil }
    private var totalGrams: Double { byServing && canUseServing ? (product.servingGrams ?? 100) * servings : grams }
    private var totals: Nutrients { product.per100g * (totalGrams / 100) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AsyncImage(url: product.imageURL) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        Text(product.name).font(.headline)
                        if !product.brand.isEmpty { Text(product.brand).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Amount") {
                if canUseServing {
                    Picker("Measure", selection: $byServing) {
                        Text("Servings").tag(true)
                        Text("Grams").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if byServing && canUseServing {
                    Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                        HStack {
                            Text("Servings")
                            Spacer()
                            Text("\(FoodAnalyzer.trim(servings)) x \(product.servingLabel)").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text("Grams")
                        Spacer()
                        NumberField(title: "g", value: $grams).frame(width: 80)
                    }
                }
            }
            Section("This amount") {
                TotalsGrid(n: totals)
            }
            Section {
                Button { onResult(meal) } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Amount")
        .onAppear { byServing = canUseServing; if let g = product.servingGrams { grams = g } }
    }

    private var meal: AnalyzedMeal {
        let unit = byServing && canUseServing ? product.servingLabel : "g"
        let qty = byServing && canUseServing ? servings : grams
        let base = byServing && canUseServing ? product.per100g * ((product.servingGrams ?? 100) / 100) : product.per100g * 0.01
        let gramsPerUnit: Double? = byServing && canUseServing ? product.servingGrams : 1
        let name = product.brand.isEmpty ? product.name : "\(product.name) (\(product.brand))"
        return AnalyzedMeal(name: name,
                            items: [.init(name: name, quantity: qty, unit: unit, gramsPerUnit: gramsPerUnit, base: base, confidence: 1)],
                            notes: "From Open Food Facts.", healthScore: nil, confidence: 1, source: .barcode)
    }
}
