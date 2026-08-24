import AppKit

// ─────────────────────────────────────────────────────────────────────────────
// Les trois états du projet, et leurs pastilles — S51, ADR-0017, risque R2
//
// R2 dit le danger : la confirmation de projet se dégrade en réflexe. Un rapport
// poussé dans le mauvais dépôt se découvre dans une pull request, des jours plus
// tard. La parade du plan : trois états VISUELLEMENT distincts — pas trois
// libellés dans la même couleur — et un seuil écrit avant la première mesure
// (lot4-seuils.md, n°8) : ΔE*ab ≥ 20 entre chaque paire de teintes, mesuré sur
// CAPTURES du rendu, pas sur les constantes du code — les constantes disent ce
// qu'on a écrit, la capture dit ce qu'on voit.
//
// Le rouge pour l'ambigu est un choix, pas un hasard : c'est la couleur qui
// interrompt un réflexe. L'ambigu n'est pas une erreur — c'est l'état où le
// produit REFUSE de deviner (S52 : « plusieurs cwd → ambigu, jamais tranché »)
// et où l'utilisateur doit lever les yeux.
// ─────────────────────────────────────────────────────────────────────────────

enum EtatProjet: String, CaseIterable {
    case certain, probable, ambigu

    /// Les teintes, en sRGB explicite — pas les couleurs sémantiques du système,
    /// qui varient avec le thème et rendraient le seuil n°8 non reproductible.
    var teinte: NSColor {
        switch self {
        case .certain:  NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        case .probable: NSColor(srgbRed: 1.000, green: 0.584, blue: 0.000, alpha: 1)
        case .ambigu:   NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 1)
        }
    }

    var libelle: String {
        switch self {
        case .certain: "certain"
        case .probable: "probable"
        case .ambigu: "ambigu"
        }
    }
}

enum PastilleProjet {

    /// Dessine la pastille d'un état dans un bitmap — le MÊME dessin que le
    /// sélecteur affiche. C'est ce bitmap que l'autotest mesure : la chaîne
    /// complète NSColor → CoreGraphics → pixels, celle que l'œil recevra.
    static func rendre(_ etat: EtatProjet, cote: Int = 24) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        etat.teinte.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: cote - 4, height: cote - 4)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// La vue que le sélecteur emploie — pastille + libellé, la pastille d'abord :
    /// la couleur se lit avant le mot, c'est tout l'objet.
    @MainActor
    static func vue(_ etat: EtatProjet) -> NSView {
        let pile = NSStackView()
        pile.orientation = .horizontal
        pile.spacing = 6
        let rond = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        rond.wantsLayer = true
        rond.layer?.backgroundColor = etat.teinte.cgColor
        rond.layer?.cornerRadius = 7
        rond.widthAnchor.constraint(equalToConstant: 14).isActive = true
        rond.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let texte = NSTextField(labelWithString: etat.libelle)
        texte.font = .systemFont(ofSize: 11, weight: .medium)
        pile.addArrangedSubview(rond)
        pile.addArrangedSubview(texte)
        return pile
    }
}
