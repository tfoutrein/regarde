import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'icône de la barre de menus, mesurée — S33 bis
//
// Ce fichier existe parce que j'ai eu tort deux fois de suite sur cette icône, en
// raisonnant au lieu de mesurer.
//
//   Première fois : `isTemplate = (tint == nil)` — donc faux dès qu'une teinte
//   existait — alors que `contentTintColor` ne teinte QUE les images template.
//   Deux lignes qui se contredisaient.
//
//   Deuxième fois : `isTemplate = true` partout. Mais un `NSStatusBarButton` avec
//   une image template est rendu par le SYSTÈME, à la couleur de la barre de
//   menus, et `contentTintColor` n'y peut rien. L'icône est sortie noire.
//
// Les deux fois, le raisonnement était plausible et le résultat faux. Ce qui
// manquait n'était pas de la réflexion, c'était un pixel compté.
//
// La conclusion des deux échecs : pour obtenir une icône COLORÉE dans la barre de
// menus, la couleur doit être DANS L'IMAGE — `SymbolConfiguration(paletteColors:)`
// — et l'image ne doit PAS être template, sans quoi le système la reprend.
//
// Ce test dessine l'image dans un bitmap et compte les pixels. Il tourne sans
// écran, sans permission et sans barre de menus : c'est du rendu hors écran.
// ─────────────────────────────────────────────────────────────────────────────

enum IconSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de l'icône de barre de menus ──\n")

        for (nom, symbole, teinte) in [
            ("session en cours", "record.circle", NSColor.systemRed),
            ("traitement", "circle.dotted", NSColor.systemOrange),
            ("permission manquante", "exclamationmark.circle", NSColor.systemRed),
        ] {
            mesurer(t, nom: nom, symbole: symbole, teinte: teinte)
        }

        // Et le cas sans teinte : l'icône doit rester TEMPLATE, pour suivre la
        // couleur de la barre de menus — noire en thème clair, blanche en sombre.
        // Une couleur codée en dur y serait illisible dans l'un des deux.
        if let img = StatusIcon.image(symbole: "circle", teinte: nil) {
            check(t, "sans teinte, l'image reste template — elle suit la barre de menus",
                  img.isTemplate)
        } else {
            check(t, "sans teinte, l'image est construite", false)
        }

        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    private static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    private static func mesurer(_ t: Tally, nom: String, symbole: String, teinte: NSColor) {
        guard let img = StatusIcon.image(symbole: symbole, teinte: teinte) else {
            check(t, "\(nom) — image construite", false, "symbole « \(symbole) » introuvable")
            return
        }
        check(t, "\(nom) — l'image N'EST PAS template",
              !img.isTemplate,
              img.isTemplate ? "template : le système la repeindrait à sa couleur" : "")

        guard let compte = teintes(de: img) else {
            check(t, "\(nom) — l'image se dessine", false); return
        }
        // La couleur attendue, en composantes.
        let voulue = teinte.usingColorSpace(.deviceRGB) ?? .red
        let dr = voulue.redComponent, dg = voulue.greenComponent, db = voulue.blueComponent

        check(t, "\(nom) — des pixels colorés existent",
              compte.colores > 0,
              "\(compte.colores) pixel(s) coloré(s) sur \(compte.opaques) opaques")

        check(t, "\(nom) — et ils portent la bonne couleur",
              compte.colores > 0 && abs(compte.r - dr) < 0.20
                && abs(compte.g - dg) < 0.20 && abs(compte.b - db) < 0.20,
              String(format: "moyenne (%.2f, %.2f, %.2f) attendue (%.2f, %.2f, %.2f)",
                     compte.r, compte.g, compte.b, dr, dg, db))

        // La contre-épreuve : la MÊME image sans configuration de palette doit être
        // grise ou noire. Si elle l'était déjà colorée, le test ne testerait rien.
        if let nue = NSImage(systemSymbolName: symbole, accessibilityDescription: nil),
           let nu = teintes(de: nue) {
            check(t, "\(nom) — sans palette, l'image n'est PAS colorée",
                  nu.colores == 0,
                  "\(nu.colores) pixel(s) coloré(s)")
        }
    }

    /// Dessine l'image dans un bitmap et rend la moyenne des pixels colorés.
    ///
    /// « Coloré » veut dire : opaque, et dont les composantes s'écartent assez du
    /// gris pour qu'un œil voie une couleur. Un symbole noir, blanc ou gris a ses
    /// trois composantes égales — c'est ce qui distingue « teinté » de « rendu par
    /// le système ».
    private static func teintes(de image: NSImage) -> (colores: Int, opaques: Int,
                                                       r: Double, g: Double, b: Double)? {
        let cote = 64
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: cote, height: cote))
        NSGraphicsContext.restoreGraphicsState()

        var colores = 0, opaques = 0
        var sr = 0.0, sg = 0.0, sb = 0.0
        for y in 0..<cote {
            for x in 0..<cote {
                guard let px = rep.colorAt(x: x, y: y) else { continue }
                guard px.alphaComponent > 0.5 else { continue }
                opaques += 1
                let r = px.redComponent, g = px.greenComponent, b = px.blueComponent
                let ecart = max(r, g, b) - min(r, g, b)
                if ecart > 0.15 { colores += 1; sr += r; sg += g; sb += b }
            }
        }
        let n = Double(max(colores, 1))
        return (colores, opaques, sr / n, sg / n, sb / n)
    }
}
