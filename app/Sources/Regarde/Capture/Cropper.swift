import CoreGraphics
import CoreImage
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Recadrage autour d'une marque — S25, spécification § 9.2
//
// Le recadrage est le levier de coût numéro un du produit : 513 jetons contre 4 784 pour
// une capture pleine. Sa géométrie n'est donc pas une préférence esthétique, elle est
// dictée par la façon dont un modèle facture une image — par tuiles de 28 pixels.
//
// Trois règles, chacune payée par un défaut qu'elle évite :
//
//   dilatation ×2,5   une bbox serrée sur le tracé montre le défaut sans son contexte.
//                     « Ce bouton est mal aligné » n'a de sens qu'avec ce à quoi il est
//                     censé s'aligner dans le cadre.
//   alignement 28     les dimensions sont arrondies à des multiples de 28 parce que
//                     c'est la taille de tuile ; 757 pixels de large coûtent autant que
//                     784 et rendent moins.
//   Lanczos           jamais d'interpolation linéaire. La réduction est l'endroit exact
//                     où le détail annoté se perd, et c'est le seul détail qui compte.
//
// Au-delà de 40 % de la surface de l'écran, le recadrage ne fait plus économiser assez
// pour justifier la perte de contexte : on bascule sur l'image entière.
// ─────────────────────────────────────────────────────────────────────────────

enum Cropper {

    /// Taille de tuile de facturation. Toute dimension y est alignée.
    static let tile = 28

    /// Facteur de dilatation de la boîte englobante.
    static let dilation: CGFloat = 2.5

    /// Bornes du côté long, en pixels natifs.
    static let longSideRange: ClosedRange<CGFloat> = 640...896

    /// Au-delà, l'image entière coûte moins cher en contexte perdu qu'en jetons gagnés.
    static let fullThreshold: CGFloat = 0.40

    enum Kind: String, Sendable {
        case crop, full
    }

    struct Result: Sendable {
        let image: CGImage
        let kind: Kind
        /// Rectangle prélevé dans l'image source, en pixels. Utile au rapport : il permet
        /// de resituer un recadrage dans la capture entière sans la recharger.
        let sourceRect: CGRect
    }

    /// Recadre autour d'une boîte normalisée.
    ///
    /// `norm` est exprimée dans le repère de l'écran, origine en BAS à gauche comme
    /// partout dans le modèle (§ 3.4) ; `CGImage` a la sienne en HAUT à gauche. Le
    /// retournement se fait ici, une fois, plutôt que dans chaque appelant — c'est
    /// exactement le genre d'inversion qui produit un recadrage juste en haut de l'écran
    /// et faux en bas, donc juste la moitié du temps.
    static func crop(_ image: CGImage, around norm: NormRect) -> Result {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let full = CGRect(x: 0, y: 0, width: w, height: h)

        let box = CGRect(x: CGFloat(norm.x) * w,
                         y: (1 - CGFloat(norm.y) - CGFloat(norm.h)) * h,
                         width: CGFloat(norm.w) * w,
                         height: CGFloat(norm.h) * h)

        let dilated = dilate(box, in: full)

        // Le seuil des 40 % porte sur la boîte DILATÉE, avant que le côté long ne soit
        // borné — et l'ordre n'est pas un détail.
        //
        // Testé dans l'autre sens, la bascule sur `full` devient inatteignable : le
        // bornage ramène tout recadrage à 896 px de côté long au plus, soit 0,8 Mpx,
        // qui n'atteint jamais 40 % d'une capture de 7,7 Mpx. La règle existait sans
        // jamais s'appliquer. Posée sur la boîte dilatée, elle dit ce qu'elle doit
        // dire : quand ce qu'on désigne occupe déjà une grande part de l'écran,
        // recadrer ne retire aucun bruit et fait juste perdre le reste du contexte.
        guard dilated.width * dilated.height < full.width * full.height * fullThreshold
        else { return Result(image: image, kind: .full, sourceRect: full) }

        // Le prélèvement contient TOUJOURS la boîte dilatée. Il n'est agrandi que par
        // le bas — pour montrer du contexte quand la marque est minuscule — et jamais
        // rogné par le haut.
        //
        // Rogner un prélèvement trop grand pour tenir dans 896 px l'a coupé au milieu de
        // la marque : un surlignage de 1037 px natifs se retrouvait dans un recadrage de
        // 896 px, dont il débordait des deux côtés. La borne haute ne concerne pas la
        // ZONE prélevée mais l'image FINALE, et c'est la réduction qui l'y amène.
        let rect = align(growToMinimum(dilated, in: full), in: full)
        guard let cropped = image.cropping(to: rect) else {
            return Result(image: image, kind: .full, sourceRect: full)
        }
        return Result(image: cropped, kind: .crop, sourceRect: rect)
    }

    // MARK: - Étapes

    /// Dilate autour du centre, sans sortir de l'image.
    static func dilate(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let cx = box.midX, cy = box.midY
        let w = max(box.width * dilation, 1), h = max(box.height * dilation, 1)
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            .intersection(bounds)
    }

    /// Agrandit un prélèvement trop petit pour être exploitable.
    ///
    /// Uniquement vers le haut : un recadrage de 80 px ne montre rien de son
    /// environnement, alors qu'un recadrage trop grand se corrige sans perte par la
    /// réduction. Le recentrage est REPOUSSÉ dans l'image quand il déborde, plutôt que
    /// rogné : rogner décentrerait la marque, qui est le sujet.
    static func growToMinimum(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let long = max(box.width, box.height)
        guard long > 0, long < longSideRange.lowerBound else { return box }

        let factor = longSideRange.lowerBound / long
        let w = min(box.width * factor, bounds.width)
        let h = min(box.height * factor, bounds.height)

        var rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        rect.origin.x = min(max(rect.origin.x, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), bounds.maxY - rect.height)
        return rect
    }

    /// Aligne les dimensions sur des multiples de la tuile de facturation.
    ///
    /// On arrondit vers le HAUT quand la place existe : une tuile entamée est facturée
    /// entière, autant qu'elle porte des pixels utiles plutôt que du vide.
    static func align(_ box: CGRect, in bounds: CGRect) -> CGRect {
        let t = CGFloat(tile)
        var w = (box.width / t).rounded(.up) * t
        var h = (box.height / t).rounded(.up) * t
        if w > bounds.width { w = (bounds.width / t).rounded(.down) * t }
        if h > bounds.height { h = (bounds.height / t).rounded(.down) * t }
        w = max(w, t); h = max(h, t)

        var rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
        rect.origin.x = (min(max(rect.origin.x, bounds.minX), bounds.maxX - w)).rounded()
        rect.origin.y = (min(max(rect.origin.y, bounds.minY), bounds.maxY - h)).rounded()
        return rect
    }

    // MARK: - Réduction

    /// Contexte partagé. Le recréer par appel coûte des dizaines de millisecondes de
    /// compilation de noyaux, à chaque marque.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Réduit une image par transformation de Lanczos.
    ///
    /// `CILanczosScaleTransform` et jamais un simple redessin dans un contexte plus
    /// petit : ce dernier interpole linéairement, et l'interpolation linéaire est
    /// précisément ce qui efface un liseré d'un pixel — soit le défaut d'alignement que
    /// la marque désignait.
    static func scale(_ image: CGImage, toLongSide target: CGFloat) -> CGImage {
        let long = CGFloat(max(image.width, image.height))
        guard long > target, target > 0 else { return image }

        let factor = target / long
        let filter = CIFilter(name: "CILanczosScaleTransform")
        filter?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter?.setValue(factor, forKey: kCIInputScaleKey)
        filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let output = filter?.outputImage,
              let result = ciContext.createCGImage(output, from: output.extent)
        else { return image }
        return result
    }

    /// Amène une image recadrée à sa forme finale : côté long dans la plage utile, et
    /// dimensions alignées sur la tuile de facturation.
    ///
    /// L'alignement se fait ICI, sur l'image écrite, et non sur la zone prélevée. Aligner
    /// le prélèvement puis le réduire donne des dimensions quelconques — un recadrage de
    /// 1120 px réduit d'un facteur 0,8 fait 896, mais un autre de 1148 en fait 918,4.
    /// Ce sont les dimensions finales que le modèle facture par tuiles.
    static func fitToTiles(_ image: CGImage) -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let long = max(w, h)
        guard long > longSideRange.upperBound else { return alignDown(image) }

        // Jamais d'agrandissement : Lanczos rendrait un flou propre, mais un flou quand
        // même, et le détail annoté est ce qui compte.
        let reduced = scale(image, toLongSide: longSideRange.upperBound)
        return alignDown(reduced)
    }

    /// Rogne au multiple de tuile inférieur, en gardant le centre.
    private static func alignDown(_ image: CGImage) -> CGImage {
        let t = CGFloat(tile)
        let w = (CGFloat(image.width) / t).rounded(.down) * t
        let h = (CGFloat(image.height) / t).rounded(.down) * t
        guard w >= t, h >= t,
              w != CGFloat(image.width) || h != CGFloat(image.height) else { return image }
        let rect = CGRect(x: ((CGFloat(image.width) - w) / 2).rounded(),
                          y: ((CGFloat(image.height) - h) / 2).rounded(),
                          width: w, height: h)
        return image.cropping(to: rect) ?? image
    }

    /// Dimensions cibles d'un palier de facturation — § 9.2.
    ///
    /// `hp = floor(sqrt(B/r))`, `wp = min(92, floor(hp·r))`, cible `28·wp × 28·hp`.
    /// Le plafond de 92 tuiles existe parce qu'au-delà le modèle redimensionne lui-même :
    /// envoyer plus large ne fait que payer un transfert pour un détail qui sera jeté.
    static func tileTarget(width: Int, height: Int, budget: Double) -> CGSize {
        guard width > 0, height > 0 else { return .zero }
        let r = Double(width) / Double(height)
        let hp = max(1, Int((budget / r).squareRoot().rounded(.down)))
        let wp = max(1, min(92, Int((Double(hp) * r).rounded(.down))))
        return CGSize(width: wp * tile, height: hp * tile)
    }
}
