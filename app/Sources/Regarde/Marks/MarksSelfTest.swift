import AppKit
import Carbon.HIToolbox
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// Autotest des marques — S20 à S23, lancé par `--marks-test`
//
// Ce que ce fichier vérifie tient en une phrase : les règles que le lot 0 a payées cher
// ne doivent pas se re-perdre en silence. Trois d'entre elles sont invisibles à l'œil —
// l'ordre réel des codes physiques `5` et `6`, la réattribution d'un numéro annulé, le
// confinement à la fenêtre cible — et se manifesteraient par un rapport subtilement faux
// plutôt que par une panne.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
enum MarksSelfTest {

    private final class Tally {
        var passed = 0
        var failed = 0
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest des marques (S20 à S23) ──\n")

        codes(t)
        numbering(t)
        rendering(t)
        anchors(t)
        arming(t)

        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    private static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            t.passed += 1
            print("  ✓ \(label)")
        } else {
            t.failed += 1
            print("  ✗ \(label) \(detail)")
        }
    }

    // MARK: - Codes de touches

    private static func codes(_ t: Tally) {
        print("Codes physiques de la palette (ADR-0021)")

        // Le piège : l'ordre des constantes Carbon n'est pas celui des chiffres.
        // Si quelqu'un « corrige » `textToFix` en 22 pour rendre la suite contiguë,
        // « texte à corriger » et « ne marche pas » s'échangent dans tous les rapports.
        check(t, "« 5 » vaut 23, et non 22",
              Intention.textToFix.keyCode == 23,
              "→ \(Intention.textToFix.keyCode)")
        check(t, "« 6 » vaut 22, et non 23",
              Intention.broken.keyCode == 22,
              "→ \(Intention.broken.keyCode)")

        for intention in Intention.allCases {
            check(t, "code \(intention.keyCode) → \(intention.label)",
                  Intention.forKeyCode(intention.keyCode) == intention)
        }

        // Six codes distincts : deux intentions sur la même touche en rendraient une
        // inatteignable, et rien ne le signalerait.
        var seen = Set<Int64>()
        for i in Intention.allCases { seen.insert(i.keyCode) }
        check(t, "les six touches sont distinctes", seen.count == 6)

        for rank in [kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9] {
            check(t, "le chiffre de code \(rank) est reconnu comme hors palette",
                  MuteDigit.rank(of: Int64(rank)) != nil
                  && Intention.forKeyCode(Int64(rank)) == nil)
        }

        // Les lettres, elles, se résolvent par caractère — règle inverse. On vérifie que
        // la table est peuplée, pas la valeur : elle DOIT changer selon la disposition.
        ToolKeyCache.shared.refresh()
        var resolved = 0
        for tool in MarkTool.allCases {
            if let code = KeyboardLayout.keyCode(for: tool.key),
               ToolKeyCache.shared.tool(forCode: code) == tool {
                resolved += 1
            }
        }
        check(t, "les quatre outils sont résolus sur la disposition courante",
              resolved == 4, "→ \(resolved)/4")

        // Le cache ne doit dépendre d'AUCUNE déclaration préalable : cet autotest ne
        // lance pas `KeyboardLayout.start(resolving:)`, et c'est précisément le cas qui
        // a révélé le couplage.
        var distinct = Set<Int64>()
        for tool in MarkTool.allCases {
            if let code = KeyboardLayout.keyCode(for: tool.key) { distinct.insert(code) }
        }
        check(t, "les quatre touches d'outil sont distinctes",
              distinct.count == 4, "→ \(distinct.sorted())")
    }

    // MARK: - Numérotation

    private static let display: CGDirectDisplayID = 1
    private static let size = CGSize(width: 1000, height: 800)

    private static func geometry() -> ScreenGeometry {
        ScreenGeometry(screens: [ScreenInfo(displayID: display,
                                            cocoaFrame: CGRect(origin: .zero, size: size),
                                            scale: 2)])
    }

    private static func numbering(_ t: Tally) {
        print("\nNumérotation (ADR-0013)")
        let store = MarkStore.shared
        let g = geometry()
        store.reset()

        store.beginStroke(at: CGPoint(x: 100, y: 100), geometry: g)
        check(t, "le numéro existe dès la pression, avant le relâchement",
              store.liveNumber == 1, "→ \(String(describing: store.liveNumber))")
        store.extendStroke(to: CGPoint(x: 300, y: 200), geometry: g)
        check(t, "le numéro ne change pas pendant le geste", store.liveNumber == 1)
        let first = store.endStroke()
        check(t, "la marque garde le numéro réservé à la pression", first?.number == 1)

        // Un tracé annulé rend son numéro : l'utilisateur ne l'a pas prononcé.
        store.beginStroke(at: CGPoint(x: 100, y: 100), geometry: g)
        check(t, "le tracé suivant réserve 2", store.liveNumber == 2)
        store.cancelStroke()
        store.beginStroke(at: CGPoint(x: 400, y: 400), geometry: g)
        check(t, "après annulation, le numéro 2 est réutilisé", store.liveNumber == 2)
        store.extendStroke(to: CGPoint(x: 500, y: 500), geometry: g)
        _ = store.endStroke()

        // Une suppression, elle, laisse un TROU : le numéro a pu être prononcé.
        store.undoLast()
        store.beginStroke(at: CGPoint(x: 600, y: 600), geometry: g)
        check(t, "après suppression, le numéro suivant est 3 et non 2",
              store.liveNumber == 3, "→ \(String(describing: store.liveNumber))")
        store.extendStroke(to: CGPoint(x: 700, y: 700), geometry: g)
        _ = store.endStroke()

        // Un geste trop court ne consomme rien non plus.
        store.tool = .arrow
        store.beginStroke(at: CGPoint(x: 800, y: 800), geometry: g)
        let reserved = store.liveNumber
        check(t, "le geste trop court avait réservé 4", reserved == 4)
        check(t, "un geste trop court ne pose aucune marque", store.endStroke() == nil)
        store.beginStroke(at: CGPoint(x: 100, y: 700), geometry: g)
        check(t, "le numéro d'un geste trop court est rendu", store.liveNumber == 4)
        store.cancelStroke()

        // L'outil survit à une publication éclair, mais pas à une nouvelle session.
        store.tool = .highlight
        store.reset(keepingTool: true)
        check(t, "l'outil survit à une publication éclair", store.tool == .highlight)
        store.reset()
        check(t, "une nouvelle session repart de la flèche", store.tool == .arrow)

        // Une nouvelle session repart de 1.
        store.reset()
        store.beginStroke(at: CGPoint(x: 100, y: 100), geometry: g)
        check(t, "une nouvelle session recommence à 1", store.liveNumber == 1)
        store.cancelStroke()
    }

    // MARK: - Modes de peinture

    private static func rendering(_ t: Tally) {
        print("\nModes de peinture (S20)")
        let cases: [(MarkShape, MarkRendering, String)] = [
            (.arrow(from: NormPoint(x: 0.1, y: 0.1), to: NormPoint(x: 0.4, y: 0.4)),
             .stroke, "la flèche se trace"),
            (.rect(NormRect(bounding: [NormPoint(x: 0.1, y: 0.1), NormPoint(x: 0.5, y: 0.5)])),
             .stroke, "le cadre se trace"),
            (.point(NormPoint(x: 0.5, y: 0.5)), .fill, "le point se remplit"),
            (.highlight(NormRect(bounding: [NormPoint(x: 0.1, y: 0.1), NormPoint(x: 0.5, y: 0.5)])),
             .wash, "le surlignage se lave"),
        ]
        for (shape, expected, label) in cases {
            check(t, label, shape.rendering == expected)
        }

        // Un surlignage tracé au trait donnerait un cadre vide, un point tracé au trait
        // un anneau : deux repères différents de ceux que l'utilisateur croit poser.
        check(t, "le surlignage et le cadre ne partagent pas le même mode",
              MarkShape.highlight(NormRect(bounding: [])).rendering
              != MarkShape.rect(NormRect(bounding: [])).rendering)

        // Les quatre outils produisent bien quatre formes distinctes.
        let a = NormPoint(x: 0.2, y: 0.2), b = NormPoint(x: 0.6, y: 0.5)
        var produced = Set<String>()
        for tool in MarkTool.allCases {
            guard let shape = MarkGeometry.shape(for: tool, from: a, to: b, in: size) else {
                check(t, "l'outil \(tool.label) produit une forme", false)
                continue
            }
            produced.insert("\(shape)".prefix(while: { $0 != "(" }).description)
        }
        check(t, "les quatre outils produisent quatre formes distinctes",
              produced.count == 4, "→ \(produced.sorted())")

        // Le point est le seul à ne rien exiger du geste : c'est sa raison d'être.
        check(t, "le point se pose sans amplitude",
              MarkGeometry.shape(for: .point, from: a, to: a, in: size) != nil)
        check(t, "la flèche refuse un geste sans amplitude",
              MarkGeometry.shape(for: .arrow, from: a, to: a, in: size) == nil)
        check(t, "le cadre refuse un geste sans amplitude",
              MarkGeometry.shape(for: .rect, from: a, to: a, in: size) == nil)
    }

    // MARK: - Ancrage des badges

    private static func anchors(_ t: Tally) {
        print("\nAncrage des numéros (S21)")

        // La règle qui compte : le badge ne masque jamais ce que la marque désigne.
        let tail = NormPoint(x: 0.5, y: 0.5), head = NormPoint(x: 0.8, y: 0.5)
        let arrow = MarkGeometry.badgeAnchor(for: .arrow(from: tail, to: head), in: size)
        let anchor = arrow.point
        let headLocal = head.local(in: size), tailLocal = tail.local(in: size)
        check(t, "le badge d'une flèche se range du côté de la queue",
              hypot(anchor.x - tailLocal.x, anchor.y - tailLocal.y)
              < hypot(anchor.x - headLocal.x, anchor.y - headLocal.y))
        check(t, "le badge est au-delà de la queue, pas dessus",
              anchor.x < tailLocal.x, "→ x=\(anchor.x) vs \(tailLocal.x)")

        let r = NormRect(bounding: [NormPoint(x: 0.2, y: 0.2), NormPoint(x: 0.6, y: 0.6)])
        let rectAnchor = MarkGeometry.badgeAnchor(for: .rect(r), in: size).point
        let local = r.local(in: size)
        check(t, "le badge d'un cadre est au-dessus du bord supérieur",
              rectAnchor.y > local.maxY)
        check(t, "le badge d'un cadre est aligné sur le bord gauche",
              abs(rectAnchor.x - local.minX) < 0.001)
        check(t, "le badge d'un cadre s'étend vers la droite",
              MarkGeometry.badgeAnchor(for: .rect(r), in: size).anchorX == 0)

        // Une gélule longue ne doit jamais recouvrir ce que la flèche désigne : elle
        // s'étend du côté opposé à la pointe.
        // `anchorX == 1` accroche la gélule par son bord DROIT, donc elle s'étend vers
        // la gauche — l'inverse de l'intuition, et l'inverse de ce que ce test affirmait
        // avant d'être corrigé.
        check(t, "une flèche vers la droite pose sa gélule vers la gauche",
              arrow.anchorX == 1)
        check(t, "une flèche vers la gauche pose sa gélule vers la droite",
              MarkGeometry.badgeAnchor(for: .arrow(from: head, to: tail), in: size).anchorX == 0)

        // Le badge du tracé en cours doit être là AVANT le relâchement : c'est pendant
        // le geste que l'utilisateur prononce le numéro.
        let store = MarkStore.shared
        let g = geometry()
        store.reset()
        store.beginStroke(at: CGPoint(x: 200, y: 200), geometry: g)
        store.extendStroke(to: CGPoint(x: 400, y: 300), geometry: g)
        let live = store.badges(for: display, size: size)
        check(t, "le tracé en cours porte déjà son badge",
              live.count == 1 && live[0].number == 1, "→ \(live.count) badge(s)")
        _ = store.endStroke()

        store.beginStroke(at: CGPoint(x: 500, y: 500), geometry: g)
        store.extendStroke(to: CGPoint(x: 600, y: 600), geometry: g)
        check(t, "le badge posé et le badge en cours coexistent",
              store.badges(for: display, size: size).count == 2)
        _ = store.endStroke()

        check(t, "aucun badge ne fuit vers un autre écran",
              store.badges(for: 999, size: size).isEmpty)

        // L'intention rejoint le badge de la marque qualifiée.
        check(t, "une intention s'applique à la dernière marque",
              { if case .applied(let n, let i) = store.apply(.slow) {
                    return n == 2 && i == .slow
                }; return false }())
        let withIntention = store.badges(for: display, size: size)
        check(t, "le badge affiche l'intention",
              withIntention.last?.intention == Intention.slow.label,
              "→ \(String(describing: withIntention.last?.intention))")
        check(t, "les autres badges restent nus",
              withIntention.first?.intention == nil)

        store.reset()
        check(t, "une intention sans marque ne s'applique nulle part",
              { if case .noMark = store.apply(.error) { return true }; return false }())
    }

    // MARK: - Armement et fenêtre cible

    private static func arming(_ t: Tally) {
        print("\nFenêtre cible et échappement (S22)")
        let required: CGEventFlags = [.maskAlternate, .maskCommand]
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        let inside = CGPoint(x: 200, y: 200)
        let outside = CGPoint(x: 900, y: 900)

        check(t, "⌥⌘ dans la cible arme",
              OptionGate.isArmed(flags: required, required: required,
                                 location: inside, target: target))

        // Le cas qui justifie S22 : cliquer dans l'éditeur pendant une session ne doit
        // ni poser de marque, ni voler le clic à l'IDE.
        check(t, "⌥⌘ hors de la cible n'arme pas",
              !OptionGate.isArmed(flags: required, required: required,
                                  location: outside, target: target))

        check(t, "⌥⌘⇧ hors de la cible arme quand même",
              OptionGate.isArmed(flags: [.maskAlternate, .maskCommand, .maskShift],
                                 required: required, location: outside, target: target))

        check(t, "⌥ seul n'arme pas, même dans la cible",
              !OptionGate.isArmed(flags: [.maskAlternate], required: required,
                                  location: inside, target: target))
        check(t, "⌃⌥⌘ arme : un modificateur en trop ne désarme pas",
              OptionGate.isArmed(flags: [.maskAlternate, .maskCommand, .maskControl],
                                 required: required, location: inside, target: target))
        check(t, "une cible infinie arme partout",
              OptionGate.isArmed(flags: required, required: required,
                                 location: outside, target: .infinite))

        // Le bord : viser au pixel près est un geste que personne ne réussit, mais la
        // tolérance ne doit pas déborder au point d'attraper la fenêtre d'à côté.
        check(t, "le bord exact de la cible arme",
              OptionGate.isArmed(flags: required, required: required,
                                 location: CGPoint(x: 100, y: 100), target: target))
        check(t, "un point nettement dehors n'arme pas",
              !OptionGate.isArmed(flags: required, required: required,
                                  location: CGPoint(x: 520, y: 200), target: target))

        // Les TOUCHES ne suivent pas le curseur, elles suivent l'application active.
        //
        // La règle inverse a été mesurée fausse : une flèche tracée vers le bord laisse
        // le pointeur hors de la fenêtre, et l'intention frappée juste après tombait
        // dans le vide — deux sur quatre perdues sur un scénario de quatre marques.
        let gate = OptionGate.shared
        let savedMode = gate.currentMode

        gate.currentMode = .active
        gate.setTargetFrontmost(true)
        check(t, "⌥⌘ + touche répond quand la cible est l'application active",
              gate.acceptsControlKeys(flags: required))

        // LA règle qui protège l'application testée. Une version antérieure conditionnait
        // les touches à « une session est ouverte » au lieu du modificateur, ce qui volait
        // ⌘Z nu en permanence — le raccourci le plus utilisé de macOS, pris par un outil
        // censé ne rien casser.
        check(t, "⌘ seul ne nous revient JAMAIS",
              !gate.acceptsControlKeys(flags: [.maskCommand]))
        check(t, "une frappe nue ne nous revient jamais",
              !gate.acceptsControlKeys(flags: []))
        check(t, "⌥ seul ne nous revient jamais",
              !gate.acceptsControlKeys(flags: [.maskAlternate]))

        gate.setTargetFrontmost(false)
        check(t, "⌥⌘ ne répond pas quand l'utilisateur est passé ailleurs",
              !gate.acceptsControlKeys(flags: required))

        gate.setTargetFrontmost(true)
        gate.currentMode = .passthrough
        check(t, "porte fermée, aucune touche ne nous revient",
              !gate.acceptsControlKeys(flags: required))

        gate.currentMode = savedMode
        gate.setTargetFrontmost(false)
    }
}
