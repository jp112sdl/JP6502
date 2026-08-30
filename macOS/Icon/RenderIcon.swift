import AppKit
import ImageIO
import CoreGraphics
import CoreText
import Foundation

// A 40 pin DIP of the shape the MOS 6502 came in: white ceramic body, gold
// pins, the notch that says which end pin 1 is at. Everything is in fractions
// of the canvas, so the same drawing is used at every size rather than one
// large rendering being shrunk into mush.

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

/// The rounded square macOS icons are, which is a superellipse rather than a
/// rectangle with circular corners.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    let a = rect.width / 2, b = rect.height / 2
    let centreX = rect.midX, centreY = rect.midY
    let n: CGFloat = 5          // 4 is a rounded square, higher is squarer
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle), sine = sin(angle)
        let x = centreX + a * pow(abs(cosine), 2 / n) * (cosine < 0 ? -1 : 1)
        let y = centreY + b * pow(abs(sine), 2 / n) * (sine < 0 ? -1 : 1)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func gradient(_ colours: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colours as CFArray, locations: stops)!
}

func draw(size: CGFloat) -> CGImage {
    let scale = size
    let context = CGContext(data: nil, width: Int(size), height: Int(size),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
    }

    // The canvas an icon is allowed to fill: macOS leaves a margin around the
    // rounded square so that icons of different shapes look the same size.
    let plate = box(0.055, 0.055, 0.89, 0.89)
    let shape = squircle(in: plate)

    // Board underneath, dark enough for a white chip to sit on it.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        gradient([rgb(52, 74, 92), rgb(22, 33, 44), rgb(14, 21, 28)], [0, 0.55, 1]),
        start: point(0, 0.945), end: point(0, 0.055), options: [])

    // A faint grid, the way a board looks under the light. At the sizes where
    // one square is a pixel or two it is only noise, so it is left off there.
    if size >= 128 {
        context.setStrokeColor(rgb(255, 255, 255, 0.035))
        context.setLineWidth(max(1, 0.004 * scale))
        var line: CGFloat = 0.055
        while line < 0.945 {
            context.move(to: point(line, 0.055)); context.addLine(to: point(line, 0.945))
            context.move(to: point(0.055, line)); context.addLine(to: point(0.945, line))
            line += 0.0625
        }
        context.strokePath()
    }
    context.restoreGState()

    // MARK: pins

    let bodyRect = box(0.295, 0.150, 0.410, 0.700)
    // Forty pins is what the part has and what nothing below a poster can
    // show. The count drops with the size so that they stay pins rather than
    // turning into a grey fringe.
    let pinCount = size >= 128 ? 10 : (size >= 64 ? 8 : 5)
    let pinHeight: CGFloat = size >= 128 ? 0.0405 : (size >= 64 ? 0.052 : 0.078)
    let pinReach: CGFloat = size >= 64 ? 0.093 : 0.105
    let pinSpan: CGFloat = 0.640
    let pinPitch = (pinSpan - pinHeight) / CGFloat(pinCount - 1)
    let firstPin = 0.5 - pinSpan / 2

    for index in 0..<pinCount {
        let y = firstPin + CGFloat(index) * pinPitch
        for left in [true, false] {
            let x = left ? 0.295 - pinReach : 0.705
            let pin = box(x, y, pinReach, pinHeight)
            let rounded = CGPath(roundedRect: pin,
                                 cornerWidth: pin.height * 0.28,
                                 cornerHeight: pin.height * 0.28, transform: nil)
            context.saveGState()
            context.addPath(rounded)
            context.clip()
            context.drawLinearGradient(
                gradient([rgb(140, 96, 26), rgb(240, 206, 122), rgb(176, 128, 42)], [0, 0.42, 1]),
                start: point(0, y), end: point(0, y + pinHeight), options: [])
            context.restoreGState()
        }
    }

    // MARK: body

    let bodyPath = CGPath(roundedRect: bodyRect,
                          cornerWidth: 0.014 * scale, cornerHeight: 0.014 * scale,
                          transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -0.012 * scale),
                      blur: 0.030 * scale, color: rgb(0, 0, 0, 0.55))
    context.addPath(bodyPath)
    context.setFillColor(rgb(233, 228, 216))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.drawLinearGradient(
        gradient([rgb(245, 242, 234), rgb(223, 217, 203), rgb(199, 192, 176)], [0, 0.6, 1]),
        start: point(0, 0.850), end: point(0, 0.150), options: [])

    // The lid, which on a ceramic 6502 is the darker rectangle down the middle.
    let lid = box(0.345, 0.243, 0.310, 0.470)
    context.addPath(CGPath(roundedRect: lid, cornerWidth: 0.010 * scale,
                           cornerHeight: 0.010 * scale, transform: nil))
    context.clip()
    context.drawLinearGradient(
        gradient([rgb(66, 62, 58), rgb(38, 35, 33), rgb(24, 22, 21)], [0, 0.5, 1]),
        start: point(0, 0.713), end: point(0, 0.243), options: [])
    context.restoreGState()

    // The notch at the pin 1 end. Clipped to the body as well as to its own
    // circle, so that it is a bite out of the top edge rather than a bead
    // sitting on top of it.
    let notchRadius: CGFloat = 0.048
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.addEllipse(in: box(0.5 - notchRadius, 0.850 - notchRadius,
                               notchRadius * 2, notchRadius * 2))
    context.clip()
    context.drawLinearGradient(
        gradient([rgb(32, 46, 58), rgb(18, 27, 36)], [0, 1]),
        start: point(0, 0.898), end: point(0, 0.802), options: [])
    context.restoreGState()

    // MARK: lettering

    func write(_ text: String, weight: NSFont.Weight, size fontSize: CGFloat,
               centreY: CGFloat, tracking: CGFloat, colour: CGColor) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize * scale, weight: weight)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: colour)!,
            .kern: tracking * scale,
        ])
        let lineToDraw = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(lineToDraw, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: (0.5 * scale) - (bounds.width + tracking * scale) / 2,
                                       y: centreY * scale - bounds.height / 2)
        CTLineDraw(lineToDraw, context)
    }

    // Lettering only where there are pixels to read it with. Below that the lid
    // stays plain, which is what a chip looks like from across the room anyway.
    if size >= 128 {
        write("MOS", weight: .semibold, size: 0.052, centreY: 0.590,
              tracking: 0.014, colour: rgb(214, 210, 200))
        write("6502", weight: .bold, size: 0.098, centreY: 0.455,
              tracking: 0.012, colour: rgb(240, 237, 229))
    }

    // A rim, so the plate has an edge in a dark dock.
    context.addPath(shape)
    context.setStrokeColor(rgb(255, 255, 255, 0.10))
    context.setLineWidth(max(1, 0.006 * scale))
    context.strokePath()

    return context.makeImage()!
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let image = draw(size: CGFloat(pixels))
    let url = outputDirectory.appendingPathComponent("icon_\(pixels).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(url.lastPathComponent)")
}
