import CoreGraphics
import Foundation
import ImageIO

// Mesure l'épaisseur d'un trait vermillon : pour chaque ligne de balayage, on relève les
// suites contiguës de pixels « encrés », et on prend la MÉDIANE de leurs largeurs.
//
// Deux seuils, parce que les deux questions sont différentes :
//   encre  → le vermillon seul, ce que l'utilisateur appelle « le trait »
//   marque → l'encre plus tout pixel nettement plus sombre que son voisinage clair,
//            c'est-à-dire le trait halo compris, soit l'épaisseur PERÇUE

let args = CommandLine.arguments
guard args.count > 1,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write(Data("usage: thickness <image.png> [x0 y0 x1 y1]\n".utf8))
    exit(2)
}
let w = image.width, h = image.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(3) }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
}
func isInk(_ p: (Int, Int, Int)) -> Bool {
    p.0 > 170 && p.1 < 130 && p.2 < 130 && p.0 - max(p.1, p.2) > 70
}
func isMark(_ p: (Int, Int, Int)) -> Bool {
    if isInk(p) { return true }
    // Halo sombre : nettement plus foncé qu'un fond clair.
    return p.0 < 150 && p.1 < 150 && p.2 < 150
}

var x0 = 0, y0 = 0, x1 = w, y1 = h
if args.count >= 6 {
    x0 = Int(args[2]) ?? 0; y0 = Int(args[3]) ?? 0
    x1 = Int(args[4]) ?? w; y1 = Int(args[5]) ?? h
}

func runs(_ test: ((Int, Int, Int)) -> Bool) -> [Int] {
    var out: [Int] = []
    for y in max(0, y0)..<min(h, y1) {
        var run = 0
        for x in max(0, x0)..<min(w, x1) {
            if test(px(x, y)) { run += 1 }
            else { if run > 0 && run < 40 { out.append(run) }; run = 0 }
        }
        if run > 0 && run < 40 { out.append(run) }
    }
    return out.sorted()
}

func report(_ label: String, _ values: [Int]) {
    guard !values.isEmpty else { print("  \(label) : aucun segment"); return }
    let med = values[values.count / 2]
    let mean = Double(values.reduce(0, +)) / Double(values.count)
    print(String(format: "  %-22s médiane %d px   moyenne %.2f   (%d segments)",
                 (label as NSString).utf8String!, med, mean, values.count))
}

print("\(URL(fileURLWithPath: args[1]).lastPathComponent)  \(w)×\(h)")
report("encre seule", runs(isInk))
report("encre + halo", runs(isMark))
