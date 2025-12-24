enum UpdateStatus: Equatable {
  case unknown
  case checking
  case available
  case upToDate
  case message(String)

  var menuTitle: String {
    switch self {
    case .unknown:
      return "Update status: Unknown"
    case .checking:
      return "Update status: Checking..."
    case .available:
      return "Update status: Update available"
    case .upToDate:
      return "Update status: Up to date"
    case .message(let message):
      return "Update status: \(message)"
    }
  }
}
