import AppKit
import Foundation

/// TextPolish App Icon — "Quill + Sparkle" design.
/// Renders a 1024x1024 PNG. See `assets/AppIcon.svg` for the canonical vector source.
///
/// Design:
/// - Dark navy squircle background with top highlight
/// - White/silver quill feather with spine and barb texture
/// - Dark nib at bottom-left
/// - Gold AI sparkles around the quill
private func makeIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocusFlipped(false)
  defer { image.unlockFocus() }

  NSGraphicsContext.current?.imageInterpolation = .high

  // Scale factor: all coordinates below are authored at 1024; scale to `size`.
  let s = size / 1024.0

  // Clear canvas
  let canvas = NSRect(x: 0, y: 0, width: size, height: size)
  NSColor.clear.setFill()
  canvas.fill()

  // Squircle background — 6% inset, ~22% corner radius
  let inset = size * 0.0625
  let bgRect = canvas.insetBy(dx: inset, dy: inset)
  let radius = size * 0.225
  let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

  NSGraphicsContext.current?.saveGraphicsState()
  bgPath.addClip()

  // Dark navy gradient
  let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.102, green: 0.102, blue: 0.180, alpha: 1.0), // #1a1a2e
    NSColor(calibratedRed: 0.086, green: 0.129, blue: 0.243, alpha: 1.0), // #16213e
  ])!
  bgGradient.draw(in: bgRect, angle: 315)

  // Top highlight
  let highlight = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.18),
    NSColor.white.withAlphaComponent(0.0),
  ])!
  highlight.draw(in: bgRect, angle: 270)

  // Convert from SVG "y-down" authored coords (0..1024) to AppKit "y-up"
  // Helper closures to translate a point from SVG space into AppKit space at `size`.
  func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: x * s, y: (1024 - y) * s)
  }

  // Drop shadow for the quill
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
  shadow.shadowOffset = NSSize(width: 0, height: -4 * s)
  shadow.shadowBlurRadius = 16 * s

  // ------- Quill body -------
  NSGraphicsContext.current?.saveGraphicsState()
  shadow.set()

  let quillPath = NSBezierPath()
  quillPath.move(to: pt(256, 768))
  quillPath.curve(to: pt(544, 352), controlPoint1: pt(352, 512), controlPoint2: pt(544, 352))
  quillPath.curve(to: pt(800, 192), controlPoint1: pt(704, 224), controlPoint2: pt(800, 192))
  quillPath.curve(to: pt(736, 480), controlPoint1: pt(832, 320), controlPoint2: pt(736, 480))
  quillPath.curve(to: pt(352, 800), controlPoint1: pt(608, 672), controlPoint2: pt(352, 800))
  quillPath.close()

  let quillFill = NSGradient(colors: [
    NSColor.white,
    NSColor(calibratedWhite: 0.85, alpha: 1.0),
  ])!
  quillFill.draw(in: quillPath, angle: 315)

  NSColor(calibratedWhite: 0.74, alpha: 1.0).setStroke()
  quillPath.lineWidth = 6 * s
  quillPath.stroke()
  NSGraphicsContext.current?.restoreGraphicsState()

  // ------- Quill spine -------
  let spine = NSBezierPath()
  spine.move(to: pt(288, 768))
  spine.line(to: pt(768, 256))
  spine.lineWidth = 9 * s
  spine.lineCapStyle = .round
  NSColor(calibratedWhite: 0.42, alpha: 1.0).setStroke()
  spine.stroke()

  // ------- Feather barb lines -------
  NSGraphicsContext.current?.saveGraphicsState()
  NSColor(calibratedWhite: 0.62, alpha: 0.55).setStroke()
  let barbs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (360, 720, 420, 690),
    (400, 670, 460, 640),
    (450, 610, 510, 580),
    (500, 550, 560, 520),
    (550, 490, 610, 460),
    (600, 430, 660, 400),
    (650, 370, 710, 340),
    (700, 310, 740, 285),
  ]
  for (x1, y1, x2, y2) in barbs {
    let p = NSBezierPath()
    p.move(to: pt(x1, y1))
    p.line(to: pt(x2, y2))
    p.lineWidth = 3 * s
    p.lineCapStyle = .round
    p.stroke()
  }
  NSGraphicsContext.current?.restoreGraphicsState()

  // ------- Nib (dark triangle at tip) -------
  let nib = NSBezierPath()
  nib.move(to: pt(256, 768))
  nib.line(to: pt(224, 832))
  nib.line(to: pt(320, 800))
  nib.close()
  NSColor(calibratedRed: 0.173, green: 0.243, blue: 0.314, alpha: 1.0).setFill() // #2c3e50
  nib.fill()

  // Nib highlight
  let nibHl = NSBezierPath()
  nibHl.move(to: pt(256, 768))
  nibHl.line(to: pt(244, 800))
  nibHl.line(to: pt(280, 790))
  nibHl.close()
  NSColor(calibratedRed: 0.204, green: 0.286, blue: 0.369, alpha: 1.0).setFill() // #34495e
  nibHl.fill()

  // ------- AI sparkles (gold 4-point stars + dots) -------
  let gold = NSColor(calibratedRed: 1.0, green: 0.850, blue: 0.239, alpha: 1.0) // #ffd93d
  gold.setFill()

  // 4-point star helper (authored at SVG point `(cx, cy)` with horizontal/vertical extent `h` and waist `w`)
  func starPath(cx: CGFloat, cy: CGFloat, h: CGFloat, w: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: pt(cx, cy - h))
    p.line(to: pt(cx + w, cy - w))
    p.line(to: pt(cx + h, cy))
    p.line(to: pt(cx + w, cy + w))
    p.line(to: pt(cx, cy + h))
    p.line(to: pt(cx - w, cy + w))
    p.line(to: pt(cx - h, cy))
    p.line(to: pt(cx - w, cy - w))
    p.close()
    return p
  }

  // Big star top-right of quill
  starPath(cx: 832, cy: 360, h: 40, w: 8).fill()
  // Medium star mid-right
  starPath(cx: 896, cy: 538, h: 26, w: 6).fill()
  // Tiny star bottom-left
  starPath(cx: 192, cy: 656, h: 16, w: 4).fill()

  // Circle sparkles
  func circleAt(cx: CGFloat, cy: CGFloat, r: CGFloat) -> NSBezierPath {
    let origin = pt(cx - r, cy + r)
    return NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y, width: r * 2 * s, height: r * 2 * s))
  }

  circleAt(cx: 640, cy: 192, r: 14).fill()
  circleAt(cx: 352, cy: 832, r: 8).fill()

  // Inner white highlights on sparkles
  NSColor.white.setFill()
  circleAt(cx: 832, cy: 360, r: 4).fill()
  circleAt(cx: 896, cy: 538, r: 2.5).fill()
  circleAt(cx: 640, cy: 192, r: 4).fill()
  circleAt(cx: 352, cy: 832, r: 2.5).fill()

  NSGraphicsContext.current?.restoreGraphicsState()
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
