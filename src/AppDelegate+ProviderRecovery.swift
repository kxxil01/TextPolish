import AppKit
import Foundation

/// Recovering from provider errors: model auto-detection, fallback decisions, and reading API keys.
extension AppDelegate {
    func normalizeGeminiModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    func recoverFromError(_ error: Error) async -> CorrectionController.RecoveryAction? {
        switch settings.provider {
        case .gemini:
            guard let geminiError = error as? GeminiCorrector.GeminiError else { return nil }
            if case let .requestFailed(status, _) = geminiError, status == 404 {
                guard let apiKey = await currentGeminiApiKey() else { return nil }
                do {
                    let models = try await fetchGeminiModels(apiKey: apiKey)
                    guard let chosenRaw = chooseGeminiModel(from: models) else { return nil }
                    let chosen = normalizeGeminiModel(chosenRaw)
                    let current = normalizeGeminiModel(settings.geminiModel)
                    guard !chosen.isEmpty, chosen != current else { return nil }

                    applySettingsMutation { $0.geminiModel = chosen }
                    refreshCorrector()
                    return CorrectionController.RecoveryAction(message: "Gemini model auto-detected: \(chosen)", corrector: nil)
                } catch {
                    TPLogger.log("Auto-detect Gemini model failed: \(error)")
                }
            }

            return nil
        case .openRouter:
            guard let openRouterError = error as? OpenRouterCorrector.OpenRouterError else { return nil }

            guard case let .requestFailed(status, _) = openRouterError else { return nil }
            guard status == 404 || status == 402 else { return nil }
            guard let apiKey = await currentOpenRouterApiKey() else { return nil }

            do {
                let current = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let chosen = try await detectWorkingOpenRouterModel(
                    apiKey: apiKey,
                    preferFree: true,
                    preferredFirst: nil,
                    excluding: current.isEmpty ? nil : current
                ) else { return nil }

                applySettingsMutation { $0.openRouterModel = chosen }
                refreshCorrector()
                let message = "OpenRouter switched to a working free model: \(chosen)"
                return CorrectionController.RecoveryAction(message: message, corrector: nil)
            } catch {
                TPLogger.log("Auto-detect OpenRouter model failed: \(error)")
                return nil
            }
        case .openAI:
            return nil
        case .anthropic, .custom:
            return nil
        }
    }

    func shouldAttemptFallback(for error: Error) -> Bool {
        guard settings.enableGeminiOpenRouterFallback else { return false }
        guard shouldFallbackFromError(error) else { return false }

        // Runs on the main thread mid-Polish, so it must not read the secret: a keychain
        // prompt here froze the app with the prompt holding keyboard focus.
        let fallbackProvider: Settings.Provider
        switch settings.provider {
        case .gemini:
            fallbackProvider = .openRouter
        case .openRouter:
            fallbackProvider = .gemini
        case .openAI:
            fallbackProvider = .anthropic
        case .anthropic:
            fallbackProvider = .openAI
        case .custom:
            return false
        }
        return ProviderCredentials.isConfigured(for: fallbackProvider, settings: settings)
    }

    private func shouldFallbackFromError(_ error: Error) -> Bool {
        if let geminiError = error as? GeminiCorrector.GeminiError {
            return shouldFallbackFromGeminiError(geminiError)
        }
        if let openRouterError = error as? OpenRouterCorrector.OpenRouterError {
            return shouldFallbackFromOpenRouterError(openRouterError)
        }
        if let openAIError = error as? OpenAICorrector.OpenAIError {
            return shouldFallbackFromOpenAIError(openAIError)
        }
        if let anthropicError = error as? AnthropicCorrector.AnthropicError {
            return shouldFallbackFromAnthropicError(anthropicError)
        }
        if let urlError = error as? URLError {
            return shouldFallbackFromURLError(urlError)
        }
        return false
    }

    private func shouldFallbackFromGeminiError(_ error: GeminiCorrector.GeminiError) -> Bool {
        switch error {
        case .missingApiKey, .invalidBaseURL:
            return false
        case .blocked, .emptyResponse, .overRewrite:
            // Provider returned an unusable response; fallback can still salvage the user flow.
            return true
        case let .requestFailed(status, _):
            if status == 401 || status == 403 {
                return false
            }
            if status == 429 {
                return true
            }
            if status <= 0 {
                return true
            }
            return (500 ... 599).contains(status)
        }
    }

    private func shouldFallbackFromOpenRouterError(_ error: OpenRouterCorrector.OpenRouterError) -> Bool {
        switch error {
        case .missingApiKey, .invalidBaseURL:
            return false
        case .emptyResponse, .overRewrite:
            return true
        case let .requestFailed(status, _):
            if status == 401 || status == 403 || status == 402 {
                return false
            }
            if status == 429 {
                return true
            }
            if status <= 0 {
                return true
            }
            return (500 ... 599).contains(status)
        }
    }

    private func shouldFallbackFromOpenAIError(_ error: OpenAICorrector.OpenAIError) -> Bool {
        switch error {
        case .missingApiKey, .invalidBaseURL, .invalidModel:
            return false
        case .emptyResponse, .overRewrite:
            return true
        case let .requestFailed(status, _):
            if status == 401 || status == 403 || status == 402 {
                return false
            }
            if status == 429 {
                return true
            }
            if status <= 0 {
                return true
            }
            return (500 ... 599).contains(status)
        }
    }

    private func shouldFallbackFromAnthropicError(_ error: AnthropicCorrector.AnthropicError) -> Bool {
        switch error {
        case .missingApiKey, .invalidBaseURL, .invalidModel:
            return false
        case .emptyResponse, .overRewrite:
            return true
        case let .requestFailed(status, _):
            if status == 401 || status == 403 {
                return false
            }
            if status == 429 || status == 529 {
                return true
            }
            if status <= 0 {
                return true
            }
            return (500 ... 599).contains(status)
        }
    }

    private func shouldFallbackFromURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    func currentGeminiApiKey() async -> String? {
        if let keyFromKeychain = await Keychain.loadConfiguredPassword(
            primaryService: keychainService,
            account: keychainAccountGemini
        ), !keyFromKeychain.isEmpty {
            return keyFromKeychain
        }

        let keyFromSettings = settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !keyFromSettings.isEmpty { return keyFromSettings }

        let env =
            ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ??
            ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ??
            ""
        let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyFromEnv.isEmpty ? nil : keyFromEnv
    }

    func currentOpenRouterApiKey() async -> String? {
        if let keyFromKeychain = await Keychain.loadConfiguredPassword(
            primaryService: keychainService,
            account: keychainAccountOpenRouter
        ), !keyFromKeychain.isEmpty {
            return keyFromKeychain
        }

        let keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !keyFromSettings.isEmpty { return keyFromSettings }

        let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyFromEnv.isEmpty ? nil : keyFromEnv
    }

    func currentOpenAIApiKey() async -> String? {
        if let keyFromKeychain = await Keychain.loadConfiguredPassword(
            primaryService: keychainService,
            account: keychainAccountOpenAI
        ), !keyFromKeychain.isEmpty {
            return keyFromKeychain
        }

        let keyFromSettings = settings.openAIApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !keyFromSettings.isEmpty { return keyFromSettings }

        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyFromEnv.isEmpty ? nil : keyFromEnv
    }

    func currentAnthropicApiKey() async -> String? {
        if let keyFromKeychain = await Keychain.loadConfiguredPassword(
            primaryService: keychainService,
            account: keychainAccountAnthropic
        ), !keyFromKeychain.isEmpty {
            return keyFromKeychain
        }

        let keyFromSettings = settings.anthropicApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !keyFromSettings.isEmpty { return keyFromSettings }

        let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyFromEnv.isEmpty ? nil : keyFromEnv
    }

    private struct GeminiModelsResponse: Decodable {
        struct Model: Decodable {
            let name: String
            let supportedGenerationMethods: [String]?
        }

        let models: [Model]?
    }

    private struct OpenRouterModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]?
    }

    private struct OpenRouterChatCompletionsResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message?
        }

        let choices: [Choice]?
    }

    private struct OpenAIErrorEnvelope: Decodable {
        struct ErrorBody: Decodable {
            let message: String?
            let code: String?
            let type: String?
        }

        let error: ErrorBody?
    }

    func parseOpenAIErrorMessage(data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
            if let message, !message.isEmpty { return message }
        }

        if let string = String(data: data, encoding: .utf8) {
            return ErrorLogSanitizer.sanitize(string)
        }

        return nil
    }

    private func parseOpenRouterErrorMessage(data: Data) -> String? {
        parseOpenAIErrorMessage(data: data)
    }

    private struct AnthropicDiagnosticsErrorEnvelope: Decodable {
        struct ErrorBody: Decodable {
            let message: String?
            let type: String?
        }

        let error: ErrorBody?
    }

    func parseAnthropicErrorMessage(data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(AnthropicDiagnosticsErrorEnvelope.self, from: data) {
            let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
            if let message, !message.isEmpty { return message }
        }

        if let string = String(data: data, encoding: .utf8) {
            return ErrorLogSanitizer.sanitize(string)
        }

        return nil
    }

    private func makeOpenRouterChatCompletionsURL() throws -> URL {
        guard let baseURL = URL(string: settings.openRouterBaseURL) else {
            throw NSError(domain: "TextPolish", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "TextPolish", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
        }
        components.path = OpenRouterEndpointPath.chatCompletionsPath(basePath: components.path)
        guard let url = components.url else {
            throw NSError(domain: "TextPolish", code: 21, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter URL"])
        }
        return url
    }

    private static func probeOpenRouterModel(
        url: URL,
        timeoutSeconds: Double,
        apiKey: String,
        model: String
    ) async throws -> Bool {
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("TextPolish", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/kxxil01", forHTTPHeaderField: "HTTP-Referer")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "Reply with ONLY the word OK."],
            ],
            "temperature": 0.0,
            "max_tokens": 8,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }

        if (200 ..< 300).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(OpenRouterChatCompletionsResponse.self, from: data)
            let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !content.isEmpty
        }

        let parsedMessage: String? = {
            if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data),
               let message = decoded.error?.message,
               !message.isEmpty
            {
                return message
            }
            return String(data: data, encoding: .utf8)
        }()
        let message = ErrorLogSanitizer.sanitize(parsedMessage)
        TPLogger.log("OpenRouter probe HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
        if http.statusCode == 401 {
            throw NSError(
                domain: "TextPolish",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "OpenRouter unauthorized (401) — check API key"]
            )
        }
        return false
    }

    func detectWorkingOpenRouterModel(
        apiKey: String,
        preferFree: Bool,
        preferredFirst: String?,
        excluding: String?,
        prefetchedModels: [String]? = nil
    ) async throws -> String? {
        let models: [String]
        if let prefetchedModels {
            models = prefetchedModels
        } else {
            models = try await fetchOpenRouterModels(apiKey: apiKey)
        }
        let candidates = rankedOpenRouterModels(
            from: models,
            preferFree: preferFree,
            preferredFirst: preferredFirst,
            excluding: excluding
        )
        var deduplicated: [String] = []
        var seen = Set<String>()
        for rawModel in candidates {
            let trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            deduplicated.append(trimmed)
        }
        let maxProbeCandidates = 9
        if deduplicated.count > maxProbeCandidates {
            deduplicated = Array(deduplicated.prefix(maxProbeCandidates))
        }
        guard !deduplicated.isEmpty else { return nil }

        let probeURL = try makeOpenRouterChatCompletionsURL()
        let probeTimeoutSeconds = max(1.0, min(settings.requestTimeoutSeconds, 4.0))

        if let preferred = deduplicated.first,
           try await Self.probeOpenRouterModel(
               url: probeURL,
               timeoutSeconds: probeTimeoutSeconds,
               apiKey: apiKey,
               model: preferred
           )
        {
            return preferred
        }

        let remaining = Array(deduplicated.dropFirst())
        let batchSize = 3
        var batchStart = 0

        while batchStart < remaining.count {
            let batchEnd = min(batchStart + batchSize, remaining.count)
            let batch = Array(remaining[batchStart ..< batchEnd])

            let firstSuccessIndex = try await withThrowingTaskGroup(of: (Int, Bool).self, returning: Int?.self) { group in
                for (index, model) in batch.enumerated() {
                    group.addTask {
                        let success = try await Self.probeOpenRouterModel(
                            url: probeURL,
                            timeoutSeconds: probeTimeoutSeconds,
                            apiKey: apiKey,
                            model: model
                        )
                        return (index, success)
                    }
                }

                var outcomesByIndex: [Int: Bool] = [:]
                var nextResolvableIndex = 0
                for try await (index, success) in group {
                    outcomesByIndex[index] = success
                    while let outcome = outcomesByIndex[nextResolvableIndex] {
                        if outcome {
                            group.cancelAll()
                            return nextResolvableIndex
                        }
                        nextResolvableIndex += 1
                    }
                }
                return nil
            }

            if let firstSuccessIndex {
                return batch[firstSuccessIndex]
            }

            batchStart = batchEnd
        }

        return nil
    }

    func fetchOpenRouterModels(apiKey: String) async throws -> [String] {
        guard let baseURL = URL(string: settings.openRouterBaseURL) else {
            throw NSError(domain: "TextPolish", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "TextPolish", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
        }

        components.path = OpenRouterEndpointPath.modelsPath(basePath: components.path)

        guard let url = components.url else {
            throw NSError(domain: "TextPolish", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid models URL"])
        }

        var request = URLRequest(url: url, timeoutInterval: settings.requestTimeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "TextPolish", code: 12, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }

        if (200 ..< 300).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let models = decoded.data ?? []
            return models.map(\.id)
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        throw NSError(
            domain: "TextPolish",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(text.prefix(240))"]
        )
    }

    func fetchGeminiModels(apiKey: String) async throws -> [String] {
        guard let baseURL = URL(string: settings.geminiBaseURL) else {
            throw NSError(domain: "TextPolish", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini base URL"])
        }

        let versionsToTry = ["v1beta", "v1"]
        var lastError: Error?

        for (index, version) in versionsToTry.enumerated() {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                throw NSError(domain: "TextPolish", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini base URL"])
            }
            components.path = GeminiEndpointPath.modelsPath(basePath: components.path, apiVersion: version)

            var items = components.queryItems ?? []
            items.removeAll { $0.name == "key" }
            items.append(URLQueryItem(name: "key", value: apiKey))
            components.queryItems = items
            guard let url = components.url else {
                throw NSError(domain: "TextPolish", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid models URL"])
            }

            var request = URLRequest(url: url, timeoutInterval: settings.requestTimeoutSeconds)
            request.httpMethod = "GET"
            request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = NSError(domain: "TextPolish", code: 3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                continue
            }

            if (200 ..< 300).contains(http.statusCode) {
                let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
                let models = decoded.models ?? []
                return models.compactMap { model in
                    let supports = model.supportedGenerationMethods ?? []
                    guard supports.isEmpty || supports.contains("generateContent") else { return nil }
                    return model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name
                }
            }

            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let error = NSError(
                domain: "TextPolish",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: text.isEmpty
                        ? "HTTP \(http.statusCode)"
                        : "HTTP \(http.statusCode): \(text.prefix(240))",
                ]
            )

            if http.statusCode == 404, index < versionsToTry.count - 1 {
                lastError = error
                continue
            }

            throw error
        }

        throw lastError ?? NSError(domain: "TextPolish", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
    }

    func chooseGeminiModel(from models: [String]) -> String? {
        guard !models.isEmpty else { return nil }

        func score(_ name: String) -> Int {
            let lower = name.lowercased()
            var value = 0
            if lower == "gemini-2.5-flash-lite" { value += 200 }
            if lower == "gemini-2.5-flash" { value += 180 }
            if lower.contains("flash") { value += 100 }
            if lower.contains("2.5") { value += 120 }
            if lower.contains("2.0") { value -= 20 }
            if lower.contains("1.5") { value += 10 }
            if lower.contains("lite") { value += 10 }
            if lower.contains("latest") { value += 5 }
            if lower.contains("preview") { value -= 50 }
            if lower.contains("exp") || lower.contains("experimental") { value -= 50 }
            if lower.contains("pro") { value -= 5 }
            return value
        }

        return models
            .map { ($0, score($0)) }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    // Legacy hotspot: split this up before removing the suppression.
    // swiftlint:disable:next cyclomatic_complexity
    private func openRouterScore(_ id: String) -> Int {
        let lower = id.lowercased()
        var value = 0
        if lower == "google/gemma-3n-e4b-it:free" { value += 980 }
        if lower == "qwen/qwen3-4b:free" { value += 940 }
        if lower == "meta-llama/llama-3.2-3b-instruct:free" { value += 900 }
        if lower == "google/gemma-3-12b-it:free" { value += 860 }
        if lower == "google/gemma-3-27b-it:free" { value += 820 }
        if lower == "openai/gpt-5-nano" { value += 780 }
        if lower.contains("gemini") { value += 220 }
        if lower.contains("flash") { value += 220 }
        if lower.contains("2.0") { value += 50 }
        if lower.contains("lite") { value += 30 }
        if lower.contains("gpt-5-nano") { value += 260 }
        if lower.contains("gpt-4o-mini") { value += 180 }
        if lower.contains("gemma-3n") { value += 200 }
        if lower.contains("4b") { value += 120 }
        if lower.contains("llama-3.2") { value += 90 }
        if lower.contains("3b") { value += 30 }
        if lower.contains("instruct") { value += 20 }
        if lower.contains(":free") { value += 40 }
        if lower.contains("preview") { value -= 40 }
        if lower.contains("think") { value -= 90 }
        if lower.contains("creative") { value -= 40 }
        return value
    }

    func rankedOpenRouterModels(
        from models: [String],
        preferFree: Bool,
        preferredFirst: String?,
        excluding: String?
    ) -> [String] {
        guard !models.isEmpty else { return [] }

        let filtered = preferFree ? models.filter { $0.hasSuffix(":free") } : models
        var pool = filtered
        if let excluding, !excluding.isEmpty {
            pool.removeAll { $0 == excluding }
        }

        pool.sort(by: { openRouterScore($0) > openRouterScore($1) })

        guard let preferredFirst, !preferredFirst.isEmpty else { return pool }
        if preferredFirst == excluding { return pool }
        if preferFree, !preferredFirst.hasSuffix(":free") { return pool }

        var result: [String] = [preferredFirst]
        result.append(contentsOf: pool.filter { $0 != preferredFirst })
        return result
    }
}
