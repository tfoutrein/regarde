import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Autotest du recadrage et de la gravure — S24 à S26, lancé par `--capture-test`
//
// Rien ici ne touche l'écran ni ne demande de permission : ce sont des rectangles et des
// conversions de repère. C'est précisément ce qu'il faut couvrir, parce qu'une inversion
// d'axe donne un résultat juste dans le haut de l'image et faux dans le bas — donc juste
// une fois sur deux, ce qu'une vérification à l'œil laisse passer.
// ─────────────────────────────────────────────────────────────────────────────

enum CaptureSelfTest {

    private final class Tally {
        var passed = 0
        var failed = 0
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la capture (S24 à S26) ──\n")
        cropping(t)
        tiles(t)
        frames(t)
        engraving(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    private static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)") }
        else { t.failed += 1; print("  ✗ \(label) \(detail)") }
    }

    // MARK: - Recadrage

    private static let capture = CGRect(x: 0, y: 0, width: 3456, height: 2234)

    private static func cropping(_ t: Tally) {
        print("Géométrie du recadrage (S25)")

        // La dilatation garde le centre : un recadrage décentré déplacerait le sujet
        // hors du milieu de l'image, là où l'œil et le modèle le cherchent tous les deux.
        let box = CGRect(x: 1000, y: 800, width: 200, height: 100)
        let dilated = Cropper.dilate(box, in: capture)
        check(t, "la dilatation conserve le centre",
              abs(dilated.midX - box.midX) < 0.01 && abs(dilated.midY - box.midY) < 0.01)
        check(t, "la dilatation vaut bien ×2,5",
              abs(dilated.width - 500) < 0.01 && abs(dilated.height - 250) < 0.01,
              "→ \(dilated.width)×\(dilated.height)")

        // Une boîte au bord ne doit pas produire un rectangle qui sort de l'image :
        // `CGImage.cropping` renverrait nil et la marque n'aurait aucune image.
        let corner = Cropper.dilate(CGRect(x: 0, y: 0, width: 100, height: 60), in: capture)
        check(t, "une boîte au coin reste dans l'image", capture.contains(corner))

        let grown = Cropper.growToMinimum(dilated, in: capture)
        check(t, "un petit prélèvement est porté à 640",
              abs(max(grown.width, grown.height) - 640) < 1,
              "→ \(max(grown.width, grown.height))")
        check(t, "le rapport d'aspect est conservé",
              abs(grown.width / grown.height - dilated.width / dilated.height) < 0.01)

        // Un grand prélèvement n'est PAS rogné. Il l'était, et il coupait la marque en
        // deux : un surlignage de 1037 px natifs se retrouvait dans un recadrage de
        // 896 px dont il débordait des deux côtés. La borne haute concerne l'image
        // finale, et c'est la réduction qui l'y amène.
        let huge = CGRect(x: 100, y: 100, width: 2000, height: 1000)
        check(t, "un grand prélèvement est laissé intact",
              Cropper.growToMinimum(huge, in: capture) == huge)

        let aligned = Cropper.align(grown, in: capture)
        check(t, "la largeur est un multiple de 28", Int(aligned.width) % 28 == 0,
              "→ \(aligned.width)")
        check(t, "la hauteur est un multiple de 28", Int(aligned.height) % 28 == 0,
              "→ \(aligned.height)")
        check(t, "l'origine est entière",
              aligned.minX == aligned.minX.rounded() && aligned.minY == aligned.minY.rounded())
        check(t, "le recadrage aligné reste dans l'image", capture.contains(aligned))

        // Le franchissement du seuil : au-delà de 40 % de la surface, on bascule sur
        // l'image entière plutôt que de payer un recadrage qui n'économise plus rien.
        //
        // L'image de test fait 1920×1200 et non 800×600, parce que la borne basse de
        // 640 px force tout recadrage à cette taille au minimum : sur 800×600, même une
        // marque minuscule dépasse les 40 % et bascule sur `full`. Ce n'est pas un
        // défaut — c'est ce que la plage [640, 896] implique sur un petit écran — mais
        // un test qui l'ignore ne vérifie plus rien du chemin de recadrage.
        let image = solidImage(width: 1920, height: 1200)
        let smallBox = NormRect(bounding: [NormPoint(x: 0.45, y: 0.45),
                                           NormPoint(x: 0.5, y: 0.5)])
        let small = Cropper.crop(image, around: smallBox)
        check(t, "une petite marque produit un recadrage", small.kind == .crop)
        check(t, "le recadrage est plus petit que l'image",
              small.image.width < image.width || small.image.height < image.height)

        // La règle qui manquait : le prélèvement CONTIENT la marque, entière.
        let boxInPixels = CGRect(x: CGFloat(smallBox.x) * CGFloat(image.width),
                                 y: (1 - CGFloat(smallBox.y) - CGFloat(smallBox.h))
                                    * CGFloat(image.height),
                                 width: CGFloat(smallBox.w) * CGFloat(image.width),
                                 height: CGFloat(smallBox.h) * CGFloat(image.height))
        check(t, "le prélèvement contient la marque entière",
              small.sourceRect.insetBy(dx: -1, dy: -1).contains(boxInPixels),
              "→ marque \(boxInPixels) dans \(small.sourceRect)")

        // Une marque LARGE, le cas qui cassait : 0,60 de la largeur d'une capture de
        // 1920 px fait 1152 px, bien au-delà des 896 de la borne haute.
        let wideBox = NormRect(bounding: [NormPoint(x: 0.18, y: 0.48),
                                          NormPoint(x: 0.78, y: 0.53)])
        let wideCrop = Cropper.crop(image, around: wideBox)
        let wideInPixels = CGRect(x: CGFloat(wideBox.x) * CGFloat(image.width),
                                  y: (1 - CGFloat(wideBox.y) - CGFloat(wideBox.h))
                                     * CGFloat(image.height),
                                  width: CGFloat(wideBox.w) * CGFloat(image.width),
                                  height: CGFloat(wideBox.h) * CGFloat(image.height))
        check(t, "une marque plus large que 896 px reste entière dans son prélèvement",
              wideCrop.sourceRect.insetBy(dx: -1, dy: -1).contains(wideInPixels),
              "→ marque \(wideInPixels) dans \(wideCrop.sourceRect)")

        // Le recadrage sort déjà à sa forme finale, réduction comprise.
        check(t, "la forme finale tient sous 896 px de côté long",
              max(wideCrop.image.width, wideCrop.image.height) <= 896,
              "→ \(wideCrop.image.width)×\(wideCrop.image.height)")
        check(t, "la forme finale est alignée sur la tuile",
              wideCrop.image.width % 28 == 0 && wideCrop.image.height % 28 == 0,
              "→ \(wideCrop.image.width)×\(wideCrop.image.height)")

        // ── Le facteur rendu est le facteur RÉEL, sur les deux axes ─────────────
        //
        // Il était déduit après coup d'un rapport de largeurs qui mélangeait la réduction
        // et le rognage d'alignement. Sur un recadrage plus haut que large, le graveur
        // recevait un facteur faux et posait la forme des dizaines de pixels à côté de ce
        // qu'elle désigne, jusqu'à 18 % trop courte.
        for (label, box) in [
            ("large", NormRect(bounding: [NormPoint(x: 0.18, y: 0.48), NormPoint(x: 0.78, y: 0.53)])),
            ("haut et étroit", NormRect(bounding: [NormPoint(x: 0.48, y: 0.12), NormPoint(x: 0.52, y: 0.88)])),
            ("petit", NormRect(bounding: [NormPoint(x: 0.45, y: 0.45), NormPoint(x: 0.48, y: 0.47)])),
        ] {
            let r = Cropper.crop(image, around: box)
            let realX = CGFloat(r.image.width) / r.sourceRect.width
            let realY = CGFloat(r.image.height) / r.sourceRect.height
            check(t, "le facteur annoncé est le facteur réel — cas \(label)",
                  abs(r.scaleX - realX) < 0.0001 && abs(r.scaleY - realY) < 0.0001,
                  "→ annoncés \(r.scaleX)/\(r.scaleY), réels \(realX)/\(realY)")
            check(t, "les deux axes restent proches — cas \(label)",
                  abs(realX - realY) / max(realX, realY) < 0.01,
                  "→ x=\(realX) y=\(realY)")
            check(t, "les dimensions restent alignées sur la tuile — cas \(label)",
                  r.image.width % 28 == 0 && r.image.height % 28 == 0,
                  "→ \(r.image.width)×\(r.image.height)")
        }

        // ── La flèche se recadre sur sa POINTE, pas sur son trait ───────────────
        let tail = NormPoint(x: 0.20, y: 0.20), head = NormPoint(x: 0.70, y: 0.70)
        let arrow = MarkShape.arrow(from: tail, to: head)
        let focus = arrow.focusBox
        check(t, "la zone d'intérêt d'une flèche est centrée sur sa pointe",
              abs(focus.x + focus.w / 2 - head.x) < 0.001
              && abs(focus.y + focus.h / 2 - head.y) < 0.001,
              "→ centre (\(focus.x + focus.w / 2), \(focus.y + focus.h / 2)) vs pointe (\(head.x), \(head.y))")
        check(t, "la zone d'intérêt ne couvre pas tout le trait",
              focus.w < arrow.boundingBox.w * 0.75)
        check(t, "la zone d'intérêt grandit avec la flèche",
              MarkShape.arrow(from: NormPoint(x: 0, y: 0), to: NormPoint(x: 0.8, y: 0)).focusBox.w
              > MarkShape.arrow(from: NormPoint(x: 0, y: 0), to: NormPoint(x: 0.1, y: 0)).focusBox.w)
        check(t, "un cadre reste sa propre zone d'intérêt",
              MarkShape.rect(smallBox).focusBox == smallBox)

        // Le recadrage réel doit mettre la pointe près du centre de l'image.
        let arrowCrop = Cropper.crop(image, around: focus)
        let headPx = CGPoint(x: CGFloat(head.x) * CGFloat(image.width),
                             y: (1 - CGFloat(head.y)) * CGFloat(image.height))
        let offCentre = hypot(headPx.x - arrowCrop.sourceRect.midX,
                              headPx.y - arrowCrop.sourceRect.midY)
        check(t, "la pointe tombe dans le tiers central du recadrage",
              abs(headPx.x - arrowCrop.sourceRect.midX) < arrowCrop.sourceRect.width / 6
              && abs(headPx.y - arrowCrop.sourceRect.midY) < arrowCrop.sourceRect.height / 6,
              "→ écart (\(Int(headPx.x - arrowCrop.sourceRect.midX)), \(Int(headPx.y - arrowCrop.sourceRect.midY))) px sur \(Int(arrowCrop.sourceRect.width))×\(Int(arrowCrop.sourceRect.height))")

        let wide = Cropper.crop(image, around: NormRect(bounding: [
            NormPoint(x: 0.05, y: 0.05), NormPoint(x: 0.95, y: 0.95)]))
        check(t, "une marque qui couvre l'écran bascule sur l'image entière",
              wide.kind == .full)
        check(t, "l'image entière garde ses dimensions",
              wide.image.width == image.width && wide.image.height == image.height)

        // L'ordonnée est INVERSÉE entre le modèle et l'image : une marque en haut de
        // l'écran doit donner un recadrage en haut de l'image, donc à petit y.
        let top = Cropper.crop(image, around: NormRect(bounding: [
            NormPoint(x: 0.45, y: 0.88), NormPoint(x: 0.55, y: 0.95)]))
        let bottom = Cropper.crop(image, around: NormRect(bounding: [
            NormPoint(x: 0.45, y: 0.05), NormPoint(x: 0.55, y: 0.12)]))
        check(t, "une marque en haut d'écran recadre en haut de l'image",
              top.sourceRect.minY < bottom.sourceRect.minY,
              "→ haut y=\(top.sourceRect.minY), bas y=\(bottom.sourceRect.minY)")
    }

    // MARK: - Paliers de facturation

    private static func tiles(_ t: Tally) {
        print("\nPaliers de facturation (§ 9.2)")
        let target = Cropper.tileTarget(width: 3456, height: 2234, budget: 1568)
        check(t, "les dimensions cibles sont des multiples de 28",
              Int(target.width) % 28 == 0 && Int(target.height) % 28 == 0,
              "→ \(target.width)×\(target.height)")
        let tilesUsed = (Int(target.width) / 28) * (Int(target.height) / 28)
        check(t, "le budget de 1568 tuiles n'est pas dépassé", tilesUsed <= 1568,
              "→ \(tilesUsed)")
        check(t, "le rapport d'aspect est approché à 2 % près",
              abs(target.width / target.height - 3456.0 / 2234.0) < 0.04,
              "→ \(target.width / target.height) vs \(3456.0 / 2234.0)")

        // Le plafond de 92 tuiles : au-delà le modèle redimensionne lui-même, et envoyer
        // plus large ne fait que payer un transfert pour un détail qui sera jeté.
        let panoramic = Cropper.tileTarget(width: 8000, height: 1000, budget: 4784)
        check(t, "la largeur est plafonnée à 92 tuiles",
              Int(panoramic.width) / 28 <= 92, "→ \(Int(panoramic.width) / 28)")
    }

    // MARK: - Conversion de repères

    private static func frames(_ t: Tally) {
        print("\nConversion du modèle vers l'image (S26)")

        // Recadrage prélevé au MILIEU de la capture : les deux origines diffèrent, et
        // l'erreur d'inversion ne se voit qu'ici.
        let frame = Engraver.Frame(captureSize: CGSize(width: 1000, height: 800),
                                   sourceRect: CGRect(x: 200, y: 150, width: 400, height: 300),
                                   scale: 1)

        // Le centre de l'écran n'est PAS le centre du prélèvement, et c'est tout
        // l'intérêt du cas. Le rectangle (200,150,400,300) compte depuis le haut : il
        // couvre y de 350 à 650 en repère bas-gauche, de centre 500. Le centre de
        // l'écran est à y = 400, donc 50 au-dessus du bord bas du prélèvement.
        //
        // Ce calcul a d'abord été posé faux dans ce test — l'attente était 150, la
        // moitié de la hauteur — et c'est le code qui avait raison.
        let centre = frame.point(NormPoint(x: 0.5, y: 0.5))
        check(t, "un point de l'écran tombe où le prélèvement le place",
              abs(centre.x - 300) < 0.01 && abs(centre.y - 50) < 0.01,
              "→ \(centre)")

        // Le sens de l'axe : plus haut à l'écran signifie plus haut dans l'image, donc un
        // y de contexte PLUS GRAND — le contexte a son origine en bas.
        let higher = frame.point(NormPoint(x: 0.5, y: 0.6))
        check(t, "monter à l'écran monte dans l'image", higher.y > centre.y)

        let scaled = Engraver.Frame(captureSize: CGSize(width: 1000, height: 800),
                                    sourceRect: CGRect(x: 200, y: 150, width: 400, height: 300),
                                    scale: 0.5)
        let halved = scaled.point(NormPoint(x: 0.5, y: 0.5))
        check(t, "la réduction s'applique aux coordonnées",
              abs(halved.x - 150) < 0.01 && abs(halved.y - 25) < 0.01, "→ \(halved)")
        check(t, "la taille de sortie suit la réduction",
              scaled.outputSize == CGSize(width: 200, height: 150))

        // Le retournement vers le repère de la carte de luminance doit être involutif.
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        check(t, "le retournement appliqué deux fois redonne le rectangle",
              frame.flipped(frame.flipped(rect)) == rect)
    }

    // MARK: - Gravure

    private static func engraving(_ t: Tally) {
        print("\nGravure (S26)")

        check(t, "l'épaisseur ne descend jamais sous 3 px",
              Engraver.inkWidth(longSide: 100) == 3)
        check(t, "l'épaisseur suit 0,22 % du côté long",
              abs(Engraver.inkWidth(longSide: 3456) - 7.6032) < 0.001,
              "→ \(Engraver.inkWidth(longSide: 3456))")
        check(t, "le badge ne descend jamais sous 26 px",
              Engraver.badgeDiameter(longSide: 100) == 26)

        // Une capsule à deux chiffres : un « 12 » dans un disque rond déborderait.
        let one = Engraver.badgeSize(number: 9, intention: nil, longSide: 896)
        let two = Engraver.badgeSize(number: 12, intention: nil, longSide: 896)
        check(t, "un chiffre seul donne un disque rond", one.width == one.height)
        check(t, "deux chiffres donnent une capsule ×1,45",
              abs(two.width / two.height - 1.45) < 0.01, "→ \(two.width / two.height)")
        let labelled = Engraver.badgeSize(number: 3, intention: "texte à corriger",
                                          longSide: 896)
        check(t, "une intention allonge le badge", labelled.width > two.width)

        // Le halo bascule sur la luminance du fond. Sur fond blanc il doit être sombre,
        // sur fond noir il doit être clair — l'inverse rendrait l'encre illisible là où
        // elle compte le plus.
        let frame = Engraver.Frame(captureSize: CGSize(width: 400, height: 400),
                                   sourceRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                                   scale: 1)
        let shape = MarkShape.arrow(from: NormPoint(x: 0.3, y: 0.3),
                                    to: NormPoint(x: 0.7, y: 0.7))
        let onWhite = Engraver.haloColor(for: shape, frame: frame,
                                         map: LuminanceMap(solidImage(width: 400, height: 400,
                                                                      level: 255)),
                                         width: 4)
        let onBlack = Engraver.haloColor(for: shape, frame: frame,
                                         map: LuminanceMap(solidImage(width: 400, height: 400,
                                                                      level: 0)),
                                         width: 4)
        check(t, "le halo est sombre sur fond clair", onWhite == Engraver.haloDark)
        check(t, "le halo est clair sur fond sombre", onBlack == Engraver.haloLight)

        // Le placement : un badge ne doit ni sortir de l'image, ni recouvrir un badge
        // déjà posé — un numéro masqué ne se lit plus, et c'est par lui que l'agent
        // retrouve la marque.
        let size = CGSize(width: 400, height: 400)
        let box = CGRect(x: 150, y: 150, width: 100, height: 80)
        let first = Engraver.place(number: 1, intention: nil, around: box, in: size,
                                   avoiding: [], map: nil, frame: frame, longSide: 400)
        check(t, "le premier badge reste dans l'image",
              CGRect(origin: .zero, size: size).contains(first))
        check(t, "le premier badge ne recouvre pas la forme", !first.intersects(box))

        let second = Engraver.place(number: 2, intention: nil, around: box, in: size,
                                    avoiding: [first], map: nil, frame: frame, longSide: 400)
        check(t, "le second badge évite le premier", !second.intersects(first))

        // Le badge ne se pose PAS du côté de la pointe. C'est arrivé sur la première
        // gravure de contrôle : le fond y était le plus uni, et l'algorithme faisait
        // exactement ce qu'on lui demandait — on lui demandait la mauvaise chose.
        let head = Engraver.designated(shape, frame: frame)
        check(t, "le point désigné d'une flèche est sa pointe",
              head != nil && abs(head!.x - 280) < 1, "→ \(String(describing: head))")
        let away = Engraver.place(number: 4, intention: nil,
                                  around: Engraver.boundingRect(of: shape, frame: frame),
                                  in: size, avoiding: [], map: nil, frame: frame,
                                  longSide: 400, focus: head)
        check(t, "le badge s'écarte de la pointe",
              hypot(away.midX - head!.x, away.midY - head!.y) >= 26 * 1.5,
              "→ distance \(hypot(away.midX - head!.x, away.midY - head!.y))")

        // Une forme fermée n'a pas de point désigné : son contenu est à l'intérieur, et
        // le badge se range dehors de toute façon.
        check(t, "un cadre n'impose aucune exclusion",
              Engraver.designated(.rect(NormRect(bounding: [])), frame: frame) == nil)

        // ── Ce que l'écran montre EST ce que l'image contient ──────────────────
        //
        // La règle a manqué au premier essai réel : le calque posait le badge à la queue,
        // la gravure le posait là où le fond était le plus uni, et le numéro sautait d'un
        // côté à l'autre entre les deux. Ces vérifications interdisent la divergence.
        let shapes: [(String, MarkShape)] = [
            ("d'une flèche", .arrow(from: NormPoint(x: 0.35, y: 0.35), to: NormPoint(x: 0.65, y: 0.62))),
            ("d'une flèche inversée", .arrow(from: NormPoint(x: 0.65, y: 0.62), to: NormPoint(x: 0.35, y: 0.35))),
            ("d'un cadre", .rect(NormRect(bounding: [NormPoint(x: 0.30, y: 0.30),
                                                NormPoint(x: 0.62, y: 0.58)]))),
            ("d'un point", .point(NormPoint(x: 0.5, y: 0.5))),
            ("d'un surlignage", .highlight(NormRect(bounding: [NormPoint(x: 0.28, y: 0.44),
                                                          NormPoint(x: 0.66, y: 0.50)]))),
        ]
        for (label, shape) in shapes {
            let want = MarkGeometry.badgeAnchor(
                for: shape, offset: Engraver.badgeDiameter(longSide: 400) * 0.64,
                project: { frame.point($0) })
            let got = Engraver.place(number: 1, intention: nil,
                                     around: Engraver.boundingRect(of: shape, frame: frame),
                                     in: size, avoiding: [], map: nil, frame: frame,
                                     longSide: 400,
                                     focus: Engraver.designated(shape, frame: frame),
                                     preferred: want)
            let anchored = CGPoint(x: got.minX + got.width * want.anchorX, y: got.midY)
            check(t, "le badge gravé \(label) est là où le calque l'affiche",
                  hypot(anchored.x - want.point.x, anchored.y - want.point.y) < 0.6,
                  "→ calque \(want.point), gravé \(anchored)")
        }

        // Le repli n'a pas disparu pour autant : une position préférée hors de l'image
        // doit rendre la main aux huit candidates.
        let out = Engraver.place(number: 2, intention: nil,
                                 around: CGRect(x: 150, y: 150, width: 80, height: 60),
                                 in: size, avoiding: [], map: nil, frame: frame,
                                 longSide: 400,
                                 preferred: (CGPoint(x: -900, y: -900), 0))
        check(t, "une position préférée hors cadre bascule sur les candidates",
              CGRect(origin: .zero, size: size).contains(out), "→ \(out)")

        // Et deux badges ne se superposent jamais, même si leur position préférée est
        // la même : le second passe aux candidates.
        let same = (CGPoint(x: 200, y: 200), CGFloat(0))
        let first2 = Engraver.place(number: 1, intention: nil,
                                    around: CGRect(x: 150, y: 150, width: 80, height: 60),
                                    in: size, avoiding: [], map: nil, frame: frame,
                                    longSide: 400, preferred: same)
        let second2 = Engraver.place(number: 2, intention: nil,
                                     around: CGRect(x: 150, y: 150, width: 80, height: 60),
                                     in: size, avoiding: [first2], map: nil, frame: frame,
                                     longSide: 400, preferred: same)
        check(t, "deux badges de même position préférée ne se superposent pas",
              !first2.intersects(second2))

        // Une marque collée au bord : les positions candidates du dessus sortent toutes,
        // il doit en rester une exploitable.
        let atEdge = Engraver.place(number: 3, intention: nil,
                                    around: CGRect(x: 2, y: 370, width: 40, height: 28),
                                    in: size, avoiding: [], map: nil, frame: frame,
                                    longSide: 400)
        check(t, "une marque au bord garde son badge dans l'image",
              CGRect(origin: .zero, size: size).contains(atEdge), "→ \(atEdge)")

        // La gravure produit réellement des pixels d'encre.
        let engraved = Engraver.engrave(
            solidImage(width: 400, height: 400, level: 255),
            items: [Engraver.Item(number: 1, shape: shape, intention: "erreur")],
            frame: frame)
        check(t, "la gravure ne change pas les dimensions",
              engraved.width == 400 && engraved.height == 400)
        check(t, "la gravure dépose de l'encre vermillon", vermillonCount(engraved) > 500,
              "→ \(vermillonCount(engraved)) pixels")
    }

    // MARK: - Outils

    private static func solidImage(width: Int, height: Int, level: UInt8 = 128) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let v = CGFloat(level) / 255
        ctx.setFillColor(CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private static func vermillonCount(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var hits = 0
        for i in stride(from: 0, to: buffer.count, by: 4) {
            let r = Int(buffer[i]), g = Int(buffer[i + 1]), b = Int(buffer[i + 2])
            if r > 200, g < 110, b < 110, r - max(g, b) > 90 { hits += 1 }
        }
        return hits
    }
}
