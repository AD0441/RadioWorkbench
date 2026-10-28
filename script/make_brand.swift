import AppKit
import Foundation

// Packaging derivatives of the approved monochrome source. The source image is never modified.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("Sources/RadioWorkbench/Resources/Brand")
let docs = root.appendingPathComponent("docs/assets/brand")
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
guard let source = NSImage(contentsOf: brand.appendingPathComponent("RazielIcon.png")) else { FileHandle.standardError.write(Data("Missing approved RAZIEL icon\n".utf8)); exit(1) }
func render(_ size: NSSize, to url: URL, draw: () -> Void) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    draw(); context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url, options: .atomic)
}
func text(_ value: String, at point: NSPoint, size: CGFloat, display: Bool = false, color: NSColor = .white) {
    let font = display ? (NSFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)) : .systemFont(ofSize: size)
    (value as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("raziel-icon-\(UUID())", isDirectory: true)
let iconset = temporary.appendingPathComponent("RAZIEL.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try render(NSSize(width: pixels, height: pixels), to: iconset.appendingPathComponent(filename)) {
            source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert","icns",iconset.path,"--output",brand.appendingPathComponent("RAZIEL.icns").path]
try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { FileHandle.standardError.write(Data("iconutil failed; icon source retained\n".utf8)); exit(1) }
try render(NSSize(width: 512, height: 512), to: docs.appendingPathComponent("app-icon.png")) { source.draw(in: NSRect(x: 0,y: 0,width: 512,height: 512)) }
try render(NSSize(width: 1200, height: 630), to: docs.appendingPathComponent("cover.png")) {
    NSColor(calibratedWhite: 0.025, alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 1200,height: 630).fill()
    source.draw(in: NSRect(x: 55,y: 95,width: 410,height: 410))
    text("RAZIEL", at: NSPoint(x: 510,y: 345), size: 82, display: true)
    text("Escucha. Decodifica. Explora.", at: NSPoint(x: 515,y: 290), size: 28)
    text("Listen. Decode. Explore.", at: NSPoint(x: 515,y: 253), size: 25, color: NSColor(calibratedWhite: 0.72,alpha: 1))
    NSColor(calibratedWhite: 0.3,alpha: 1).setStroke(); let line = NSBezierPath();line.move(to: NSPoint(x: 515,y: 224));line.line(to: NSPoint(x: 1110,y: 224));line.lineWidth = 1;line.stroke()
    text("macOS · Apple Silicon · Español / English", at: NSPoint(x: 515,y: 178), size: 20, color: NSColor(calibratedWhite: 0.82,alpha: 1))
    text("Creado por Sebastián Pastén F.", at: NSPoint(x: 515,y: 114), size: 18, color: NSColor(calibratedWhite: 0.7,alpha: 1))
}
let drawings = [
    "signal": #"<path d="M16 46V18m-6 22a18 18 0 0 1 0-22m12 22a18 18 0 0 0 0-22M8 54h16m20-14 4-16 5 28 4-14h6"/>"#,
    "images": #"<rect x="8" y="10" width="48" height="44" rx="3"/><path d="m9 43 13-14 9 10 9-15 15 22"/><circle cx="22" cy="21" r="3"/>"#,
    "terrain": #"<path d="M6 51 18 37 26 43 37 19 48 37 58 30M8 51V15m-3 0h6m44 15V11m-3 0h6M8 15l47-4"/>"#
]
for (name, shapes) in drawings {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\"><rect width=\"64\" height=\"64\" rx=\"12\" fill=\"#111\"/><g fill=\"none\" stroke=\"#fff\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(shapes)</g></svg>\n"
    try svg.write(to: docs.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
print("RAZIEL: ICNS, documentation icon, cover and three geometric feature symbols generated.")
