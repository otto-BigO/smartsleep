// Genererer docs/banner.png til README'en. Koer fra repo-roden:
//   swiftc -o /tmp/make_banner Tools/make_banner.swift && /tmp/make_banner
import AppKit

let width: CGFloat = 1280
let height: CGFloat = 360
let scale: CGFloat = 2

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
let cg = context.cgContext
cg.clear(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
cg.scaleBy(x: scale, y: scale)

// Moerk nattehimmel, saa ikonets blaa flise staar tydeligt frem.
let background = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                        cornerWidth: 28, cornerHeight: 28, transform: nil)
cg.saveGState()
cg.addPath(background)
cg.clip()
let colors = [NSColor(srgbRed: 0.09, green: 0.11, blue: 0.26, alpha: 1).cgColor,
              NSColor(srgbRed: 0.03, green: 0.04, blue: 0.09, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0),
                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
cg.restoreGState()

let title = NSAttributedString(string: "SmartSleep", attributes: [
    .font: NSFont.systemFont(ofSize: 88, weight: .bold),
    .foregroundColor: NSColor.white,
])
let tagline = NSAttributedString(string: "Keeps your Mac awake while music plays.\nClose the lid and keep listening.", attributes: [
    .font: NSFont.systemFont(ofSize: 28, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.72),
    .paragraphStyle: {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        return style
    }(),
])

let iconSize: CGFloat = 230
let gap: CGFloat = 36
let titleSize = title.size()
let taglineSize = tagline.boundingRect(with: NSSize(width: 900, height: 400), options: [.usesLineFragmentOrigin]).size
let textWidth = max(titleSize.width, taglineSize.width)
let textHeight = titleSize.height + 10 + taglineSize.height
let startX = (width - (iconSize + gap + textWidth)) / 2

// Ikonet har selv luft og skygge i kanten, derfor lidt stoerre end teksten.
let icon = NSImage(contentsOfFile: "Resources/AppIcon.icns")!
icon.draw(in: NSRect(x: startX, y: (height - iconSize) / 2, width: iconSize, height: iconSize))

let textX = startX + iconSize + gap
let textBottom = (height - textHeight) / 2
tagline.draw(with: NSRect(x: textX, y: textBottom, width: 900, height: taglineSize.height), options: [.usesLineFragmentOrigin])
title.draw(at: NSPoint(x: textX - 4, y: textBottom + taglineSize.height + 10))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/banner.png"))
print("docs/banner.png skrevet")
