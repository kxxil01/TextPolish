import AppKit
import Foundation

private func makeIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocusFlipped(false)
  defer { image.unlockFocus() }

  NSGraphicsContext.current?.imageInterpolation = .high

  let rect = NSRect(x: 0, y: 0, width: size, height: size)
  NSColor.clear.setFill()
  rect.fill()

  let inset = size * 0.06
  let bgRect = rect.insetBy(dx: inset, dy: inset)
  let radius = size * 0.22
  let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
  bgPath.addClip()

  let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.18, green: 0.86, blue: 0.92, alpha: 1.0),
  ])!
  gradient.draw(in: bgRect, angle: 315)

  let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.22),
    NSColor.white.withAlphaComponent(0.0),
  ])!
  highlight.draw(in: bgRect, angle: 90)

  guard let symbol = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: nil) else {
    return image
  }

  let symbolSize = size * 0.58
  let baseConfig = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
  let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: .white)
  let config = baseConfig.applying(colorConfig)
  let tinted = symbol.withSymbolConfiguration(config) ?? symbol

  let target = NSRect(
    x: (size - symbolSize) / 2.0,
    y: (size - symbolSize) / 2.0,
    width: symbolSize,
    height: symbolSize
  )

  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
  shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
  shadow.shadowBlurRadius = size * 0.035
  shadow.set()

  tinted.draw(in: target)

  return image
}

private func writePNG(_ image: NSImage, to url: URL) throws {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let data = rep.representation(using: .png, properties: [:])
  else {
    throw NSError(domain: "TextPolish", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
  }

  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try data.write(to: url, options: [.atomic])
}

let args = CommandLine.arguments
guard args.count >= 2 else {
  fputs("Usage: IconGenerator <output.png>\n", stderr)
  exit(2)
}

let outputURL = URL(fileURLWithPath: args[1])
let icon = makeIcon(size: 1024)
do {
  try writePNG(icon, to: outputURL)
} catch {
  fputs("IconGenerator failed: \(error)\n", stderr)
  exit(1)
}
