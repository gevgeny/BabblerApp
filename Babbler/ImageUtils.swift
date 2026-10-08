import Cocoa
import Carbon

@objc class ImageUtils: NSObject {

  static var languageImages: [String: String] = [
    "com.apple.keylayout.US":                 "🇺🇸",
    "com.apple.keylayout.USInternational-PC": "🇺🇸",
    "com.apple.keylayout.British-PC":         "🇬🇧",
    "com.apple.keylayout.British":            "🇬🇧",
    "com.apple.keylayout.ABC":                "🇬🇧",
    "com.apple.keylayout.Russian":            "🇷🇺",
    "com.apple.keylayout.RussianWin":         "🇷🇺",
  ]
  
  static func getLangCode(for source: TISInputSource) -> String {
    return (source.sourceLanguages.first ?? String(source.name.prefix(2))).uppercased()
  }

  static func makeInputSourceIcon(for source: TISInputSource) -> NSImage? {
    makeLangCodeIcon(getLangCode(for: source))
  }

  static func makeLangCodeIcon(_ text: String) -> NSImage {
    let imageSize = NSSize(width: 22, height: 17)

    let image = NSImage(size: imageSize, flipped: false) { drawRect in
      let cornerRadius: CGFloat = 4

      // Fill the rounded rect solid — this becomes the white/black body of the icon
      let path = NSBezierPath(roundedRect: drawRect, xRadius: cornerRadius, yRadius: cornerRadius)
      NSColor.black.setFill()
      path.fill()

      // Punch the text out of the fill with destinationOut so it becomes transparent.
      // Because isTemplate = true, the opaque fill renders as white in the menu bar
      // and the transparent text reveals the background colour behind it.
      let fontSize: CGFloat = text.count > 1 ? 10.5 : 12
      let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
      ]
      let textSize = (text as NSString).size(withAttributes: attrs)
      let textPoint = CGPoint(
        x: (drawRect.width - textSize.width) / 2,
        y: (drawRect.height - textSize.height) / 2 - 0.5
      )
      NSGraphicsContext.current?.compositingOperation = .destinationOut
      (text as NSString).draw(at: textPoint, withAttributes: attrs)
      NSGraphicsContext.current?.compositingOperation = .sourceOver

      return true
    }

    image.isTemplate = true
    return image
  }

  static func makeTextIcon(_ text: String) -> NSImage {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.menuBarFont(ofSize: 0),
      // Dynamic colour resolves against the menu bar appearance at draw time
      .foregroundColor: NSColor.labelColor,
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    return NSImage(size: size, flipped: false) { _ in
      (text as NSString).draw(at: .zero, withAttributes: attrs)
      return true
    }
  }

  static let disabledIconAlpha: CGFloat = 0.4

  static func dimmed(_ base: NSImage) -> NSImage {
    let image = NSImage(size: base.size, flipped: false) { rect in
      base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: disabledIconAlpha)
      return true
    }
    image.isTemplate = base.isTemplate
    return image
  }

  // Secure input also blocks text replacement, so the base is always dimmed here
  static func addSecureInputDot(to base: NSImage) -> NSImage {
    let dotSize: CGFloat = 6
    let overhang: CGFloat = 2  // dot shift right past the base; padded left and right to keep it centred
    let rise: CGFloat = 2      // dot shift above the base; padded top and bottom to keep it centred
    let size = NSSize(width: base.size.width + overhang * 2, height: base.size.height + rise * 2)
    return NSImage(size: size, flipped: false) { _ in
      let baseRect = NSRect(origin: NSPoint(x: overhang, y: rise), size: base.size)
      base.draw(in: baseRect, from: .zero, operation: .sourceOver, fraction: disabledIconAlpha)
      if base.isTemplate {
        // Result isn't a template (the dot must stay red), so tint the base by hand
        NSColor.labelColor.set()
        baseRect.fill(using: .sourceAtop)
      }
      NSColor.systemRed.setFill()
      NSBezierPath(ovalIn: NSRect(x: baseRect.maxX - dotSize + overhang, y: size.height - dotSize, width: dotSize, height: dotSize)).fill()
      return true
    }
  }
}
