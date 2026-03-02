import Foundation

enum ModelDetector {
    enum DetectorError: Error, LocalizedError, Equatable {
        case noApiKey
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey:
                return "API key is required"
            case .requestFailed(let message):
                return message
            }
        }
    }

    static func detectGeminiModel(apiKey: String, baseURL: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetectorError.noApiKey
        }

        guard let url = URL(string: baseURL) else {
            throw DetectorError.requestFailed("Invalid base URL")
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.path = "/v1beta/models"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("TextPolish/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DetectorError.requestFailed("Invalid response")
            }

            if http.statusCode != 200 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw DetectorError.requestFailed("HTTP \(http.statusCode): \(message)")
            }

            let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)

            // Prefer stable lightweight Gemini models first, then any flash model.
            if let preferred = decoded.models?.first(where: { $0.name == "gemini-2.5-flash" }) {
                return preferred.name
            }
            if let preferredLite = decoded.models?.first(where: { $0.name == "gemini-2.5-flash-lite" }) {
                return preferredLite.name
            }
            if let flash = decoded.models?.first(where: { $0.name.contains("flash") && !$0.name.contains("preview") && !$0.name.contains("exp") }) {
                return flash.name
            }
            if let first = decoded.models?.first {
                return first.name
            }

            throw DetectorError.requestFailed("No models found")
        } catch let error as DetectorError {
            throw error
        } catch {
            throw DetectorError.requestFailed(error.localizedDescription)
        }
    }

    static func detectOpenRouterModel(apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetectorError.noApiKey
        }

        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("TextPolish/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DetectorError.requestFailed("Invalid response")
            }

            if http.statusCode != 200 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw DetectorError.requestFailed("HTTP \(http.statusCode): \(message)")
            }

            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

            // Prefer lightweight free models, then any free model.
            let freeModels = decoded.data?.filter { $0.pricing?.prompt == "0" && $0.pricing?.completion == "0" } ?? []
            if let preferredLightFree = freeModels.first(where: {
                let id = $0.id.lowercased()
                return id.contains("mini") || id.contains("lite") || id.contains("flash") || id.contains("4b") || id.contains("3b")
            }) {
                return preferredLightFree.id
            }
            if let freeModel = freeModels.first {
                return freeModel.id
            }
            if let first = decoded.data?.first {
                return first.id
            }

            throw DetectorError.requestFailed("No models found")
        } catch let error as DetectorError {
            throw error
        } catch {
            throw DetectorError.requestFailed(error.localizedDescription)
        }
    }

    struct GeminiModelsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]?
    }

    struct OpenRouterModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
            let pricing: Pricing?
        }
        struct Pricing: Decodable {
            let prompt: String?
            let completion: String?
        }
        let data: [Model]?
    }
}
