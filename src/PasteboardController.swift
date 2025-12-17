import AppKit

@MainActor
final class PasteboardController {
  struct Snapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
  }

  enum PasteboardError: Error, LocalizedError {
    case noChange
    case noString

    var errorDescription: String? {
      switch self {
      case .noChange:
        return "Copy failed (no text copied)"
      case .noString:
        return "Copy failed (clipboard has no text)"
      }
    }
  }

  var changeCount: Int {
    NSPasteboard.general.changeCount
  }

  func snapshot() -> Snapshot {
    let pb = NSPasteboard.general
    let items = pb.pasteboardItems ?? []

    let stored = items.map { item -> [NSPasteboard.PasteboardType: Data] in
      var dict: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) {
          dict[type] = data
        }
      }
      return dict
    }

    return Snapshot(items: stored)
  }

  func restore(_ snapshot: Snapshot) {
    let pb = NSPasteboard.general
    pb.clearContents()

    let items: [NSPasteboardItem] = snapshot.items.map { dict in
      let item = NSPasteboardItem()
      for (type, data) in dict {
        item.setData(data, forType: type)
      }
      return item
    }

    _ = pb.writeObjects(items)
  }

  func setString(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
  }

  func waitForCopiedString(after previousChangeCount: Int, excluding excluded: String?, timeout: Duration) async throws -> String {
    let deadline = ContinuousClock.now + timeout
    var sawChange = false

    while ContinuousClock.now < deadline {
      if NSPasteboard.general.changeCount != previousChangeCount {
        sawChange = true
        if let string = NSPasteboard.general.string(forType: .string), !string.isEmpty {
          if let excluded, string == excluded {
            // keep waiting
          } else {
            return string
          }
        }
      }
      try await Task.sleep(for: .milliseconds(30))
    }

    throw sawChange ? PasteboardError.noString : PasteboardError.noChange
  }
}
