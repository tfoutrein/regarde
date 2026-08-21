import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Lecture du numéro de frame gravé par le témoin — S31, critère C11
//
// Le témoin dessine son numéro de frame en modules noirs et blancs (S29). Ce
// fichier le relit dans une image. C'est l'instrument du critère C11, et par
// conséquent le seul instrument existant contre le risque R5 — le bug B1, une
// image extraite au mauvais instant, invisible sur écran statique.
//
// UNE SEULE RÈGLE GOUVERNE CE CODE : **juste ou absent, jamais faux.**
//
// Un décodeur qui rend un mauvais numéro fait rendre à C11 un verdict faux, et
// C11 est ce qui doit attraper B1. Mieux vaut cent abstentions qu'une lecture
// erronée : chaque abstention porte un motif nommé, et le banc distingue ainsi
// « frame décalée » — ce qu'on cherche — de « réglette hors cadre » — une panne
// d'instrument.
//
// Il ne suppose NI la position de la réglette, NI le plein écran, NI l'absence
// de boîtage : il balaie l'image, trouve le localisateur, déduit le pas de
// grille, puis lit chaque bit par décision DIFFÉRENTIELLE entre deux rangées.
//
// DEUX PIÈGES, tous deux trouvés en écrivant l'implémentation de référence
// (`prototypes/lot0/Tools/lire-reglette.py`) contre une vraie capture, et tous
// deux absents de la conception :
//
//   1. « la plus longue plage sombre » ne trouve pas le localisateur. Le fond du
//      témoin est sombre et la passe de charge sort entre 8 et 33 sur 255 : la
//      plus longue plage sombre de l'image est une ligne de fond ENTIÈRE. La
//      plage doit être BORNÉE PAR DU BLANC des deux côtés — c'est à cela que
//      sert la zone de silence, et l'oublier fait chercher au mauvais endroit.
//
//   2. la ligne de balayage qui trouve la barre n'est pas le BORD de la barre.
//      Le balayage avance par pas et tombe où il tombe ; prendre ce y pour
//      l'origine des rangées les décale toutes d'une fraction de module, et les
//      échantillons mordent sur la rangée voisine.
//
// L'accord avec l'implémentation de référence Python n'est pas une élégance :
// c'est un ORACLE. Deux implémentations indépendantes qui rendent le même numéro
// sur la même image, sinon l'une des deux se trompe.
// ─────────────────────────────────────────────────────────────────────────────

enum Reglette {
    /// Côté d'un module, en pixels du tampon natif.
    ///
    /// Deux fois le plus grand bloc de transformation luma de HEVC (32×32) : un
    /// module de côté 2B contient toujours entièrement le bloc qui porte son
    /// centre, quelle que soit la position de la grille.
    static let module = 64
    static let cols = 34, rows = 6
    static let bitsDonnees = 20, bitsCRC = 8
    static var bits: Int { bitsDonnees + bitsCRC }
    static let masque = 0xF_FFFF
    static let crcPoly: UInt8 = 0x2F
    /// Init NON normalisée : elle sert de numéro de version du format. Un
    /// décodeur d'une autre génération refuse au lieu de rendre un nombre
    /// plausible.
    static let crcInit: UInt8 = 0xA5

    /// Le module mesuré peut descendre jusque-là avant qu'on refuse.
    ///
    /// À 30 px, la garde entre la fenêtre d'échantillonnage et le bord du module
    /// vaut 7,5 px, contre 3 px de portée du filtre de déblocage HEVC — facteur
    /// 2,5. En dessous, on refuse plutôt que de deviner.
    static let modulePlancher = 30.0

    static func crc8(_ g: Int) -> UInt8 {
        var c = crcInit
        for octet in [UInt8(g & 0xFF), UInt8((g >> 8) & 0xFF), UInt8((g >> 16) & 0x0F)] {
            c ^= octet
            for _ in 0..<8 { c = (c & 0x80) != 0 ? (c << 1) ^ crcPoly : c << 1 }
        }
        return c
    }

    /// Le mot de 28 bits pour une valeur de compteur. LSB en position 0.
    ///
    /// Le code de Gray fait basculer 4,1 bits par incrément en moyenne, contre
    /// une pointe à 20 bits une fois tous les 2¹⁹ en binaire naturel — une frame
    /// vingt fois plus chère à encoder, à un instant imprévisible.
    static func mot(pour v: Int) -> [Int] {
        let g = v ^ (v >> 1)
        let c = Int(crc8(g))
        return (0..<bits).map { k in
            k < bitsDonnees ? (g >> k) & 1 : (c >> (k - bitsDonnees)) & 1
        }
    }

    /// Inverse du code de Gray.
    static func deGray(_ g: Int) -> Int {
        var v = g, s = 1
        while s < bitsDonnees { v ^= v >> s; s <<= 1 }
        return v & masque
    }
}

enum FrameNumberReader {

    /// Pourquoi une lecture n'a pas eu lieu. Chaque motif est NOMMÉ, et remonté
    /// tel quel au banc, qui le journalise par marque.
    enum Refus: Equatable, CustomStringConvertible {
        case imageTropPetite(largeur: Int, hauteur: Int)
        case localisateurAbsent
        case localisateurAmbigu(paires: Int)
        case moduleHorsPlage(mesure: Double)
        case contrasteInsuffisant(mesure: Int)
        case cadreNonConforme(colonne: Int)
        case silenceNonConforme(rangee: Int, colonne: Int)
        case bitAmbigu(indice: Int, marge: Int)
        case desaccordDifferentielAbsolu(indice: Int)
        case crcInvalide(lu: UInt8, attendu: UInt8)

        var description: String {
            switch self {
            case .imageTropPetite(let w, let h): "image trop petite — \(w)×\(h)"
            case .localisateurAbsent: "localisateur absent"
            case .localisateurAmbigu(let n): "localisateur ambigu — \(n) paires candidates"
            case .moduleHorsPlage(let m): String(format: "pas de grille %.2f px hors plage", m)
            case .contrasteInsuffisant(let c): "contraste \(c)/255 insuffisant"
            case .cadreNonConforme(let k): "barre du cadre percée en colonne \(k)"
            case .silenceNonConforme(let r, let c): "zone de silence salie en (\(r), \(c))"
            case .bitAmbigu(let k, let m): "bit \(k) ambigu — marge \(m)"
            case .desaccordDifferentielAbsolu(let k): "bit \(k) — différentiel et seuil en désaccord"
            case .crcInvalide(let lu, let att):
                String(format: "CRC 0x%02X ≠ 0x%02X", lu, att)
            }
        }
    }

    /// Ce qu'une lecture RÉUSSIE remonte en plus du numéro.
    ///
    /// Le succès n'est pas muet : une lecture juste avec quatre bits faibles est
    /// une alerte que le banc doit consigner. C'est le signal précoce que
    /// l'encodage se dégrade, AVANT qu'il ne mente.
    struct Diag: Sendable, CustomStringConvertible {
        let module: Double
        /// Coin haut-gauche de l'empreinte, zone de silence comprise.
        let origine: CGPoint
        let contraste: Int
        let margeMin: Int
        let bitsFaibles: Int

        var description: String {
            String(format: "module %.2f · origine (%.0f, %.0f) · contraste %d · marge %d · %d bit(s) faible(s)",
                   module, origine.x, origine.y, contraste, margeMin, bitsFaibles)
        }
    }

    enum Lecture {
        case lu(v: Int, diag: Diag)
        case refus(Refus)

        var valeur: Int? { if case .lu(let v, _) = self { return v } else { return nil } }
        var refus: Refus? { if case .refus(let r) = self { return r } else { return nil } }
    }

    // ── Seuils ───────────────────────────────────────────────────────────────
    private static let seuilSombre = 96      // sous cette valeur, un pixel est « noir »
    private static let seuilClair = 160      // au-dessus, « blanc »
    private static let contrasteMin = 60     // écart différentiel minimal accepté
    private static let margeAmbigue = 51     // 0,20 × 255 : sous cette marge, on refuse
    private static let margeFaible = 100     // au-dessus du refus, mais à consigner

    /// Lit le numéro de frame dans une image.
    static func lire(_ image: CGImage) -> Lecture {
        guard let (w, h, gris) = gris8(image) else {
            return .refus(.imageTropPetite(largeur: image.width, hauteur: image.height))
        }
        // Il faut au minimum l'empreinte plus sa marge, au plancher de module.
        guard w >= Int(Double(Reglette.cols) * Reglette.modulePlancher),
              h >= Int(Double(Reglette.rows) * Reglette.modulePlancher) else {
            return .refus(.imageTropPetite(largeur: w, hauteur: h))
        }
        return decoder(w: w, h: h, gris: gris)
    }

    // MARK: - Balayage

    private static func decoder(w: Int, h: Int, gris: [UInt8]) -> Lecture {
        @inline(__always) func px(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, x < w, y >= 0, y < h else { return 0 }
            return Int(gris[y * w + x])
        }

        // ── 1. Le localisateur ───────────────────────────────────────────────
        //
        // Une plage sombre BORNÉE PAR DU BLANC des deux côtés. La barre du cadre
        // fait 32 modules ; la plus longue plage sombre possible dans une rangée
        // de données en fait 25 — atteinte quand le code de Gray vaut 0xFFFFF,
        // vérifié exhaustivement sur les 2²⁰ valeurs. 22 % d'écart, hors de toute
        // tolérance d'appariement.
        var plages: [(longueur: Int, x0: Int, y: Int)] = []
        // On balaie depuis le BAS : la réglette est collée en bas de l'écran.
        var y = h - 1
        while y > 0 {
            var run = 0, debut = 0
            for x in 0...w {
                let sombre = x < w && px(x, y) < seuilSombre
                if sombre {
                    if run == 0 { debut = x }
                    run += 1
                } else {
                    if run >= 16 {
                        let avant = debut > 0 ? px(debut - 1, y) : 0
                        let apres = x < w ? px(x, y) : 0
                        if avant > seuilClair && apres > seuilClair { plages.append((run, debut, y)) }
                    }
                    run = 0
                }
            }
            y -= 3
        }
        guard let barre = plages.max(by: { $0.longueur < $1.longueur }) else {
            return .refus(.localisateurAbsent)
        }

        // L'ambiguïté se compte en LOCALISATEURS CONCURRENTS, pas en plages.
        //
        // Compter toutes les plages n'a aucun sens : chaque rangée de données en
        // produit, sur chaque ligne de balayage, et le compte monte à plusieurs
        // centaines sur une réglette parfaitement lisible. Ce qui rendrait la
        // lecture ambiguë, c'est un SECOND groupe de plages aussi longues que la
        // meilleure et situé AILLEURS en x — deux réglettes dans l'image, ou un
        // motif de l'écran qui imite la barre.
        //
        // Une barre réelle donne une vingtaine de plages au même x0 : la hauteur
        // d'un module divisée par le pas de balayage. Un groupe d'au moins trois
        // est donc un vrai candidat, et un groupe isolé du bruit.
        let quasiMeilleures = plages.filter { Double($0.longueur) >= Double(barre.longueur) * 0.97 }
        var groupes: [(x0: Int, n: Int)] = []
        for p in quasiMeilleures {
            if let i = groupes.firstIndex(where: { abs($0.x0 - p.x0) <= 32 }) { groupes[i].n += 1 }
            else { groupes.append((p.x0, 1)) }
        }
        let concurrents = groupes.filter { $0.n >= 3 }
        if concurrents.count > 1 { return .refus(.localisateurAmbigu(paires: concurrents.count)) }

        let module = Double(barre.longueur) / 32.0
        guard module >= Reglette.modulePlancher else {
            return .refus(.moduleHorsPlage(mesure: module))
        }
        guard abs(module - Double(Reglette.module)) <= 1.0 else {
            return .refus(.moduleHorsPlage(mesure: module))
        }
        let m = module
        let x0 = Double(barre.x0)

        // ── 2. La barre jumelle, à trois modules ─────────────────────────────
        var yBarre = barre.y
        var trouvee = false
        for signe in [1.0, -1.0] {
            let y2 = Int((Double(barre.y) + signe * 3 * m).rounded())
            guard y2 >= 0, y2 < h else { continue }

            // La jumelle doit être BORNÉE PAR DU BLANC, exactement comme la
            // première. C'est le même piège que celui du localisateur, appliqué
            // au second temps — et il ne se voit pas quand la réglette est collée
            // en bas de l'écran, parce que la position symétrique tombe alors hors
            // de l'image. Sans cette borne, une zone de fond sombre passe : trente-
            // deux sondes y lisent toutes « noir », le décodeur prend le fond pour
            // la jumelle, cale ses rangées une barre trop bas, et refuse ensuite
            // pour « zone de silence salie » — un refus juste, rendu pour une
            // raison fausse, qui aurait envoyé chercher le défaut ailleurs.
            let avant = px(Int(x0) - 1, y2)
            let apres = px(Int(x0 + 32 * m) + 1, y2)
            guard avant > seuilClair, apres > seuilClair else { continue }

            var sombres = 0
            for k in 0..<32 where px(Int(x0 + (Double(k) + 0.5) * m), y2) < seuilSombre { sombres += 1 }
            if sombres >= 31 { yBarre = min(barre.y, y2); trouvee = true; break }
        }
        guard trouvee else { return .refus(.localisateurAbsent) }

        // ── 3. Remonter au BORD de la barre ──────────────────────────────────
        //
        // `yBarre` est une ligne de balayage prise dans la barre, pas son bord :
        // le balayage avance de trois en trois. La prendre pour origine des
        // rangées les décalerait toutes d'une fraction de module.
        var yHaut = yBarre
        let sonde = Int(x0 + 16 * m)
        while yHaut > 0 && px(sonde, yHaut - 1) < seuilSombre { yHaut -= 1 }

        // ── 4. Repères ───────────────────────────────────────────────────────
        //
        // `x0` est le début de la barre, donc la colonne 1 de l'empreinte (la 0
        // est le silence, blanc). `yHaut` est le bord haut de la barre, donc la
        // rangée 1. D'où les décalages ci-dessous.
        func colX(_ c: Int) -> Double { x0 + (Double(c) + 0.5) * m }        // c = 0 → montant gauche
        func rowY(_ r: Int) -> Int { Int((Double(yHaut) + (Double(r) + 0.5) * m).rounded()) }

        let demi = max(1, Int(m / 4))
        func echantillon(_ cx: Double, _ cy: Int) -> Int {
            var somme = 0, n = 0
            for dy in -demi..<demi {
                for dx in -demi..<demi {
                    somme += px(Int(cx) + dx, cy + dy); n += 1
                }
            }
            return n > 0 ? somme / n : 0
        }

        // ── 5. Le cadre et les zones de silence ──────────────────────────────
        for k in stride(from: 0, to: 32, by: 4) {
            if echantillon(colX(k), rowY(0)) > seuilSombre { return .refus(.cadreNonConforme(colonne: k)) }
            if echantillon(colX(k), rowY(3)) > seuilSombre { return .refus(.cadreNonConforme(colonne: k)) }
        }
        // Silence : une rangée au-dessus de la barre haute, une sous la barre basse,
        // et les DEUX colonnes extérieures — qui font partie de la zone de silence
        // et dont l'omission laissait passer une salissure sur tout le pourtour.
        for (r, etiquette) in [(-1, 0), (4, 5)] {
            for c in [-1, 0, 16, 31, 32] where echantillon(colX(c), rowY(r)) < seuilClair {
                return .refus(.silenceNonConforme(rangee: etiquette, colonne: c + 1))
            }
        }
        for r in [0, 1, 2, 3] {
            for c in [-1, 32] where echantillon(colX(c), rowY(r)) < seuilClair {
                return .refus(.silenceNonConforme(rangee: r + 1, colonne: c + 1))
            }
        }
        // Colonnes témoins blanches, aux deux bouts de l'intérieur.
        for r in [1, 2] {
            for c in [1, 30] where echantillon(colX(c), rowY(r)) < seuilClair {
                return .refus(.silenceNonConforme(rangee: r, colonne: c))
            }
        }

        // ── 6. Les 28 bits, par décision DIFFÉRENTIELLE ──────────────────────
        //
        // Le bit ne se lit pas contre un seuil, il se lit ENTRE DEUX CASES. Cette
        // décision est invariante à tout décalage commun aux deux échantillons :
        // plage limitée contre plage pleine, gamma, décalage SAO du bloc, dérive
        // de luminance du rendu sous-jacent. Le seuil absolu n'intervient qu'en
        // RECOUPEMENT — les deux échantillons doivent en plus tomber chacun du
        // bon côté — et jamais comme décision.
        var g = 0
        var crcLu: UInt8 = 0
        var contraste = 255, margeMin = 255, faibles = 0
        for k in 0..<Reglette.bits {
            let c = 2 + k
            let haut = echantillon(colX(c), rowY(1))
            let bas = echantillon(colX(c), rowY(2))
            let ecart = abs(haut - bas)
            contraste = min(contraste, ecart)
            guard ecart >= contrasteMin else { return .refus(.contrasteInsuffisant(mesure: ecart)) }

            let marge = min(abs(haut - 128), abs(bas - 128))
            margeMin = min(margeMin, marge)
            if marge < margeAmbigue { return .refus(.bitAmbigu(indice: k, marge: marge)) }
            if marge < margeFaible { faibles += 1 }

            let bit = haut > bas ? 1 : 0
            // Recoupement absolu : la case retenue doit être franchement claire et
            // l'autre franchement sombre. Un désaccord signale que les deux cases
            // ont dérivé du même côté — le différentiel seul y survivrait à tort.
            let clair = bit == 1 ? haut : bas
            let sombre = bit == 1 ? bas : haut
            guard clair > seuilClair, sombre < seuilSombre else {
                return .refus(.desaccordDifferentielAbsolu(indice: k))
            }
            if k < Reglette.bitsDonnees { g |= bit << k }
            else { crcLu |= UInt8(bit) << UInt8(k - Reglette.bitsDonnees) }
        }

        let attendu = Reglette.crc8(g)
        guard crcLu == attendu else { return .refus(.crcInvalide(lu: crcLu, attendu: attendu)) }

        return .lu(v: Reglette.deGray(g),
                   diag: Diag(module: m,
                              origine: CGPoint(x: x0 - m, y: Double(yHaut) - m),
                              contraste: contraste, margeMin: margeMin, bitsFaibles: faibles))
    }

    // MARK: - Rendu gris

    /// Redessine l'image en gris 8 bits, un octet par pixel.
    ///
    /// Passer par un contexte plutôt que par les octets bruts de l'image évite
    /// d'avoir à connaître son format : la capture arrive en BGRA, une frame
    /// extraite d'un asset peut arriver autrement, et une conversion faite à la
    /// main sur le mauvais ordre de composantes lirait la réglette à l'envers.
    private static func gris8(_ image: CGImage) -> (Int, Int, [UInt8])? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var tampon = [UInt8](repeating: 0, count: w * h)
        let ok = tampon.withUnsafeMutableBytes { octets -> Bool in
            guard let base = octets.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (w, h, tampon) : nil
    }
}
