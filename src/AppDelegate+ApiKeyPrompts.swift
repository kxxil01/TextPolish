import AppKit
import Foundation

/// Menu prompts for entering or clearing each provider's API key.
extension AppDelegate {
    @objc func setGeminiApiKey() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let result = self.promptForApiKey(
                title: "Gemini API Key",
                message: Self.apiKeyPromptMessage
            )
            TPLogger.log("Gemini key prompt result=\(self.apiKeyPromptResultKind(result))")

            switch result {
            case .canceled:
                return
            case .clear:
                self.feedback?.showInfo("Clearing Gemini key…")
                do {
                    try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountGemini)
                    self.applySettingsMutation { $0.geminiApiKey = nil }
                    self.feedback?.showInfo("Gemini key cleared")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to clear key: \(error)")
                    self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
                }
            case let .save(value):
                self.feedback?.showInfo("Saving Gemini key… (check for a Keychain prompt)")
                do {
                    try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountGemini)
                    self.applySettingsMutation { $0.geminiApiKey = nil }
                    self.feedback?.showInfo("Gemini key saved")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to save key: \(error)")
                    self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
                }
            }
        }
    }

    @objc func setOpenRouterApiKey() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let result = self.promptForApiKey(
                title: "OpenRouter API Key",
                message: Self.apiKeyPromptMessage
            )
            TPLogger.log("OpenRouter key prompt result=\(self.apiKeyPromptResultKind(result))")

            switch result {
            case .canceled:
                return
            case .clear:
                self.feedback?.showInfo("Clearing OpenRouter key…")
                do {
                    try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountOpenRouter)
                    self.applySettingsMutation { $0.openRouterApiKey = nil }
                    self.feedback?.showInfo("OpenRouter key cleared")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to clear key: \(error)")
                    self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
                }
            case let .save(value):
                self.feedback?.showInfo("Saving OpenRouter key… (check for a Keychain prompt)")
                do {
                    try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountOpenRouter)
                    self.applySettingsMutation { $0.openRouterApiKey = nil }
                    self.feedback?.showInfo("OpenRouter key saved")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to save key: \(error)")
                    self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
                }
            }
        }
    }

    @objc func setOpenAIApiKey() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let result = self.promptForApiKey(
                title: "OpenAI API Key",
                message: Self.apiKeyPromptMessage
            )
            TPLogger.log("OpenAI key prompt completed")

            switch result {
            case .canceled:
                return
            case .clear:
                self.feedback?.showInfo("Clearing OpenAI key…")
                do {
                    try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountOpenAI)
                    self.applySettingsMutation { $0.openAIApiKey = nil }
                    self.feedback?.showInfo("OpenAI key cleared")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to clear key: \(error)")
                    self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
                }
            case let .save(value):
                self.feedback?.showInfo("Saving OpenAI key… (check for a Keychain prompt)")
                do {
                    try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountOpenAI)
                    self.applySettingsMutation { $0.openAIApiKey = nil }
                    self.feedback?.showInfo("OpenAI key saved")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to save key: \(error)")
                    self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
                }
            }
        }
    }

    @objc func setAnthropicApiKey() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let result = self.promptForApiKey(
                title: "Anthropic API Key",
                message: Self.apiKeyPromptMessage
            )
            TPLogger.log("Anthropic key prompt completed")

            switch result {
            case .canceled:
                return
            case .clear:
                self.feedback?.showInfo("Clearing Anthropic key…")
                do {
                    try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountAnthropic)
                    self.applySettingsMutation { $0.anthropicApiKey = nil }
                    self.feedback?.showInfo("Anthropic key cleared")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to clear key: \(error)")
                    self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
                }
            case let .save(value):
                self.feedback?.showInfo("Saving Anthropic key… (check for a Keychain prompt)")
                do {
                    try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountAnthropic)
                    self.applySettingsMutation { $0.anthropicApiKey = nil }
                    self.feedback?.showInfo("Anthropic key saved")
                    self.refreshCorrector()
                } catch {
                    TPLogger.log("Failed to save key: \(error)")
                    self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
                }
            }
        }
    }

    private func showSimpleAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private enum ApiKeyPromptResult {
        case save(String)
        case clear
        case canceled
    }

    private func apiKeyPromptResultKind(_ result: ApiKeyPromptResult) -> String {
        switch result {
        case .save:
            return "save"
        case .clear:
            return "clear"
        case .canceled:
            return "canceled"
        }
    }

    private func promptForApiKey(title: String, message: String) -> ApiKeyPromptResult {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Paste API key (⌘V or ⌃V)"
        field.isEditable = true
        field.isSelectable = true
        field.allowsEditingTextAttributes = false
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingMiddle
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        alert.accessoryView = field

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear")

        let window = alert.window
        window.level = .floating
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window, window.isVisible else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let wantsPaste =
                (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)) &&
                event.charactersIgnoringModifiers?.lowercased() == "v"
            if wantsPaste {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            }
            return event
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        let response = alert.runModal()
        window.orderOut(nil)
        switch response {
        case .alertFirstButtonReturn: // Save
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                NSSound.beep()
                return .canceled
            }
            return .save(value)
        case .alertThirdButtonReturn: // Clear
            return .clear
        default:
            return .canceled
        }
    }
}
