import Foundation
import Sparkle

struct UpdateCheckFeedback {
  enum Kind {
    case info
    case error
  }

  let kind: Kind
  let message: String

  static func fromSparkleError(_ error: NSError) -> UpdateCheckFeedback {
    if error.domain == SUSparkleErrorDomain, let sparkleError = SUError(rawValue: Int32(error.code)) {
      switch sparkleError {
      case .noUpdateError:
        return UpdateCheckFeedback(kind: .info, message: "You're up to date.")
      case .installationCanceledError:
        return UpdateCheckFeedback(kind: .info, message: "Update canceled.")
      default:
        break
      }
    }
    return UpdateCheckFeedback(kind: .error, message: "Update check failed.")
  }
}
