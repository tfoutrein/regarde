import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Autotest du décodeur de réglette — S31
//
// Tourne sans écran, sans permission et sans témoin : il fabrique ses propres
// images. C'est le point — le décodeur est l'instrument de C11, et un instrument
// dont la vérification exige l'appareil qu'il mesure ne se vérifie jamais.
//
// Trois familles :
//
//   l'ALLER-RETOUR      on grave un numéro, on le relit, on compare. Sur les
//                       valeurs limites et sur un échantillon régulier.
//   les NEUF REFUS      une image fabriquée par motif, et le décodeur doit rendre
//                       CE refus-là — jamais une valeur. Un refus qu'on ne sait
//                       pas provoquer est un refus qu'on ne sait pas avoir.
//   les VECTEURS        les huit couples (V, G, CRC) de la table de référence,
//                       que la page publie aussi de son côté. L'accord des deux
//                       implémentations se constate au lieu de s'espérer.
// ─────────────────────────────────────────────────────────────────────────────

enum RegletteSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la réglette (S31) ──\n")

        vecteurs(t)
        allerRetour(t)
        refus(t)
        robustesse(t)

        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    private static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            t.passed += 1
            print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)"))
        } else {
            t.failed += 1
            print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)"))
        }
    }

    // MARK: - Les huit vecteurs de référence

    /// La table du format, recopiée telle quelle. La page en publie une copie
    /// dans chaque dépôt ; le banc compare les deux.
    private static let table: [(v: Int, g: Int, crc: UInt8)] = [
        (0, 0x00000, 0x14), (1, 0x00001, 0x1A), (2, 0x00003, 0x06), (3, 0x00002, 0x08),
        (1023, 0x00200, 0xE9), (1024, 0x00600, 0x3C),
        (524287, 0x40000, 0xA8), (1048575, 0x80000, 0x43),
    ]

    private static func vecteurs(_ t: Tally) {
        print("· Vecteurs de contrôle du format")
        for cas in table {
            let g = cas.v ^ (cas.v >> 1)
            let crc = Reglette.crc8(g)
            check(t, String(format: "V=%d → G=0x%05X, CRC=0x%02X", cas.v, cas.g, cas.crc),
                  g == cas.g && crc == cas.crc,
                  g == cas.g && crc == cas.crc ? "" : String(format: "obtenu G=0x%05X CRC=0x%02X", g, crc))
        }
        // L'inverse du code de Gray, sur toute la plage utile.
        var inversions = 0
        for v in stride(from: 0, to: Reglette.masque, by: 997) {
            if Reglette.deGray(v ^ (v >> 1)) != v { inversions += 1 }
        }
        check(t, "deGray inverse le code de Gray sur 1 052 valeurs réparties",
              inversions == 0, inversions == 0 ? "" : "\(inversions) échecs")
    }

    // MARK: - Aller-retour

    private static func allerRetour(_ t: Tally) {
        print("\n· Aller-retour : graver puis relire")
        // Les limites, plus des valeurs qui font basculer beaucoup de bits.
        let cas = [0, 1, 2, 3, 255, 256, 1023, 1024, 65535, 65536,
                   524287, 524288, 699050, 1048574, 1048575]
        for v in cas {
            guard let image = graver(v) else {
                check(t, "V=\(v) — image fabriquée", false, "rendu impossible"); continue
            }
            let lecture = FrameNumberReader.lire(image)
            switch lecture {
            case .lu(let lu, let diag):
                check(t, "V=\(v) relu", lu == v,
                      lu == v ? String(format: "module %.1f, contraste %d", diag.module, diag.contraste)
                              : "lu \(lu)")
            case .refus(let r):
                check(t, "V=\(v) relu", false, "refus : \(r)")
            }
        }

        // 699050 est le pire cas de plage noire : G vaut 0xFFFFF, donc les vingt
        // bits de données sont noirs sur la rangée complémentaire. C'est la valeur
        // qui met le localisateur le plus à l'épreuve — 25 modules consécutifs
        // contre 32 pour la barre du cadre.
        if let image = graver(699050), case .lu(let lu, _) = FrameNumberReader.lire(image) {
            check(t, "le pire cas de plage noire (V=699050, G=0xFFFFF) ne trompe pas le localisateur",
                  lu == 699050, "lu \(lu)")
        } else {
            check(t, "le pire cas de plage noire ne trompe pas le localisateur", false)
        }

        // La réglette doit se trouver où qu'elle soit dans l'image : le décodeur
        // ne suppose ni le plein écran, ni l'absence de boîtage.
        for (dx, dy, nom) in [(0, 0, "collée en bas à gauche"),
                              (600, 0, "décalée à droite"),
                              (120, 400, "au milieu — cas d'une frame boîtée")] {
            guard let image = graver(4242, decalageX: dx, decalageY: dy) else { continue }
            let lecture = FrameNumberReader.lire(image)
            check(t, "réglette \(nom)", lecture.valeur == 4242,
                  lecture.valeur == 4242 ? "" : "\(lecture.refus.map(String.init(describing:)) ?? "lu \(lecture.valeur ?? -1)")")
        }
    }

    // MARK: - Les neuf refus

    private static func refus(_ t: Tally) {
        print("\n· Les refus, provoqués un par un")

        // 1 — image trop petite
        if let petite = image(largeur: 200, hauteur: 100, peindre: { _, _ in }) {
            let r = FrameNumberReader.lire(petite).refus
            check(t, "image trop petite", { if case .imageTropPetite = r { return true }; return false }(),
                  "\(r.map(String.init(describing:)) ?? "AUCUN REFUS")")
        }

        // 2 — localisateur absent : une image uniformément sombre, comme une scène
        //     sans réglette. C'est le cas qui a fait trouver le premier piège.
        if let vide = image(largeur: 2560, hauteur: 1440, peindre: { ctx, r in
            ctx.setFillColor(gray: 0.04, alpha: 1); ctx.fill(r)
        }) {
            let r = FrameNumberReader.lire(vide).refus
            check(t, "fond sombre sans réglette — localisateur absent",
                  r == .localisateurAbsent, "\(r.map(String.init(describing:)) ?? "AUCUN REFUS")")
        }

        // 4 — contraste insuffisant : les deux rangées peintes en gris voisins.
        if let terne = graver(1234, encreRangee0: 0.48, encreRangee1: 0.52) {
            let r = FrameNumberReader.lire(terne).refus
            check(t, "deux rangées de gris voisins — contraste insuffisant",
                  { if case .contrasteInsuffisant = r { return true }
                    if case .bitAmbigu = r { return true }
                    if case .desaccordDifferentielAbsolu = r { return true }
                    return false }(),
                  "\(r.map(String.init(describing:)) ?? "AUCUN REFUS")")
        }

        // 5 — barre du cadre percée
        if let percee = graver(777, saboter: .barrePercee) {
            let r = FrameNumberReader.lire(percee).refus
            check(t, "barre du cadre percée", r != nil && FrameNumberReader.lire(percee).valeur == nil,
                  "\(r.map(String.init(describing:)) ?? "AUCUN REFUS")")
        }

        // 6 — zone de silence salie
        if let salie = graver(888, saboter: .silenceSali) {
            let r = FrameNumberReader.lire(salie).refus
            check(t, "zone de silence salie", r != nil,
                  "\(r.map(String.init(describing:)) ?? "AUCUN REFUS")")
        }

        // 9 — CRC invalide : un bit de donnée retourné, le CRC reste celui de
        //     l'original. C'est LE refus qui compte : sans lui, le banc rendrait
        //     un numéro faux, et C11 un verdict faux.
        if let faux = graver(4096, saboter: .bitRetourne(3)) {
            let lecture = FrameNumberReader.lire(faux)
            let r = lecture.refus
            check(t, "un bit de donnée retourné — CRC invalide",
                  { if case .crcInvalide = r { return true }; return false }(),
                  "\(r.map(String.init(describing:)) ?? "AUCUN REFUS, valeur \(lecture.valeur ?? -1)")")
            check(t, "et AUCUNE valeur n'est rendue", lecture.valeur == nil)
        }

        // La contre-épreuve qui donne son sens aux autres : sur les 20 bits de
        // données, retourner n'importe lequel doit toujours faire refuser.
        var passesEnSilence = 0
        for k in 0..<Reglette.bitsDonnees {
            guard let faux = graver(123456, saboter: .bitRetourne(k)) else { continue }
            if FrameNumberReader.lire(faux).valeur != nil { passesEnSilence += 1 }
        }
        check(t, "aucun des 20 bits de donnée retournés ne passe en silence",
              passesEnSilence == 0, passesEnSilence == 0 ? "20/20 refusés" : "\(passesEnSilence) ont menti")
    }

    // MARK: - Robustesse

    private static func robustesse(_ t: Tally) {
        print("\n· Robustesse")

        // Un fond clair sous la réglette : la zone de silence est blanche, donc le
        // localisateur ne peut plus s'appuyer sur « bornée par du blanc » de façon
        // triviale. Il doit quand même trouver la barre.
        if let clair = graver(31337, fond: 0.92) {
            check(t, "réglette sur fond clair", FrameNumberReader.lire(clair).valeur == 31337,
                  "\(FrameNumberReader.lire(clair).refus.map(String.init(describing:)) ?? "")")
        }

        // Un bruit léger, comme en laisse un encodage avec pertes.
        if let bruitee = graver(55555, bruit: 12) {
            let lecture = FrameNumberReader.lire(bruitee)
            check(t, "réglette bruitée de ±12/255", lecture.valeur == 55555,
                  lecture.valeur == 55555 ? "" : "\(lecture.refus.map(String.init(describing:)) ?? "")")
        }

        // Le diagnostic doit dire la vérité sur la géométrie : c'est lui que le
        // banc croise avec ce que la page publie.
        if let image = graver(2024, decalageX: 320, decalageY: 128),
           case .lu(_, let diag) = FrameNumberReader.lire(image) {
            check(t, "le diagnostic rend le pas de grille exact",
                  abs(diag.module - Double(Reglette.module)) < 0.5,
                  String(format: "%.2f", diag.module))
            check(t, "et l'origine de l'empreinte à deux pixels près",
                  abs(diag.origine.x - 320) <= 2 && abs(diag.origine.y - 128) <= 2,
                  String(format: "(%.0f, %.0f) attendu (320, 128)", diag.origine.x, diag.origine.y))
        } else {
            check(t, "le diagnostic rend la géométrie", false)
        }
    }

    // MARK: - Rendu d'une réglette

    enum Sabotage {
        case aucun
        case barrePercee
        case silenceSali
        case bitRetourne(Int)
    }

    /// Fabrique une image portant la réglette du numéro `v`.
    ///
    /// Le rendu est délibérément écrit à la main plutôt que repris du témoin :
    /// deux implémentations indépendantes du MÊME format, et un désaccord entre
    /// elles est un désaccord qu'on veut voir.
    private static func graver(_ v: Int,
                               decalageX: Int = 0, decalageY: Int = 0,
                               fond: CGFloat = 0.04,
                               encreRangee0: CGFloat = 1.0, encreRangee1: CGFloat = 0.0,
                               bruit: Int = 0,
                               saboter: Sabotage = .aucun) -> CGImage? {
        let M = Reglette.module
        let largeur = max(2560, decalageX + Reglette.cols * M + M)
        let hauteur = max(1440, decalageY + Reglette.rows * M + M)

        var mot = Reglette.mot(pour: v)
        if case .bitRetourne(let k) = saboter, k < mot.count { mot[k] ^= 1 }

        return image(largeur: largeur, hauteur: hauteur) { ctx, cadre in
            ctx.setFillColor(gray: fond, alpha: 1); ctx.fill(cadre)

            // Origine de l'empreinte en coordonnées d'IMAGE (y vers le bas). Le
            // contexte a son origine en bas à gauche : on convertit à chaque rect.
            let ox = decalageX
            let oy = decalageY == 0 ? hauteur - Reglette.rows * M - M : decalageY

            func poser(_ col: Int, _ rang: Int, _ gris: CGFloat) {
                let x = ox + col * M
                let yHaut = oy + rang * M
                ctx.setFillColor(gray: gris, alpha: 1)
                ctx.fill(CGRect(x: x, y: hauteur - yHaut - M, width: M, height: M))
            }

            // Zones de silence et colonnes témoins : tout blanc d'abord.
            for r in 0..<Reglette.rows { for c in 0..<Reglette.cols { poser(c, r, 1.0) } }
            // Barres du cadre.
            var perceeFaite = false
            for c in 1...32 {
                var gris: CGFloat = 0.0
                if case .barrePercee = saboter, c == 17, !perceeFaite { gris = 1.0; perceeFaite = true }
                poser(c, 1, gris); poser(c, 4, 0.0)
            }
            // Montants du cadre.
            for r in 1...4 { poser(1, r, 0.0); poser(32, r, 0.0) }
            // Les 28 colonnes de données, sur deux rangées complémentaires.
            for k in 0..<Reglette.bits {
                let c = 3 + k
                poser(c, 2, mot[k] == 1 ? encreRangee0 : encreRangee1)
                poser(c, 3, mot[k] == 1 ? encreRangee1 : encreRangee0)
            }
            if case .silenceSali = saboter {
                ctx.setFillColor(gray: 0.0, alpha: 1)
                ctx.fill(CGRect(x: ox, y: hauteur - oy - M, width: M, height: M))
            }
            if bruit > 0 {
                // Un damier de faible amplitude : déterministe, donc rejouable.
                let a = CGFloat(bruit) / 255.0
                for i in stride(from: 0, to: largeur, by: 7) {
                    for j in stride(from: 0, to: hauteur, by: 11) {
                        ctx.setFillColor(gray: ((i / 7 + j / 11) % 2 == 0) ? 1 : 0, alpha: a)
                        ctx.fill(CGRect(x: i, y: j, width: 7, height: 11))
                    }
                }
            }
        }
    }

    private static func image(largeur: Int, hauteur: Int,
                              peindre: (CGContext, CGRect) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: largeur, height: hauteur,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        peindre(ctx, CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        return ctx.makeImage()
    }
}
