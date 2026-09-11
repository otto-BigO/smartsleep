// Genererer AppIcon.icns. Koer fra repo-roden:
//   swiftc -o /tmp/make_icon Tools/make_icon.swift && /tmp/make_icon /tmp/iconwork
//   iconutil -c icns /tmp/iconwork/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Tegnet paa et 1024-gitter efter macOS' ikonskabelon: 824 x 824 med 100 px luft.
func drawIcon(_ cg: CGContext) {
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    cg.addPath(tile)
    cg.setFillColor(NSColor(srgbRed: 0.07, green: 0.08, blue: 0.22, alpha: 1).cgColor)
    cg.fillPath()
    cg.restoreGState()
    
    cg.saveGState()
    cg.addPath(tile)
    cg.clip()
    let colors = [NSColor(srgbRed: 0.24, green: 0.30, blue: 0.70, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.07, green: 0.08, blue: 0.22, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100),
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()
    
    // Maane: en hvid cirkel med en bid skaaret ud.
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(x: 455 - 265, y: 512 - 265, width: 530, height: 530))
    cg.setBlendMode(.destinationOut)
    cg.fillEllipse(in: CGRect(x: 600 - 235, y: 612 - 235, width: 470, height: 470))
    cg.endTransparencyLayer()
    
    // Tre lydbjaelker i bidden.
    cg.setFillColor(NSColor.white.cgColor)
    let barWidth: CGFloat = 46
    let gap: CGFloat = 28
    for (index, height) in [CGFloat(110), 210, 145].enumerated() {
        let rect = CGRect(x: 575 + CGFloat(index) * (barWidth + gap), y: 575 - height / 2, width: barWidth, height: height)
        cg.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        cg.fillPath()
    }
}

let iconset = "\(CommandLine.arguments[1])/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let data = render(pixels).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("iconset skrevet til \(iconset)")
