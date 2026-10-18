import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.118, green: 0.435, blue: 0.361, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.translateBy(x: 512, y: 512)
context.rotate(by: .pi / 5)
context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1))
for rect in [CGRect(x: -310, y: -24, width: 620, height: 48), CGRect(x: -270, y: -160, width: 70, height: 320), CGRect(x: -186, y: -220, width: 90, height: 440), CGRect(x: 96, y: -220, width: 90, height: 440), CGRect(x: 200, y: -160, width: 70, height: 320)] {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)); context.fillPath()
}
let image = NSBitmapImageRep(cgImage: context.makeImage()!)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try image.representation(using: .png, properties: [:])!.write(to: output)
