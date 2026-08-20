import CoreGraphics
import Foundation
import ImageIO

// Compte les pixels proches du vermillon de l'encre (#FF3B30) dans une image.
//
// Sert à mesurer R12 plutôt qu'à le regarder : « je n'ai rien vu » n'est pas une mesure,
// et une trace d'encre à 0,1 % de la surface passe inaperçue à l'œil tout en polluant
// chaque capture du rapport.

let args = CommandLine.arguments
guard args.count > 1,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write(Data("usage: count-ink <image.png>\n".utf8))
    exit(2)
}

let w = image.width, h = image.height
var buffer = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(3)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// Tolérance large : le vermillon traverse une conversion d'espace colorimétrique à la
// capture, donc exiger la valeur exacte laisserait passer l'encre qu'on cherche.
var hits = 0
for i in stride(from: 0, to: buffer.count, by: 4) {
    let r = Int(buffer[i]), g = Int(buffer[i + 1]), b = Int(buffer[i + 2])
    if r > 200, g < 110, b < 110, r - max(g, b) > 90 { hits += 1 }
}
let ratio = Double(hits) / Double(w * h) * 100
print(String(format: "%d pixels vermillon sur %d (%.4f %%)", hits, w * h, ratio))
exit(hits > 0 ? 1 : 0)
