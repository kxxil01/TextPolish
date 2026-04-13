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
        let requestURL = try makeGeminiModelsURL(baseURL: baseURL, apiKey: apiKey)

        var request = URLRequest(url: requestURL)
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

            if let selectedModel = selectPreferredGeminiModel(from: decoded.models ?? []) {
                return selectedModel
            }

            throw DetectorError.requestFailed("No models found")
        } catch let error as DetectorError {
            throw error
        } catch {
            throw DetectorError.requestFailed(error.localizedDescription)
        }
    }

    static func makeGeminiModelsURL(baseURL: String, apiKey: String) throws -> URL {
        guard let url = URL(string: baseURL) else {
            throw DetectorError.requestFailed("Invalid base URL")
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DetectorError.requestFailed("Invalid base URL")
        }
        components.path = GeminiEndpointPath.modelsPath(basePath: components.path, apiVersion: "v1beta")

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "key" }
        items.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = items

        guard let requestURL = components.url else {
            throw DetectorError.requestFailed("Invalid Gemini models URL")
        }
        return requestURL
    }

    static func selectPreferredGeminiModel(from models: [GeminiModelsResponse.Model]) -> String? {
        let normalizedNames = models.map { normalizeGeminiModelName($0.name) }

        // Prefer stable lightweight Gemini models first, then any flash model.
        if let preferred = normalizedNames.first(where: { $0 == "gemini-2.5-flash" }) {
            return preferred
        }
        if let preferredLite = normalizedNames.first(where: { $0 == "gemini-2.5-flash-lite" }) {
            return preferredLite
        }
        if let flash = normalizedNames.first(where: {
            let lower = $0.lowercased()
            return lower.contains("flash") && !lower.contains("preview") && !lower.contains("exp")
        }) {
            return flash
        }
        if let first = normalizedNames.first {
            return first
        }
        return nil
    }

    static func detectOpenRouterModel(
        apiKey: String,
        baseURL: String = "https://openrouter.ai/api/v1"
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetectorError.noApiKey
        }

        let requestURL = try makeOpenRouterModelsURL(baseURL: baseURL)
        var request = URLRequest(url: requestURL)
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
            let freeModels = decoded.data?.filter {
                isFreePrice($0.pricing?.prompt) && isFreePrice($0.pricing?.completion)
            } ?? []
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

    static func detectOpenAIModel(
        apiKey: String,
        baseURL: String = "https://api.openai.com/v1"
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetectorError.noApiKey
        }

        let requestURL = try makeOpenAIModelsURL(baseURL: baseURL)
        var request = URLRequest(url: requestURL)
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

            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let gptModels = decoded.data?.filter { $0.id.lowercased().hasPrefix("gpt") } ?? []

            if let preferred = gptModels.first(where: {
                let id = $0.id.lowercased()
                return id.contains("nano") || id.contains("mini")
            }) {
                return preferred.id
            }
            if let gpt = gptModels.first {
                return gpt.id
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

    static func detectAnthropicModel(
        apiKey: String,
        baseURL: String = "https://api.anthropic.com"
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetectorError.noApiKey
        }

        let requestURL = try makeAnthropicModelsURL(baseURL: baseURL)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

            let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            let models = decoded.data ?? []

            if let preferred = models.first(where: {
                let id = $0.id.lowercased()
                return id.contains("haiku")
            }) {
                return preferred.id
            }
            if let sonnet = models.first(where: {
                $0.id.lowercased().contains("sonnet")
            }) {
                return sonnet.id
            }
            if let first = models.first {
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

    struct OpenAIModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }
        let data: [Model]?
    }

    struct AnthropicModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }
        let data: [Model]?
    }

    static func makeOpenAIModelsURL(baseURL: String) throws -> URL {
        guard let url = URL(string: baseURL) else {
            throw DetectorError.requestFailed("Invalid OpenAI base URL")
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DetectorError.requestFailed("Invalid OpenAI base URL")
        }
        components.path = OpenAIEndpointPath.modelsPath(basePath: components.path)

        guard let requestURL = components.url else {
            throw DetectorError.requestFailed("Invalid OpenAI models URL")
        }
        return requestURL
    }

    static func makeAnthropicModelsURL(baseURL: String) throws -> URL {
        guard let url = URL(string: baseURL) else {
            throw DetectorError.requestFailed("Invalid Anthropic base URL")
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DetectorError.requestFailed("Invalid Anthropic base URL")
        }
        components.path = AnthropicEndpointPath.modelsPath(basePath: components.path)

        guard let requestURL = components.url else {
            throw DetectorError.requestFailed("Invalid Anthropic models URL")
        }
        return requestURL
    }

    private static func isFreePrice(_ value: String?) -> Bool {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return false }
        if trimmed == "0" || trimmed == "0.0" || trimmed == "0.00" {
            return true
        }
        if let decimal = Decimal(string: trimmed), decimal <= 0 {
            return true
        }
        if let numeric = Double(trimmed), numeric <= 0 {
            return true
        }
        return false
    }

    static func makeOpenRouterModelsURL(baseURL: String) throws -> URL {
        guard let url = URL(string: baseURL) else {
            throw DetectorError.requestFailed("Invalid OpenRouter base URL")
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DetectorError.requestFailed("Invalid OpenRouter base URL")
        }
        components.path = OpenRouterEndpointPath.modelsPath(basePath: components.path)

        guard let requestURL = components.url else {
            throw DetectorError.requestFailed("Invalid OpenRouter models URL")
        }
        return requestURL
    }

    private static func normalizeGeminiModelName(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }
}
