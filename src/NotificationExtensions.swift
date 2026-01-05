import Foundation

extension Notification.Name {
    static let settingsDidChange = Notification.Name("SettingsDidChange")
}

extension Settings {
    static func saveAndNotify(_ settings: Settings) throws {
        try save(settings)
        NotificationCenter.default.post(name: .settingsDidChange, object: settings)
    }
}
