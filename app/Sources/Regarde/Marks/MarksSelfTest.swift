import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CoreMedia
import Foundation

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
        noteTexte(t)

        codes(t)
        numbering(t)
        rendering(t)
        anchors(t)
        arming(t)
        horloge(t)

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
        check(t, "TOUS les outils sont résolus sur la disposition courante",
              resolved == MarkTool.allCases.count, "→ \(resolved)/\(MarkTool.allCases.count)")

        // Le cache ne doit dépendre d'AUCUNE déclaration préalable : cet autotest ne
        // lance pas `KeyboardLayout.start(resolving:)`, et c'est précisément le cas qui
        // a révélé le couplage.
        var distinct = Set<Int64>()
        for tool in MarkTool.allCases {
            if let code = KeyboardLayout.keyCode(for: tool.key) { distinct.insert(code) }
        }
        check(t, "toutes les touches d'outil sont distinctes",
              distinct.count == MarkTool.allCases.count, "→ \(distinct.sorted())")
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

        // Une suppression rend son numéro, exactement comme une annulation.
        //
        // Échap et ⌥⌘Z font la même chose du point de vue de l'utilisateur — annuler une
        // marque qu'on vient de faire — et laisser un trou dans un cas mais pas dans
        // l'autre était une incohérence. Signalé à l'usage.
        let removed = store.undoLast()
        check(t, "l'annulation retire bien la dernière marque", removed?.number == 2)
        store.beginStroke(at: CGPoint(x: 600, y: 600), geometry: g)
        check(t, "après suppression, le numéro supprimé est repris",
              store.liveNumber == 2, "→ \(String(describing: store.liveNumber))")
        store.extendStroke(to: CGPoint(x: 700, y: 700), geometry: g)
        _ = store.endStroke()

        // La numérotation reste contiguë : c'est tout l'objet du changement.
        check(t, "les numéros se suivent sans trou",
              store.marks.map(\.number) == [1, 2],
              "→ \(store.marks.map(\.number))")

        // Mais deux marques différentes ont porté le 2 : leurs identités diffèrent, et
        // c'est par elles que la gravure les distingue.
        check(t, "la marque reprise a sa propre identité",
              store.marks.last?.id != removed?.id)

        // Un geste trop court ne consomme rien non plus.
        store.tool = .arrow
        store.beginStroke(at: CGPoint(x: 800, y: 800), geometry: g)
        let reserved = store.liveNumber
        check(t, "le geste trop court avait réservé 3", reserved == 3)
        check(t, "un geste trop court ne pose aucune marque", store.endStroke() == nil)
        store.beginStroke(at: CGPoint(x: 100, y: 700), geometry: g)
        check(t, "le numéro d'un geste trop court est rendu", store.liveNumber == 3)
        store.cancelStroke()

        // Un geste qui sort de l'écran reste dans le cadre de la marque.
        //
        // Relevé dans un journal réel : `bbox (0.679, -0.085) …`. Le calque clippait bien
        // à l'affichage, mais la géométrie sortait de [0, 1] et le recadrage visait une
        // zone en partie hors de l'image.
        store.reset()
        store.beginStroke(at: CGPoint(x: 500, y: 400), geometry: g)
        store.extendStroke(to: CGPoint(x: -3000, y: 5000), geometry: g)
        if let mark = { () -> Mark? in
            store.extendStroke(to: CGPoint(x: -3000, y: 5000), geometry: g)
            return store.endStroke()
        }() {
            let b = mark.shape.boundingBox
            check(t, "un geste hors écran reste dans [0, 1]",
                  b.x >= 0 && b.y >= 0 && b.x + b.w <= 1.001 && b.y + b.h <= 1.001,
                  "→ bbox (\(b.x), \(b.y)) \(b.w)×\(b.h)")
        } else {
            check(t, "un geste hors écran produit tout de même une marque", false)
        }
        store.reset()

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

        // Chaque outil produit une forme distincte — comparé à `allCases`,
        // jamais à un nombre écrit en dur : le cinquième outil (S70) a fait
        // rougir trois tests qui comptaient jusqu'à quatre.
        let a = NormPoint(x: 0.2, y: 0.2), b = NormPoint(x: 0.6, y: 0.5)
        var produced = Set<String>()
        for tool in MarkTool.allCases {
            guard let shape = MarkGeometry.shape(for: tool, from: a, to: b, in: size) else {
                check(t, "l'outil \(tool.label) produit une forme", false)
                continue
            }
            produced.insert("\(shape)".prefix(while: { $0 != "(" }).description)
        }
        check(t, "chaque outil produit une forme distincte",
              produced.count == MarkTool.allCases.count, "→ \(produced.sorted())")

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

        // ── La fenêtre cible est faite de ses morceaux accolés ─────────────────
        //
        // Plusieurs applications découpent leur fenêtre : Warp expose une barre
        // d'onglets de 3440×44 puis la vraie fenêtre de 3440×1440 juste en dessous,
        // Chrome en plein écran en expose trois. Retenir le premier morceau donnait une
        // cible de 44 pixels de haut, et tracer dans le terminal ne faisait rien.
        let warpBar = CGRect(x: -971, y: -1484, width: 3440, height: 44)
        let warpBody = CGRect(x: -971, y: -1440, width: 3440, height: 1440)
        check(t, "une barre accolée est agrégée à sa fenêtre",
              TargetWindow.merge([warpBar, warpBody])
              == CGRect(x: -971, y: -1484, width: 3440, height: 1484),
              "→ \(String(describing: TargetWindow.merge([warpBar, warpBody])))")

        // Trois barres en cascade, comme Chrome en plein écran : chacune ne touche que
        // sa voisine, d'où l'agrégation répétée.
        let chrome = [CGRect(x: 0, y: 0, width: 1728, height: 33),
                      CGRect(x: 0, y: 33, width: 1728, height: 41),
                      CGRect(x: 0, y: 74, width: 1728, height: 47),
                      CGRect(x: 0, y: 121, width: 1728, height: 996)]
        check(t, "trois barres en cascade rejoignent la fenêtre",
              TargetWindow.merge(chrome) == CGRect(x: 0, y: 0, width: 1728, height: 1117))

        // Une fenêtre POSÉE AILLEURS n'est pas absorbée : « la fenêtre du dessus » garde
        // son sens quand une application en a plusieurs.
        let front = CGRect(x: 100, y: 100, width: 500, height: 400)
        let elsewhere = CGRect(x: 900, y: 700, width: 500, height: 400)
        check(t, "une fenêtre distante n'est pas absorbée",
              TargetWindow.merge([front, elsewhere]) == front)

        // ── L'ORDRE de la liste ne doit rien changer ────────────────────────
        //
        // C'est la cause du défaut intermittent du 23 août. Le journal portait deux
        // sessions sur la même application, l'une avec une cible de 3440×1440 et
        // l'autre de 3440×88, sans que rien n'ait changé entre les deux :
        // l'agrégation semait sur le PREMIER morceau, et `CGWindowListCopyWindowInfo`
        // ne garantit aucun ordre.
        let attendu = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        var ordresFautifs = 0
        for depart in 0..<chrome.count {
            let tourne = Array(chrome[depart...] + chrome[..<depart])
            if TargetWindow.merge(tourne) != attendu { ordresFautifs += 1 }
        }
        check(t, "les quatre ordres de liste donnent la même cible",
              ordresFautifs == 0,
              ordresFautifs == 0 ? "" : "\(ordresFautifs) ordre(s) donnent autre chose")

        // Et l'inverse strict, qui est l'ordre le plus défavorable : les barres
        // d'abord, le contenu en dernier.
        check(t, "barres en tête, contenu en queue — même résultat",
              TargetWindow.merge(chrome.reversed()) == attendu,
              "→ \(String(describing: TargetWindow.merge(chrome.reversed())))")

        // ── LE CAS RÉEL DU 23 AOÛT, reconstitué ────────────────────────────
        //
        // La liste ne contenait que les deux barres du milieu : celle de 33 points
        // est écartée par la garde de taille, et le contenu était absent — ce qui
        // arrive pendant une transition plein écran. 41 + 47 = 88, à partir de
        // y = 33 : exactement le cadre relevé.
        //
        // Aucun ensemencement ne répare cela, et c'est le point : le contenu n'est
        // pas là. La seule conduite juste est de REFUSER la cible.
        let barresSeules = [CGRect(x: 0, y: 33, width: 3440, height: 41),
                            CGRect(x: 0, y: 74, width: 3440, height: 47)]
        let cadreFautif = TargetWindow.merge(barresSeules)
        check(t, "deux barres seules donnent bien le cadre observé",
              cadreFautif == CGRect(x: 0, y: 33, width: 3440, height: 88),
              "→ \(String(describing: cadreFautif))")
        check(t, "et ce cadre est reconnu comme une barre, donc refusable",
              cadreFautif.map {
                  TargetWindow.ressembleAUneBarre($0, ecran: CGRect(x: 0, y: 0, width: 3440, height: 1440))
              } == true)

        // ── Une cible qui ressemble à une barre se reconnaît ────────────────
        //
        // Le cadre relevé dans le journal du 23 août, face à l'écran qui le portait.
        let ecran3 = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        check(t, "une bande pleine largeur de 88 points est reconnue comme barre",
              TargetWindow.ressembleAUneBarre(CGRect(x: 0, y: 33, width: 3440, height: 88),
                                              ecran: ecran3))
        check(t, "la fenêtre entière n'est PAS prise pour une barre",
              !TargetWindow.ressembleAUneBarre(CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                               ecran: ecran3))
        // Une petite fenêtre — une boîte de dialogue — reste annotable : ce qui
        // trahit la barre est d'être pleine largeur ET courte, pas d'être petite.
        check(t, "une boîte de dialogue n'est pas prise pour une barre",
              !TargetWindow.ressembleAUneBarre(CGRect(x: 900, y: 500, width: 600, height: 200),
                                               ecran: ecran3))

        // Un seul morceau reste lui-même, et zéro morceau ne donne pas de cible.
        check(t, "une fenêtre unique est rendue telle quelle",
              TargetWindow.merge([front]) == front)
        check(t, "aucun morceau ne donne aucune cible", TargetWindow.merge([]) == nil)

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

    // MARK: - Horloge de session (S30)

    /// Les deux horloges, et le recalage d'origine.
    ///
    /// Rien ici n'exige d'écran, de permission ni de session : c'est le point de
    /// cette section. Le § 3.1 a quatre corrections, et trois d'entre elles se
    /// vérifient sans quitter la ligne de commande.
    private static func horloge(_ t: Tally) {
        print("\n· Horloge de session")
        let clock = SessionClock.shared

        // ── Le recalage d'origine ────────────────────────────────────────────
        //
        // On ne peut pas avancer l'horloge de la machine dans un autotest. Ce qu'on
        // peut faire, et qui teste la même chose, c'est laisser le temps s'écouler
        // puis constater que `rearm()` ramène `now()` près de zéro. Sans recalage,
        // une session ouverte six heures après le lancement daterait ses marques de
        // six heures, et `assetTime()` les clamperait toutes hors bornes.
        let avant = clock.now().seconds
        clock.rearm()
        let apres = clock.now().seconds
        check(t, "rearm() ramène l'origine à l'instant courant",
              apres < 0.050 && apres >= 0,
              String(format: "avant %.3fs → après %.3fs", avant, apres))
        check(t, "l'origine avançait bien avant le recalage",
              avant >= apres,
              String(format: "%.3fs ≥ %.3fs", avant, apres))

        // ── Les deux horloges avancent ensemble hors veille ──────────────────
        //
        // `mach_absolute_time` s'arrête pendant la veille, `mach_continuous_time`
        // non. Hors veille, elles doivent donner la MÊME durée : c'est ce qui rend
        // l'écart interprétable comme « il y a eu veille » plutôt que comme du bruit.
        // Un autotest ne peut pas endormir la machine ; il peut établir qu'au repos
        // les deux ne divergent pas.
        clock.rearm()
        let debut = Date()
        while Date().timeIntervalSince(debut) < 0.25 { }        // attente active, 250 ms
        let maitresse = clock.now().seconds
        let murale = clock.wallSeconds()
        check(t, "durée d'horloge et durée murale s'accordent hors veille",
              abs(maitresse - murale) < 0.005,
              String(format: "%.4fs contre %.4fs, écart %.1f ms",
                     maitresse, murale, abs(maitresse - murale) * 1000))
        check(t, "les deux ont bien mesuré l'attente",
              maitresse > 0.20 && maitresse < 0.50,
              String(format: "%.3fs", maitresse))

        // ── L'aller-retour SessionTime ↔ PTS ─────────────────────────────────
        //
        // `pts(for:)` est l'inverse de `now()`, et S32 s'en sert pour demander à
        // l'asset la frame d'un `SessionTime`. Une inversion ici produirait des
        // images décalées du double de l'offset, dans le bon sens la moitié du temps.
        for secondes in [0.0, 0.5, 12.75, 600.0] {
            let st = SessionTime(seconds: secondes)
            let retour = SessionTime(CMTimeSubtract(clock.pts(for: st),
                                                    clock.pts(for: SessionTime(seconds: 0))))
            check(t, String(format: "SessionTime %.2fs → PTS → SessionTime", secondes),
                  abs(retour.seconds - secondes) < 0.001,
                  String(format: "%.6fs", retour.seconds))
        }

        // ── Codable, au tick près ────────────────────────────────────────────
        //
        // Encoder en secondes flottantes perdrait la précision que l'échelle de
        // 90 000 existe pour garantir. Le manifeste du lot 4 portera ces valeurs.
        for secondes in [0.0, 1.0 / 3.0, 42.123456, 3600.0] {
            let st = SessionTime(seconds: secondes)
            guard let data = try? JSONEncoder().encode(st),
                  let relu = try? JSONDecoder().decode(SessionTime.self, from: data) else {
                check(t, "SessionTime encodé puis relu", false, "encodage impossible")
                continue
            }
            check(t, String(format: "SessionTime %.6fs survit à l'encodage", secondes),
                  relu.raw.value == st.raw.value && relu.raw.timescale == st.raw.timescale,
                  "\(relu.raw.value)/\(relu.raw.timescale)")
        }

        // ── L'horodatage matériel, et son repli ──────────────────────────────
        //
        // Un timestamp nul est le cas des événements synthétiques : Karabiner,
        // BetterTouchTool, pilotes Logitech ou Razer, Universal Control, partage
        // d'écran. Sans le repli, la marque serait perdue en silence chez tout
        // utilisateur de ces outils — c'est le critère C12.
        let avantReplis = clock.fallbackCount
        let nul = clock.stamp(hostTicks: 0)
        check(t, "un timestamp nul bascule en repli",
              nul.origin == .fallbackNow && clock.fallbackCount == avantReplis + 1)
        check(t, "et rend malgré tout un instant utilisable",
              nul.time.seconds >= 0)

        let futur = clock.stamp(hostTicks: SessionClock.hostTicksNow() &+ 10_000_000_000)
        check(t, "un timestamp du futur bascule en repli",
              futur.origin == .fallbackNow)

        let bon = clock.stamp(hostTicks: SessionClock.hostTicksNow())
        check(t, "un timestamp matériel valide est accepté",
              bon.origin == .hardware,
              String(format: "%.4fs", bon.time.seconds))

        // ── Le mode éclair, sans session ─────────────────────────────────────
        //
        // C'est le cas majoritaire, et celui qu'un développement centré session ne
        // traverse jamais. Hors session l'origine reste celle du dernier recalage :
        // une marque posée maintenant tombe donc APRÈS elle, dans la fenêtre de
        // validité, et n'a aucune raison de partir en repli. Si elle y partait, tout
        // relevé du banc C11 serait refusé pour `fallbackCount` bougé.
        let replisAvantEclair = clock.fallbackCount
        let eclair = clock.stamp(hostTicks: SessionClock.hostTicksNow())
        check(t, "une marque éclair, sans session, porte une origine matérielle",
              eclair.origin == .hardware)
        check(t, "et ne fait pas bouger fallbackCount",
              clock.fallbackCount == replisAvantEclair,
              "\(clock.fallbackCount)")
    }

    // MARK: - La note texte (S70)

    private static func noteTexte(_ t: Tally) {
        print("· La note texte — l'outil, la forme, le chemin")

        // LE TEST QUI MANQUAIT : chaque outil doit avoir sa touche résolue.
        // Sans lui, ajouter `.text` laissait ⌥⌘T muet, sans erreur ni trace —
        // et c'est arrivé.
        ToolKeyCache.shared.refresh()
        let muets = MarkTool.allCases.filter { ToolKeyCache.shared.code(pour: $0) < 0 }
        check(t, "TOUS les outils ont leur touche résolue — aucun n'est muet",
              muets.isEmpty, muets.isEmpty ? "" : "muets : \(muets.map(\.label))")
        let codes = MarkTool.allCases.map { ToolKeyCache.shared.code(pour: $0) }
        check(t, "…et deux outils ne partagent jamais la même touche",
              Set(codes).count == codes.count)
        check(t, "le code résolu rend bien son outil",
              MarkTool.allCases.allSatisfy {
                  ToolKeyCache.shared.tool(forCode: ToolKeyCache.shared.code(pour: $0)) == $0
              })

        // La forme naît VIDE : le texte arrive à la frappe.
        let ancre = NormPoint(x: 0.4, y: 0.6)
        let forme = MarkGeometry.shape(for: .text, from: ancre, to: ancre,
                                       in: CGSize(width: 1000, height: 800))
        if case .text(let p, let texte)? = forme {
            check(t, "l'outil texte pose une ancre et un texte VIDE", p == ancre && texte.isEmpty)
        } else {
            check(t, "l'outil texte pose une ancre et un texte vide", false, "\(String(describing: forme))")
        }

        // Le chemin : cartouche + glyphes, une seule fonction pour le calque
        // ET la gravure.
        let taille = CGSize(width: 1000, height: 800)
        let vide = MarkGeometry.path(for: .text(ancre, ""), in: taille, lineWidth: 3)
        let court = MarkGeometry.path(for: .text(ancre, "ok"), in: taille, lineWidth: 3)
        let long = MarkGeometry.path(for: .text(ancre, "une note beaucoup plus longue"), in: taille, lineWidth: 3)
        check(t, "une note vide a quand même sa cartouche", !vide.isEmpty)
        check(t, "le texte ÉLARGIT la cartouche — les glyphes sont dans le chemin",
              long.boundingBox.width > court.boundingBox.width
                && court.boundingBox.width >= vide.boundingBox.width)
        check(t, "la cartouche part de l'ancre et s'étend vers le haut-droite",
              long.boundingBox.minX >= ancre.local(in: taille).x - 0.5
                && long.boundingBox.minY >= ancre.local(in: taille).y - 0.5)
        let multi = MarkGeometry.path(for: .text(ancre, "deux\nlignes"), in: taille, lineWidth: 3)
        check(t, "deux lignes donnent une cartouche plus HAUTE",
              multi.boundingBox.height > court.boundingBox.height)
        check(t, "la taille suit lineWidth — lisible sur un recadrage comme en pleine résolution",
              MarkGeometry.path(for: .text(ancre, "ok"), in: taille, lineWidth: 12)
                .boundingBox.width > court.boundingBox.width)

        // Le cycle : compléter, vider, abandonner.
        let store = MarkStore.shared
        store.reset()
        store.tool = .text
        store.beginStroke(at: CGPoint(x: 100, y: 100), geometry: geometrieDEssai())
        store.extendStroke(to: CGPoint(x: 100, y: 100), geometry: geometrieDEssai())
        let posee = store.endStroke()
        check(t, "le relâchement pose l'ancre, la marque existe déjà", posee != nil)
        let complete = store.completerTexte("  il manque un état vide  ")
        check(t, "compléter donne son texte à la marque, espaces rognés",
              { if case .text(_, let x)? = complete?.shape { return x == "il manque un état vide" }
                return false }())
        store.beginStroke(at: CGPoint(x: 200, y: 200), geometry: geometrieDEssai())
        store.extendStroke(to: CGPoint(x: 200, y: 200), geometry: geometrieDEssai())
        _ = store.endStroke()
        let numeroAvant = store.marks.count
        check(t, "une note VIDE n'est pas posée, et son numéro repart au pot",
              store.completerTexte("   ") == nil && store.marks.count == numeroAvant - 1)
        store.beginStroke(at: CGPoint(x: 300, y: 300), geometry: geometrieDEssai())
        store.extendStroke(to: CGPoint(x: 300, y: 300), geometry: geometrieDEssai())
        _ = store.endStroke()
        check(t, "Échap abandonne la note et rend son numéro",
              store.abandonnerNote() && store.marks.count == 1)
        // Une flèche par-dessus : abandonner ne doit alors RIEN retirer.
        store.tool = .arrow
        store.beginStroke(at: CGPoint(x: 400, y: 400), geometry: geometrieDEssai())
        store.extendStroke(to: CGPoint(x: 500, y: 500), geometry: geometrieDEssai())
        _ = store.endStroke()
        check(t, "abandonner quand la dernière marque n'est PAS une note ne fait rien",
              !store.abandonnerNote() && store.marks.count == 2)
        store.reset()
        store.tool = .arrow
    }

    /// Un écran d'essai, pour poser des marques sans dépendre de la machine.
    private static func geometrieDEssai() -> ScreenGeometry {
        ScreenGeometry(screens: [ScreenInfo(displayID: 1,
                                            cocoaFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                                            scale: 2)])
    }
}
