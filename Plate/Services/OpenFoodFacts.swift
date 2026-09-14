import Foundation

/// Open Food Facts lookups for barcodes and text search. No key needed; one call per real scan.
struct OpenFoodFacts {
    struct Product: Identifiable, Equatable {
        var id: String { barcode ?? name + brand }
        var barcode: String?
        var name: String
        var brand: String
        var servingLabel: String
        var servingGrams: Double?
        var per100g: Nutrients
        var imageURL: URL?

        var perServing: Nutrients? {
            guard let g = servingGrams, g > 0 else { return nil }
            return per100g * (g / 100)
        }
    }

    enum LookupError: LocalizedError {
        case notFound
        case network
        var errorDescription: String? {
            switch self {
            case .notFound: return "No product found for that barcode. Try scanning the nutrition label instead."
            case .network: return "Could not reach Open Food Facts."
            }
        }
    }

    static let fields = "code,product_name,product_name_en,brands,serving_size,serving_quantity,nutriments,image_front_small_url"
    static let userAgent = "Plate/1.0 (https://github.com/Dunebru/plate)"

    static func product(barcode: String) async throws -> Product {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)")!
        comps.queryItems = [URLQueryItem(name: "fields", value: fields)]
        let data = try await fetch(comps.url!)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1 || (json["status"] as? String) == "success",
              let p = json["product"] as? [String: Any],
              let product = parse(p) else { throw LookupError.notFound }
        return product
    }

    /// Full-text search. The dedicated search service is fast; the legacy CGI search is the fallback.
    static func search(_ query: String) async throws -> [Product] {
        var fast = URLComponents(string: "https://search.openfoodfacts.org/search")!
        fast.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: fields),
        ]
        if let data = try? await fetch(fast.url!),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hits = json["hits"] as? [[String: Any]] {
            return hits.compactMap(parse).filter { $0.per100g.calories > 0 }
        }
        var comps = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: fields),
        ]
        let data = try await fetch(comps.url!)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else { return [] }
        return products.compactMap(parse).filter { $0.per100g.calories > 0 }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw LookupError.notFound }
            guard (200..<300).contains(status) else { throw LookupError.network }
            return data
        } catch let e as LookupError {
            throw e
        } catch {
            throw LookupError.network
        }
    }

    static func brand(from raw: Any?) -> String {
        if let list = raw as? [String] { return list.first?.trimmingCharacters(in: .whitespaces) ?? "" }
        if let s = raw as? String { return s.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "" }
        return ""
    }

    static func parse(_ p: [String: Any]) -> Product? {
        let name = (p["product_name_en"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (p["product_name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ key: String) -> Double {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String, let d = Double(s) { return d }
            return 0
        }
        var kcal = num("energy-kcal_100g")
        if kcal == 0 { kcal = num("energy_100g") / 4.184 }
        let per100 = Nutrients(calories: kcal, protein: num("proteins_100g"), carbs: num("carbohydrates_100g"),
                               fat: num("fat_100g"), fiber: num("fiber_100g"), sugar: num("sugars_100g"),
                               sodium: num("sodium_100g") * 1000)
        var servingGrams: Double? = nil
        if let q = p["serving_quantity"] as? Double, q > 0 { servingGrams = q }
        else if let q = p["serving_quantity"] as? String, let d = Double(q), d > 0 { servingGrams = d }
        let servingSize = (p["serving_size"] as? String) ?? ""
        let servingLabel = servingSize.isEmpty ? (servingGrams.map { "serving (\(Int($0)) g)" } ?? "100 g") : servingSize
        let image = (p["image_front_small_url"] as? String).flatMap(URL.init(string:))
        return Product(barcode: p["code"] as? String, name: name.trimmingCharacters(in: .whitespaces),
                       brand: brand(from: p["brands"]),
                       servingLabel: servingLabel, servingGrams: servingGrams, per100g: per100, imageURL: image)
    }
}
