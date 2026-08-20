import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Lecture de la luminance d'une image — support de S26
//
// La gravure a besoin de deux mesures sur le fond, et d'aucune autre :
//
//   moyenne   sous le tracé, pour choisir la couleur du halo. Un halo sombre sur fond
//             sombre ne détache rien, et l'encre devient illisible là où elle compte.
//   variance  sous un badge candidat, pour le poser sur la zone la plus unie. Un chiffre
//             posé sur du texte se lit mal ; posé sur un aplat, il se lit toujours.
//
// L'image est dépixelisée UNE FOIS et gardée en mémoire pour toutes les mesures d'une
// même gravure : chaque marque interroge huit positions candidates, et redessiner
// l'image à chaque interrogation coûterait plus cher que la gravure entière.
// ─────────────────────────────────────────────────────────────────────────────

struct LuminanceMap {
    let width: Int
    let height: Int
    /// L* pour chaque pixel, dans l'ordre de balayage, origine en HAUT à gauche —
    /// celle de `CGImage`.
    private let values: [Float]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buffer, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var out = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Self.linear(buffer[i * 4])
            let g = Self.linear(buffer[i * 4 + 1])
            let b = Self.linear(buffer[i * 4 + 2])
            out[i] = Self.lStar(0.2126 * r + 0.7152 * g + 0.0722 * b)
        }
        width = w
        height = h
        values = out
    }

    /// sRGB → linéaire. L'étape qu'on saute par étourderie, et qui fausse tout jugement
    /// de contraste : moyenner des valeurs gamma-encodées surestime les fonds sombres.
    private static func linear(_ c: UInt8) -> Float {
        let v = Float(c) / 255
        return v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
    }

    /// Luminance relative → L*, l'échelle perceptuelle. C'est elle que le seuil de 55
    /// de la spécification désigne, pas la luminance brute.
    private static func lStar(_ y: Float) -> Float {
        let t = y > 0.008856 ? powf(y, 1.0 / 3) : 7.787 * y + 16.0 / 116
        return 116 * t - 16
    }

    /// Échantillonne un rectangle. Les coordonnées sont en pixels, origine en haut à
    /// gauche. Retourne `nil` si le rectangle ne recouvre aucun pixel de l'image.
    ///
    /// Le pas d'échantillonnage borne le coût : une zone de 900×600 ferait 540 000
    /// lectures par position candidate, soit plus de quatre millions par marque.
    func stats(in rect: CGRect, maxSamples: Int = 2048) -> (mean: Float, variance: Float)? {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }

        let x0 = Int(clipped.minX), y0 = Int(clipped.minY)
        let x1 = min(width, Int(clipped.maxX.rounded(.up)))
        let y1 = min(height, Int(clipped.maxY.rounded(.up)))
        let total = max(1, (x1 - x0) * (y1 - y0))
        let step = max(1, Int((Double(total) / Double(maxSamples)).squareRoot().rounded(.up)))

        var sum: Double = 0, sumSquares: Double = 0, count = 0
        for y in stride(from: y0, to: y1, by: step) {
            for x in stride(from: x0, to: x1, by: step) {
                let v = Double(values[y * width + x])
                sum += v
                sumSquares += v * v
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        return (Float(mean), Float(max(0, sumSquares / Double(count) - mean * mean)))
    }
}
