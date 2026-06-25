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
    let text = getLangCode(for: source)
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


}
