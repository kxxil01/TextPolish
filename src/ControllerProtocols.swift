import Foundation

@MainActor
protocol KeyboardControlling {
  func isAccessibilityTrusted(prompt: Bool) -> Bool
  func sendCommandA()
  func sendCommandC()
  func sendCommandV()
}

@MainActor
protocol PasteboardControlling {
  func snapshot() -> PasteboardController.Snapshot
  func restore(_ snapshot: PasteboardController.Snapshot)
  func setString(_ string: String)
  var changeCount: Int { get }
  func waitForCopiedString(after previousChangeCount: Int, excluding excluded: String?, timeout: Duration) async throws -> String
}

extension KeyboardController: KeyboardControlling {}
extension PasteboardController: PasteboardControlling {}
