import Foundation
import OSLog

struct FoodEstimateValue: Equatable, Sendable {
    var description: String
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var addedSugarGrams: Double
    var sodiumMilligrams: Double
    var confidence: Double
}

enum EstimateClientError: LocalizedError, Equatable {
    case notConfigured
    case missingInput
    case textTooLong
    case invalidResponse
    case unauthorized
    case tooLarge
    case dailyLimit
    case serverUnavailable
    case connection

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Food estimates aren't available right now. You can enter the numbers yourself."
        case .missingInput: "Add a description or photo to estimate this meal."
        case .textTooLong: "Keep the meal description under 500 characters."
        case .invalidResponse: "Koi couldn't read that estimate. Try again or enter the numbers yourself."
        case .unauthorized: "Koi couldn't verify this request. You can enter the numbers yourself."
        case .tooLarge: "That photo is too large to estimate. Try a smaller photo."
        case .dailyLimit: "You've reached today's estimate limit. You can enter the numbers yourself."
        case .serverUnavailable: "Couldn't reach Koi's estimator. Check your connection."
        case .connection: "Couldn't reach Koi's estimator. Check your connection."
        }
    }
}

protocol FoodEstimating: Sendable {
    func estimate(text: String?, jpegData: Data?) async throws -> FoodEstimateValue
}

struct EstimateClient: FoodEstimating {
    private let logger = Logger(subsystem: "com.alexandertarica.koi", category: "Estimate")
    private let session: URLSession
    private let configuration: Configuration?

    struct Configuration: Sendable {
        let baseURL: URL
        let appToken: String

        init?(baseURL: String, appToken: String) {
            guard let url = URL(string: baseURL),
                  url.scheme == "https",
                  url.host != nil,
                  !appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  appToken != "REPLACE_ME" else { return nil }
            self.baseURL = url
            self.appToken = appToken
        }
    }

    init(session: URLSession = .shared, configuration: Configuration? = Self.loadConfiguration()) {
        self.session = session
        self.configuration = configuration
    }

    var isConfigured: Bool { configuration != nil }

    func estimate(text: String?, jpegData: Data?) async throws -> FoodEstimateValue {
        guard let configuration else { throw EstimateClientError.notConfigured }
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validText = trimmedText.flatMap { $0.isEmpty ? nil : $0 }
        guard validText != nil || jpegData != nil else { throw EstimateClientError.missingInput }
        if let validText, validText.count > 500 { throw EstimateClientError.textTooLong }

        let url = configuration.baseURL.appending(path: "/api/estimate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.appToken, forHTTPHeaderField: "x-koi-app-token")
        request.setValue(Self.deviceIdentifier(), forHTTPHeaderField: "x-koi-device")
        let payload = EstimateRequest(text: validText, image: jpegData?.base64EncodedString(), mediaType: jpegData == nil ? nil : "image/jpeg")
        request.httpBody = try JSONEncoder().encode(payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw EstimateClientError.invalidResponse }
            switch response.statusCode {
            case 200..<300:
                guard let decoded = try? JSONDecoder().decode(EstimateResponse.self, from: data) else {
                    throw EstimateClientError.invalidResponse
                }
                return decoded.value
            case 401: throw EstimateClientError.unauthorized
            case 413: throw EstimateClientError.tooLarge
            case 429: throw EstimateClientError.dailyLimit
            case 500..<600: throw EstimateClientError.serverUnavailable
            default: throw EstimateClientError.invalidResponse
            }
        } catch let error as EstimateClientError {
            throw error
        } catch {
            logger.error("Estimator request failed.")
            throw EstimateClientError.connection
        }
    }

    private static func loadConfiguration() -> Configuration? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let baseURL = dictionary["KOI_API_BASE_URL"],
              let token = dictionary["KOI_APP_TOKEN"] else { return nil }
        return Configuration(baseURL: baseURL, appToken: token)
    }

    private static func deviceIdentifier() -> String {
        let key = "koi.device.identifier"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

private struct EstimateRequest: Encodable {
    let text: String?
    let image: String?
    let mediaType: String?
}

private struct EstimateResponse: Decodable {
    let calories: Double
    let proteinGrams: Double
    let carbohydrateGrams: Double
    let fatGrams: Double
    let fiberGrams: Double
    let addedSugarGrams: Double
    let sodiumMilligrams: Double
    let confidence: Double
    let description: String

    enum CodingKeys: String, CodingKey {
        case calories, confidence, description
        case proteinGrams = "protein_g"
        case carbohydrateGrams = "carbs_g"
        case fatGrams = "fat_g"
        case fiberGrams = "fiber_g"
        case addedSugarGrams = "added_sugar_g"
        case sodiumMilligrams = "sodium_mg"
    }

    var value: FoodEstimateValue {
        FoodEstimateValue(
            description: description,
            calories: nonnegative(calories),
            proteinGrams: nonnegative(proteinGrams),
            carbohydrateGrams: nonnegative(carbohydrateGrams),
            fatGrams: nonnegative(fatGrams),
            fiberGrams: nonnegative(fiberGrams),
            addedSugarGrams: nonnegative(addedSugarGrams),
            sodiumMilligrams: nonnegative(sodiumMilligrams),
            confidence: min(max(confidence.isFinite ? confidence : 0, 0), 1)
        )
    }

    private func nonnegative(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
}
