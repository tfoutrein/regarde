import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Table de cas de la conversion de coordonnées — `Regarde --geometry-test`
//
// Le plan l'exige avant toute ligne de dessin, et pour une raison précise : le décalage
// ×2 et l'origine négative ne se voient PAS sur une configuration mono-écran Retina,
// c'est-à-dire sur la machine de développement, en permanence. Le défaut se
// manifesterait au lot 3, mêlé aux bugs de temps, et coûterait trois fois plus cher.
//
// `ScreenGeometry` ne dépend pas d'AppKit précisément pour rendre ces cas possibles :
// on fabrique des dispositions qu'on n'a pas — écran non-Retina à gauche, écran plus
// haut que le principal, échelles mixtes — et on vérifie les conversions à la main.
//
// Chaque cas porte le calcul attendu en commentaire. Un test dont on ne peut pas
// refaire le calcul de tête ne prouve rien quand il tombe.
// ─────────────────────────────────────────────────────────────────────────────

enum GeometrySelfTest {

    // MARK: - Dispositions

    /// MacBook Pro 14" seul. Le cas où rien ne se voit.
    static let soloRetina = ScreenGeometry(screens: [
        ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2),
    ])

    /// La configuration réelle de la machine de développement : un externe 3440×1440
    /// non-Retina, à gauche ET au-dessus du portable.
    ///
    /// C'est le cas qui exerce les deux pièges à la fois — origine x négative et
    /// origine y d'événement négative.
    static let realWorld = ScreenGeometry(screens: [
        ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2),
        ScreenInfo(displayID: 3, cocoaFrame: CGRect(x: -971, y: 1117, width: 3440, height: 1440), scale: 1),
    ])

    /// Externe non-Retina strictement à gauche, aligné en bas. Le cas du plan.
    static let externalLeft = ScreenGeometry(screens: [
        ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2),
        ScreenInfo(displayID: 2, cocoaFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1),
    ])

    /// Externe à droite, plus grand que le principal.
    static let externalRight = ScreenGeometry(screens: [
        ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2),
        ScreenInfo(displayID: 2, cocoaFrame: CGRect(x: 1728, y: 0, width: 2560, height: 1440), scale: 1),
    ])

    /// Externe Retina au-dessus : deux écrans à l'échelle 2, mais l'un en y positif.
    static let externalAbove = ScreenGeometry(screens: [
        ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2),
        ScreenInfo(displayID: 2, cocoaFrame: CGRect(x: 0, y: 1117, width: 1728, height: 1117), scale: 2),
    ])

    // MARK: - Harnais

    /// Compteurs portés par une instance : Swift 6 refuse l'état global mutable, et
    /// le contourner par `nonisolated(unsafe)` serait admettre une course qu'on n'a
    /// aucune raison d'avoir ici.
    private final class Tally {
        var failures = 0
        var checks = 0
        /// Pour les vérifications qui ne comparent pas deux points ou deux tailles.
        func record(_ ok: Bool) { checks += 1; if !ok { failures += 1 } }
    }

    private static func expect(_ t: Tally, _ label: String, _ got: CGPoint, _ want: CGPoint,
                               tolerance: CGFloat = 0.001) {
        t.checks += 1
        let ok = abs(got.x - want.x) <= tolerance && abs(got.y - want.y) <= tolerance
        if !ok {
            t.failures += 1
            print(String(format: "    ✗ %@ → (%.1f, %.1f), attendu (%.1f, %.1f)",
                         label, got.x, got.y, want.x, want.y))
        }
    }

    private static func expect(_ t: Tally, _ label: String, _ got: CGSize, _ want: CGSize) {
        t.checks += 1
        if abs(got.width - want.width) > 0.001 || abs(got.height - want.height) > 0.001 {
            t.failures += 1
            print(String(format: "    ✗ %@ → %.0f×%.0f, attendu %.0f×%.0f",
                         label, got.width, got.height, want.width, want.height))
        }
    }

    private static func section(_ t: Tally, _ title: String, _ body: () -> Void) {
        let before = t.failures
        body()
        print("  [\(t.failures == before ? "✓" : "✗")] \(title)")
    }

    // MARK: - Les cas

    /// Les six dispositions du refus d'écran — S33, spécification § 3.3.
    ///
    /// Fabriquées, parce qu'on ne met pas un moniteur en rotation portrait ni un
    /// jeu de recopie en place pour lancer un test. C'est toute la raison pour
    /// laquelle la décision est une fonction pure sur trois entrées.
    private static func refusDEcran(_ t: Tally) {
        section(t, "écrans écartés — rotation portrait et recopie vidéo") {
            func cas(_ nom: String, rotation: Double, mirrorSet: Bool, recopieDe: UInt32,
                     attendu: RefusEcran?) {
                let got = ScreenInfo.refus(rotation: rotation,
                                           dansJeuDeRecopie: mirrorSet, recopieDe: recopieDe)
                let ok = got == attendu
                t.record(ok)
                // Muet en cas de succès, comme le reste du fichier : une table de
                // cas qui déroule ses trente lignes vertes noie celle qui rougit.
                if !ok {
                    print("      ✗ \(nom) → \(got.map(\.rawValue) ?? "capturable"), "
                          + "attendu \(attendu.map(\.rawValue) ?? "capturable")")
                }
            }

            // 1 — L'écran ordinaire, qui doit rester capturable.
            cas("paysage, hors recopie", rotation: 0, mirrorSet: false, recopieDe: 0, attendu: nil)
            // 2 — La rotation portrait : largeur et hauteur inversées entre
            //     CGDisplayBounds et le tampon, donc toute conversion transposée.
            cas("rotation 90°", rotation: 90, mirrorSet: false, recopieDe: 0,
                attendu: .rotationPortrait)
            // 3 — L'autre sens, tout aussi cassant.
            cas("rotation 270°", rotation: 270, mirrorSet: false, recopieDe: 0,
                attendu: .rotationPortrait)
            // 4 — 180° n'inverse PAS les dimensions : la conversion y reste juste,
            //     et refuser serait refuser une fois de trop.
            cas("rotation 180°", rotation: 180, mirrorSet: false, recopieDe: 0, attendu: nil)
            // 5 — Le SECONDAIRE d'un jeu de recopie : c'est lui qu'on écarte.
            cas("recopie d'un autre écran", rotation: 0, mirrorSet: true, recopieDe: 3,
                attendu: .recopieVideo)
            // 6 — La SOURCE du jeu de recopie reste capturable. Écarter les deux
            //     ne laisserait aucun écran, et la session n'aurait plus rien à
            //     capturer — un refus juste appliqué une fois de trop.
            cas("source du jeu de recopie", rotation: 0, mirrorSet: true, recopieDe: 0,
                attendu: nil)
            // La combinaison : la recopie prime, parce qu'elle dit sur QUEL écran
            // la marque atterrirait, ce qui est le défaut le plus grave des deux.
            cas("en recopie ET en rotation", rotation: 90, mirrorSet: true, recopieDe: 3,
                attendu: .recopieVideo)

            // Une disposition complète : deux écrans, dont un écarté.
            let g = ScreenGeometry(screens: [
                ScreenInfo(displayID: 1, cocoaFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                           scale: 2),
                ScreenInfo(displayID: 3, cocoaFrame: CGRect(x: -971, y: 1117, width: 3440, height: 1440),
                           scale: 1, refus: .recopieVideo),
            ])
            let ok = g.capturables.count == 1 && g.refuses.count == 1
                  && g.capturables[0].displayID == 1 && g.refuses[0].displayID == 3
            t.record(ok)
            if !ok { print("      ✗ la disposition ne sépare pas capturables et écartés") }

            // Et l'écran écarté reste TROUVABLE par un point : c'est ce qui permet
            // de refuser en le NOMMANT, au lieu de ne rien trouver et de se taire.
            let dessus = g.screen(containingEvent: CGPoint(x: -500, y: 200))
            let trouve = dessus?.displayID == 3 && dessus?.refus == .recopieVideo
            t.record(trouve)
            if !trouve { print("      ✗ un point sur l'écran écarté ne le trouve pas avec sa raison") }
        }
    }

    static func runAll() -> Int {
        let t = Tally()
        print("\nConversion de coordonnées — table de cas")
        print("────────────────────────────────────────")
        refusDEcran(t)

        section(t, "écran unique Retina") {
            let g = soloRetina
            let s = g.screens[0]
            // flipHeight = 1117. Un point tout en haut de l'écran en espace événement
            // (y=0) est tout en haut en Cocoa, donc y = 1117.
            expect(t, "event(0,0) → cocoa", g.cocoaGlobal(fromEvent: .zero), CGPoint(x: 0, y: 1117))
            expect(t, "event(0,1117) → cocoa", g.cocoaGlobal(fromEvent: CGPoint(x: 0, y: 1117)), .zero)
            // L'écran commence en (0,0) : les coordonnées locales valent les coordonnées Cocoa.
            expect(t, "windowLocal du coin haut-gauche",
                   g.windowLocal(fromEvent: .zero, on: s), CGPoint(x: 0, y: 1117))
            // Retina : 100 pt depuis le haut = 200 px.
            expect(t, "pixel(100,100)", g.pixel(fromEvent: CGPoint(x: 100, y: 100), on: s),
                   CGPoint(x: 200, y: 200))
            expect(t, "taille de capture", g.pixelSize(of: s), CGSize(width: 3456, height: 2234))
        }

        section(t, "machine réelle — externe non-Retina à gauche ET au-dessus") {
            let g = realWorld
            let ext = g.screens[1]
            // cocoaFrame de l'externe : x −971..2469, y 1117..2557.
            // eventFrame.y = flipHeight − maxY = 1117 − 2557 = −1440.
            expect(t, "eventFrame de l'externe",
                   g.eventFrame(of: ext).origin, CGPoint(x: -971, y: -1440))
            // Coin haut-gauche de l'externe, en espace événement.
            let corner = CGPoint(x: -971, y: -1440)
            expect(t, "coin haut-gauche → local", g.windowLocal(fromEvent: corner, on: ext),
                   CGPoint(x: 0, y: 1440))
            expect(t, "coin haut-gauche → pixel", g.pixel(fromEvent: corner, on: ext), .zero)
            // Écran non-Retina : 1 pt = 1 px. C'est ICI que le décalage ×2 se produirait
            // si l'on appliquait l'échelle de l'écran principal.
            expect(t, "centre de l'externe → pixel",
                   g.pixel(fromEvent: CGPoint(x: -971 + 1720, y: -1440 + 720), on: ext),
                   CGPoint(x: 1720, y: 720))
            expect(t, "taille de capture de l'externe", g.pixelSize(of: ext),
                   CGSize(width: 3440, height: 1440))
            // Le portable garde son échelle 2 dans la même disposition.
            expect(t, "le portable reste en ×2",
                   g.pixel(fromEvent: CGPoint(x: 10, y: 10), on: g.screens[0]),
                   CGPoint(x: 20, y: 20))
        }

        section(t, "écran contenant un point") {
            let g = realWorld
            expect(t, "point sur le portable",
                   CGPoint(x: Double(g.screen(containingEvent: CGPoint(x: 800, y: 500))?.displayID ?? 0), y: 0),
                   CGPoint(x: 1, y: 0))
            expect(t, "point sur l'externe",
                   CGPoint(x: Double(g.screen(containingEvent: CGPoint(x: 0, y: -700))?.displayID ?? 0), y: 0),
                   CGPoint(x: 3, y: 0))
            // Un point dans l'interstice doit retomber sur l'écran le plus proche,
            // jamais sur nil : perdre une marque serait pire que l'attribuer au voisin.
            expect(t, "point hors de tout écran",
                   CGPoint(x: Double(g.screen(containingEvent: CGPoint(x: -5000, y: -5000))?.displayID ?? 0), y: 0),
                   CGPoint(x: 3, y: 0))
        }

        section(t, "externe non-Retina strictement à gauche") {
            let g = externalLeft
            let ext = g.screens[1]
            // cocoaFrame x −1920..0, y 0..1080. flipHeight = 1117.
            // eventFrame.y = 1117 − 1080 = 37 : l'écran est plus court, son bord haut
            // est 37 pt SOUS celui du portable.
            expect(t, "eventFrame", g.eventFrame(of: ext).origin, CGPoint(x: -1920, y: 37))
            expect(t, "coin haut-gauche → pixel",
                   g.pixel(fromEvent: CGPoint(x: -1920, y: 37), on: ext), .zero)
            expect(t, "coin bas-droit → pixel",
                   g.pixel(fromEvent: CGPoint(x: 0, y: 1117), on: ext),
                   CGPoint(x: 1920, y: 1080))
        }

        section(t, "externe à droite, plus grand") {
            let g = externalRight
            let ext = g.screens[1]
            // y : 1117 − 1440 = −323.
            expect(t, "eventFrame", g.eventFrame(of: ext).origin, CGPoint(x: 1728, y: -323))
            expect(t, "coin haut-gauche → pixel",
                   g.pixel(fromEvent: CGPoint(x: 1728, y: -323), on: ext), .zero)
        }

        section(t, "externe Retina au-dessus — deux écrans en ×2") {
            let g = externalAbove
            let above = g.screens[1]
            // y : 1117 − 2234 = −1117.
            expect(t, "eventFrame", g.eventFrame(of: above).origin, CGPoint(x: 0, y: -1117))
            expect(t, "coin haut-gauche → pixel",
                   g.pixel(fromEvent: CGPoint(x: 0, y: -1117), on: above), .zero)
            expect(t, "100 pt vers le bas → 200 px",
                   g.pixel(fromEvent: CGPoint(x: 0, y: -1017), on: above), CGPoint(x: 0, y: 200))
        }

        section(t, "aller-retour des conversions") {
            for g in [soloRetina, realWorld, externalLeft, externalRight, externalAbove] {
                for screen in g.screens {
                    let frame = g.eventFrame(of: screen)
                    for p in [frame.origin,
                              CGPoint(x: frame.midX, y: frame.midY),
                              CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)] {
                        // event → cocoa → event doit rendre le point d'origine.
                        let back = g.eventLocation(fromCocoa: g.cocoaGlobal(fromEvent: p))
                        expect(t, "aller-retour", back, p)
                    }
                }
            }
        }

        print("")
        if t.failures == 0 {
            print("  ✓ \(t.checks) vérifications passent.")
            print("    Le refus d'écran tient sur sept cas, dont aucun n'est branché ici.\n    Les conversions tiennent sur cinq dispositions, dont trois")
            print("    absentes de cette machine.")
        } else {
            print("  ✗ \(t.failures) échec(s) sur \(t.checks) vérifications.")
            print("    Aucun code de dessin ne doit être écrit avant correction (plan § 5, lot 2).")
        }
        print("")
        return t.failures
    }
}
