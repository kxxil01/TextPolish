import AppKit
import Foundation

/// The Diagnostics window: per-provider checks of the API key, model, and endpoint.
extension AppDelegate {
    @objc func openDiagnostics() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            if self.diagnosticsWindow == nil {
                self.diagnosticsWindow = DiagnosticsWindow()
            }
            self.diagnosticsWindow?.onRunDiagnostic = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.runActiveDiagnostic()
                }
            }
            self.diagnosticsWindow?.show()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func runActiveDiagnostic() async {
        diagnosticsWindow?.showRunning()
        let provider = settings.provider
        var lines: [String] = []
        lines.append("Provider: \(providerDisplayName(provider))")
        lines.append("─────────────────────────────────")

        switch provider {
        case .gemini:
            lines.append(contentsOf: await diagnoseGemini())
        case .openRouter:
            lines.append(contentsOf: await diagnoseOpenRouter())
        case .openAI:
            lines.append(contentsOf: await diagnoseOpenAI())
        case .anthropic:
            lines.append(contentsOf: await diagnoseAnthropic())
        }

        let result = lines.joined(separator: "\n")
        let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
        diagnosticsWindow?.showResult(
            normalized.isEmpty ? "Diagnostic completed, but no output was generated." : result
        )
    }

    private func providerDisplayName(_ provider: Settings.Provider) -> String {
        switch provider {
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    private func diagnoseGemini() async -> [String] {
        var lines: [String] = []
        var hasFailure = false
        guard let apiKey = await currentGeminiApiKey(), !apiKey.isEmpty else {
            lines.append("API Key: ✗ Not configured")
            lines.append("")
            lines.append("Set your Gemini API key in Settings or Keychain.")
            lines.append("")
            lines.append("Status: ✗ Not configured")
            return lines
        }
        lines.append("API Key: ✓ Found")
        lines.append("Model: \(settings.geminiModel)")
        lines.append("")

        // Fetch model list
        do {
            let models = try await fetchGeminiModels(apiKey: apiKey)
            lines.append("Available models (\(models.count)):")
            let displayModels = models.prefix(20)
            for model in displayModels {
                let marker = model == settings.geminiModel ? " ← current" : ""
                lines.append("  • \(model)\(marker)")
            }
            if models.count > 20 {
                lines.append("  … and \(models.count - 20) more")
            }

            if !models.contains(settings.geminiModel) {
                lines.append("")
                lines.append("⚠ Current model \"\(settings.geminiModel)\" not found in model list.")
                if let suggested = chooseGeminiModel(from: models) {
                    lines.append("  Suggested: \(suggested)")
                }
            }
        } catch {
            lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
            hasFailure = true
        }

        // Verify key works with a simple generation call
        lines.append("")
        lines.append("API Key Test:")
        do {
            let testResult = try await testGeminiApiKey(apiKey: apiKey, model: settings.geminiModel)
            if testResult {
                lines.append("  ✓ API key is valid and model responds")
            } else {
                lines.append("  ✗ API key or model issue — no response")
                hasFailure = true
            }
        } catch {
            lines.append("  ✗ \(error.localizedDescription)")
            hasFailure = true
        }

        lines.append("")
        lines.append("Status: \(hasFailure ? "✗ Failing checks" : "✓ Healthy")")

        return lines
    }

    private func diagnoseOpenRouter() async -> [String] {
        var lines: [String] = []
        var hasFailure = false
        guard let apiKey = await currentOpenRouterApiKey(), !apiKey.isEmpty else {
            lines.append("API Key: ✗ Not configured")
            lines.append("")
            lines.append("Set your OpenRouter API key in Settings or Keychain.")
            lines.append("")
            lines.append("Status: ✗ Not configured")
            return lines
        }

        lines.append("API Key: ✓ Found")
        lines.append("Current Model: \(settings.openRouterModel)")
        lines.append("")

        // Fetch free models
        lines.append("Scanning free models…")
        do {
            let allModels = try await fetchOpenRouterModels(apiKey: apiKey)
            let freeModels = allModels.filter { $0.hasSuffix(":free") }
            lines.removeLast() // remove "Scanning…"

            lines.append("Free models available (\(freeModels.count)):")
            let ranked = rankedOpenRouterModels(from: freeModels, preferFree: true, preferredFirst: nil, excluding: nil)
            let displayModels = ranked.prefix(15)
            for model in displayModels {
                let marker = model == settings.openRouterModel ? " ← current" : ""
                lines.append("  • \(model)\(marker)")
            }
            if ranked.count > 15 {
                lines.append("  … and \(ranked.count - 15) more")
            }

            // Auto-detect a working free model
            lines.append("")
            lines.append("Probing for a working free model…")
            if let working = try await detectWorkingOpenRouterModel(
                apiKey: apiKey,
                preferFree: true,
                preferredFirst: settings.openRouterModel,
                excluding: nil,
                prefetchedModels: allModels
            ) {
                if working == settings.openRouterModel {
                    lines.append("  ✓ Current model \"\(working)\" is working")
                } else {
                    applySettingsMutation { $0.openRouterModel = working }
                    lines.append("  ✓ Set model to \"\(working)\" (verified working)")
                }
            } else {
                lines.append("  ✗ No working free model found")
                hasFailure = true
            }
        } catch {
            lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
            hasFailure = true
        }

        lines.append("")
        lines.append("Status: \(hasFailure ? "✗ Failing checks" : "✓ Healthy")")

        return lines
    }

    private func diagnoseOpenAI() async -> [String] {
        var lines: [String] = []
        var hasFailure = false
        guard let apiKey = await currentOpenAIApiKey(), !apiKey.isEmpty else {
            lines.append("API Key: ✗ Not configured")
            lines.append("")
            lines.append("Set your OpenAI API key in Settings or Keychain.")
            lines.append("")
            lines.append("Status: ✗ Not configured")
            return lines
        }
        lines.append("API Key: ✓ Found")
        lines.append("Model: \(settings.openAIModel)")
        lines.append("")

        // Fetch model list
        do {
            let models = try await fetchOpenAIModels(apiKey: apiKey)
            let chatModels = models.filter(OpenAITokenPolicy.isChatModel).sorted()
            lines.append("Chat models (\(chatModels.count)):")
            let displayModels = chatModels.prefix(20)
            for model in displayModels {
                let marker = model == settings.openAIModel ? " ← current" : ""
                lines.append("  • \(model)\(marker)")
            }
            if chatModels.count > 20 {
                lines.append("  … and \(chatModels.count - 20) more")
            }

            if !chatModels.contains(settings.openAIModel), !models.contains(settings.openAIModel) {
                lines.append("")
                lines.append("⚠ Current model \"\(settings.openAIModel)\" not found.")
            } else if OpenAITokenPolicy.isModelFamily(settings.openAIModel),
                      !OpenAITokenPolicy.isChatModel(settings.openAIModel)
            {
                lines.append("")
                lines.append("⚠ \"\(settings.openAIModel)\" is not a chat model. Use Detect Model or set gpt-4.1-mini.")
            }
        } catch {
            lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
            hasFailure = true
        }

        // Verify key
        lines.append("")
        lines.append("API Key Test:")
        do {
            let testResult = try await testOpenAIApiKey(apiKey: apiKey, model: settings.openAIModel)
            if testResult {
                lines.append("  ✓ API key is valid and model responds")
            } else {
                lines.append("  ✗ API key or model issue — no response")
                hasFailure = true
            }
        } catch {
            lines.append("  ✗ \(error.localizedDescription)")
            hasFailure = true
        }

        lines.append("")
        lines.append("Status: \(hasFailure ? "✗ Failing checks" : "✓ Healthy")")

        return lines
    }

    private func diagnoseAnthropic() async -> [String] {
        var lines: [String] = []
        var hasFailure = false
        guard let apiKey = await currentAnthropicApiKey(), !apiKey.isEmpty else {
            lines.append("API Key: ✗ Not configured")
            lines.append("")
            lines.append("Set your Anthropic API key in Settings or Keychain.")
            lines.append("")
            lines.append("Status: ✗ Not configured")
            return lines
        }
        lines.append("API Key: ✓ Found")
        lines.append("Model: \(settings.anthropicModel)")
        lines.append("")

        // Anthropic doesn't have a public model list endpoint, so just verify the key
        lines.append("API Key Test:")
        do {
            let testResult = try await testAnthropicApiKey(apiKey: apiKey, model: settings.anthropicModel)
            if testResult {
                lines.append("  ✓ API key is valid and model responds")
            } else {
                lines.append("  ✗ API key or model issue — no response")
                hasFailure = true
            }
        } catch {
            lines.append("  ✗ \(error.localizedDescription)")
            hasFailure = true
        }

        lines.append("")
        lines.append("Status: \(hasFailure ? "✗ Failing checks" : "✓ Healthy")")

        return lines
    }

    // MARK: - Diagnostic API Helpers

    private func testGeminiApiKey(apiKey: String, model: String) async throws -> Bool {
        guard let baseURL = URL(string: settings.geminiBaseURL) else { return false }
        let normalizedModel = normalizeGeminiModel(model)
        let versionsToTry = ["v1beta", "v1"]

        for (index, version) in versionsToTry.enumerated() {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return false }
            components.path = GeminiEndpointPath.generateContentPath(
                basePath: components.path,
                apiVersion: version,
                model: normalizedModel
            )
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            guard let url = components.url else { return false }

            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "contents": [["parts": [["text": "Reply OK"]]]],
                "generationConfig": ["maxOutputTokens": 8],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200 ..< 300).contains(http.statusCode) {
                return true
            }
            if http.statusCode == 404, index < versionsToTry.count - 1 {
                continue
            }
            return false
        }

        return false
    }

    private func makeOpenAIModelsURL() throws -> URL {
        guard let baseURL = URL(string: settings.openAIBaseURL) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI base URL"])
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI base URL"])
        }

        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        if basePath.hasSuffix("/chat/completions") {
            basePath.removeLast("/chat/completions".count)
        } else if basePath.hasSuffix("/models") {
            basePath.removeLast("/models".count)
        }

        components.path = basePath.isEmpty ? "/models" : basePath + "/models"
        guard let url = components.url else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI models URL"])
        }
        return url
    }

    private func makeOpenAIChatCompletionsURLForDiagnostics() throws -> URL {
        guard let baseURL = URL(string: settings.openAIBaseURL) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI base URL"])
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI base URL"])
        }

        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        if basePath.hasSuffix("/chat/completions") {
            basePath.removeLast("/chat/completions".count)
        }

        components.path = basePath.isEmpty ? "/chat/completions" : basePath + "/chat/completions"
        guard let url = components.url else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI chat completions URL"])
        }
        return url
    }

    private func makeAnthropicMessagesURLForDiagnostics() throws -> URL {
        guard let baseURL = URL(string: settings.anthropicBaseURL) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Anthropic base URL"])
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Anthropic base URL"])
        }

        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        if basePath.hasSuffix("/v1/messages") {
            basePath.removeLast("/v1/messages".count)
        } else if basePath.hasSuffix("/v1") {
            basePath.removeLast("/v1".count)
        }

        components.path = basePath.isEmpty ? "/v1/messages" : basePath + "/v1/messages"
        guard let url = components.url else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Anthropic messages URL"])
        }
        return url
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        let url = try makeOpenAIModelsURL()
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NSError(domain: "TextPolish", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }

        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]?
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data?.map(\.id) ?? []
    }

    private func testOpenAIApiKey(apiKey: String, model: String) async throws -> Bool {
        let url = try makeOpenAIChatCompletionsURLForDiagnostics()
        let preferredUsesMaxCompletionTokens = OpenAITokenPolicy.usesMaxCompletionTokens(model: model)
        let tokenStrategies = preferredUsesMaxCompletionTokens ? [true, false] : [false, true]
        var lastError: Error?

        for (index, useMaxCompletionTokens) in tokenStrategies.enumerated() {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": "Reply OK"]],
            ]
            if useMaxCompletionTokens {
                body["max_completion_tokens"] = 8
            } else {
                body["max_tokens"] = 8
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    let error = NSError(
                        domain: "TextPolish",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]
                    )
                    lastError = error
                    continue
                }

                if (200 ..< 300).contains(http.statusCode) {
                    return true
                }

                let message = parseOpenAIErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
                let error = NSError(
                    domain: "TextPolish",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(message.prefix(240))"]
                )
                lastError = error

                if index == 0, OpenAITokenPolicy.isTokenParameterError(message: message) {
                    continue
                }
                throw error
            } catch {
                lastError = error
                if index == 0, OpenAITokenPolicy.isTokenParameterError(message: error.localizedDescription) {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(
            domain: "TextPolish",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "OpenAI API key test failed"]
        )
    }

    private func testAnthropicApiKey(apiKey: String, model: String) async throws -> Bool {
        let url = try makeAnthropicMessagesURLForDiagnostics()
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8,
            "messages": [["role": "user", "content": "Reply OK"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "TextPolish",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]
            )
        }

        if (200 ..< 300).contains(http.statusCode) {
            return true
        }

        let message = parseAnthropicErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
        throw NSError(
            domain: "TextPolish",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(message.prefix(240))"]
        )
    }
}
