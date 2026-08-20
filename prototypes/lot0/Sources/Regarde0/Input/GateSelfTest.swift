import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Auto-test de la porte a verrou — `Regarde0 --selftest`
//
// La logique de `OptionGate.decide` est pure : elle ne depend que du type d'evenement,
// des modificateurs et de la position. Elle est donc verifiable sans permission, sans
// ecran et sans les mains — ce qui compte, parce que les defauts qu'elle peut porter
// sont ceux qui rendent l'application testee inutilisable, et qu'on ne veut pas les
// decouvrir en salle de recette.
//
// Ce n'est PAS un substitut aux douze criteres : ceux-ci mesurent le systeme reel,
// avec le WindowServer, le vrai tap et les vraies applications. C'est un filet qui
// attrape les regressions de raisonnement avant qu'elles ne coutent une manipulation.
//
// La sequence C6b existe parce que la premiere version du prototype echouait dessus.
// ─────────────────────────────────────────────────────────────────────────────

enum GateSelfTest {

    private struct Step {
        let label: String
        let type: CGEventType
        let flags: CGEventFlags
        let expected: Expectation
    }

    private enum Expectation {
        case pass       // va a l'application testee
        case capture    // devient de l'encre
        case swallow    // consomme sans produire d'encre
    }

    private static let armed: CGEventFlags = [.maskAlternate, .maskCommand]
    private static let bare: CGEventFlags = []
    private static let point = CGPoint(x: 400, y: 300)

    private static func matches(_ decision: GateDecision, _ expected: Expectation) -> Bool {
        switch (decision, expected) {
        case (.pass, .pass), (.swallow, .swallow): true
        case (.capture, .capture): true
        default: false
        }
    }

    private static func name(_ d: GateDecision) -> String {
        switch d {
        case .pass: "pass"
        case .swallow: "swallow"
        case .capture(let k): "capture(\(k))"
        }
    }

    /// Deroule un scenario sur une porte neuve et rend le nombre d'echecs.
    private static func run(_ title: String, _ criterion: String,
                            _ steps: [Step],
                            interlude: [Int: (OptionGate) -> Void] = [:]) -> Int {
        // Une porte neuve par scenario : l'etat du verrou ne doit pas fuir de l'un a l'autre.
        let gate = OptionGate()
        var failures = 0
        var lines: [String] = []

        for (i, step) in steps.enumerated() {
            interlude[i]?(gate)
            let decision = gate.decide(type: step.type, flags: step.flags, location: point)
            let ok = matches(decision, step.expected)
            if !ok { failures += 1 }
            lines.append(String(format: "    %@ %-38@ → %@ (attendu %@)",
                                ok ? "✓" : "✗",
                                step.label as NSString,
                                name(decision),
                                "\(step.expected)"))
        }

        let verdict = failures == 0 ? "PASS" : "ÉCHEC"
        print("  [\(criterion)] \(title) — \(verdict)")
        if failures > 0 { lines.forEach { print($0) } }
        return failures
    }

    static func runAll() -> Int {
        print("\nAuto-test de la porte a verrou")
        print("──────────────────────────────")
        var failures = 0

        // C1 — sans modificateur, l'application testee recoit tout.
        failures += run("clic ordinaire", "C1", [
            Step(label: "mouseMoved", type: .mouseMoved, flags: bare, expected: .pass),
            Step(label: "mouseDown", type: .leftMouseDown, flags: bare, expected: .pass),
            Step(label: "mouseDragged", type: .leftMouseDragged, flags: bare, expected: .pass),
            Step(label: "mouseUp", type: .leftMouseUp, flags: bare, expected: .pass),
        ])

        // C2 — sous ⌥⌘, rien n'atteint l'application testee.
        failures += run("tracé complet sous ⌥⌘", "C2", [
            Step(label: "mouseMoved armé", type: .mouseMoved, flags: armed, expected: .capture),
            Step(label: "mouseDown armé", type: .leftMouseDown, flags: armed, expected: .capture),
            Step(label: "mouseDragged", type: .leftMouseDragged, flags: armed, expected: .capture),
            Step(label: "mouseUp", type: .leftMouseUp, flags: armed, expected: .capture),
        ])

        // C6 — le modificateur est relache EN PLEIN TRACE. Le verrou doit tenir
        // jusqu'au mouseUp, sinon l'application recoit un mouseUp sans mouseDown.
        failures += run("⌥⌘ relâché pendant le tracé", "C6", [
            Step(label: "mouseDown armé", type: .leftMouseDown, flags: armed, expected: .capture),
            Step(label: "mouseDragged armé", type: .leftMouseDragged, flags: armed, expected: .capture),
            Step(label: "mouseDragged SANS modificateur", type: .leftMouseDragged, flags: bare, expected: .capture),
            Step(label: "mouseUp SANS modificateur", type: .leftMouseUp, flags: bare, expected: .capture),
        ])

        // C6 symetrique — le clic a commence DANS l'application. Presser ⌥⌘ ensuite ne
        // doit pas lui voler la fin de son geste.
        failures += run("⌥⌘ pressé après un clic dans l'app", "C6", [
            Step(label: "mouseDown SANS modificateur", type: .leftMouseDown, flags: bare, expected: .pass),
            Step(label: "mouseDragged armé", type: .leftMouseDragged, flags: armed, expected: .pass),
            Step(label: "mouseUp armé", type: .leftMouseUp, flags: armed, expected: .pass),
            Step(label: "mouseMoved armé, clic fini", type: .mouseMoved, flags: armed, expected: .capture),
        ])

        // C6b — Échap pendant le tracé, bouton toujours enfonce. Ni les drags ni le
        // mouseUp ne doivent partir : l'application n'a jamais vu le mouseDown.
        failures += run("Échap en plein tracé", "C6b", [
            Step(label: "mouseDown armé", type: .leftMouseDown, flags: armed, expected: .capture),
            Step(label: "mouseDragged", type: .leftMouseDragged, flags: armed, expected: .capture),
            Step(label: "mouseDragged après Échap", type: .leftMouseDragged, flags: armed, expected: .swallow),
            Step(label: "mouseUp après Échap", type: .leftMouseUp, flags: armed, expected: .swallow),
            Step(label: "mouseDown suivant", type: .leftMouseDown, flags: armed, expected: .capture),
        ], interlude: [2: { $0.cancelStroke() }])

        // Meme invariant par le chemin du desarmement du tap — le scenario NOMINAL de T0.8.
        failures += run("tap désarmé en plein tracé", "C6b", [
            Step(label: "mouseDown armé", type: .leftMouseDown, flags: armed, expected: .capture),
            Step(label: "mouseDragged", type: .leftMouseDragged, flags: armed, expected: .capture),
            Step(label: "mouseDragged après reset", type: .leftMouseDragged, flags: armed, expected: .swallow),
            Step(label: "mouseUp après reset", type: .leftMouseUp, flags: armed, expected: .swallow),
        ], interlude: [2: { $0.requestReset() }])

        // Un reset HORS tracé ne doit rien avaler : le clic suivant est normal.
        failures += run("reset hors tracé", "—", [
            Step(label: "mouseMoved", type: .mouseMoved, flags: bare, expected: .pass),
            Step(label: "mouseDown après reset", type: .leftMouseDown, flags: bare, expected: .pass),
            Step(label: "mouseUp", type: .leftMouseUp, flags: bare, expected: .pass),
        ], interlude: [1: { $0.requestReset() }])

        // En passthrough, tout passe sans condition — un doute sur l'etat du systeme se
        // resout toujours en faveur de l'application testee.
        failures += run("mode passthrough", "—", [
            Step(label: "mouseDown armé", type: .leftMouseDown, flags: armed, expected: .pass),
            Step(label: "mouseDragged armé", type: .leftMouseDragged, flags: armed, expected: .pass),
            Step(label: "mouseUp armé", type: .leftMouseUp, flags: armed, expected: .pass),
        ], interlude: [0: { $0.currentMode = .passthrough }])

        // Un modificateur partiel n'arme pas : ⌥ seule est un geste legitime dans la
        // plupart des applications testees (ADR-0006).
        failures += run("⌥ seule n'arme pas", "—", [
            Step(label: "mouseDown ⌥ seule", type: .leftMouseDown, flags: [.maskAlternate], expected: .pass),
            Step(label: "mouseUp ⌥ seule", type: .leftMouseUp, flags: [.maskAlternate], expected: .pass),
            Step(label: "mouseDown ⌘ seule", type: .leftMouseDown, flags: [.maskCommand], expected: .pass),
            Step(label: "mouseUp ⌘ seule", type: .leftMouseUp, flags: [.maskCommand], expected: .pass),
        ])

        // Un surensemble arme : ⌥⌘⇧ est l'echappement prevu au § 6.3.
        failures += run("⌥⌘⇧ arme aussi", "—", [
            Step(label: "mouseDown ⌥⌘⇧", type: .leftMouseDown,
                 flags: [.maskAlternate, .maskCommand, .maskShift], expected: .capture),
            Step(label: "mouseUp ⌥⌘⇧", type: .leftMouseUp,
                 flags: [.maskAlternate, .maskCommand, .maskShift], expected: .capture),
        ])

        // La disposition du clavier ne se teste pas par des sequences : elle depend du
        // systeme. On l'AFFICHE, parce que c'est la premiere chose a regarder quand un
        // raccourci ne repond pas — et parce que le defaut est invisible sur QWERTY.
        KeyboardLayout.shared.start()
        print(KeyboardLayout.describe().split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))

        print("")
        if failures == 0 {
            print("  ✓ Toutes les séquences passent.")
            print("    Cela ne remplace pas les douze critères : la porte est juste,")
            print("    le comportement du système réel reste à mesurer.")
        } else {
            print("  ✗ \(failures) étape(s) en échec — ne pas passer aux critères avant correction.")
        }
        print("")
        return failures
    }
}
