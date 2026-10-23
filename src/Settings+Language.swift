import Foundation

extension Settings {
  enum CorrectionLanguage: String, Codable, Sendable {
    case auto = "auto"
    case englishUS = "en-US"
    case indonesian = "id-ID"

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      switch raw {
      case "en-us", "en_us", "english", "english-us", "english_us":
        self = .englishUS
      case "id-id", "id_id", "indonesian", "bahasa", "bahasa-indonesia", "bahasa_indonesia", "id":
        self = .indonesian
      default:
        self = .auto
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }

    var displayName: String {
      switch self {
      case .auto:
        return "Auto"
      case .englishUS:
        return "English (US)"
      case .indonesian:
        return "Indonesian"
      }
    }

    var promptInstruction: String? {
      switch self {
      case .auto:
        return nil
      case .englishUS:
        return "Language: English (US). Correct in English (US). Do not translate."
      case .indonesian:
        return "Language: Indonesian. Correct in Indonesian. Do not translate."
      }
    }
  }
}
