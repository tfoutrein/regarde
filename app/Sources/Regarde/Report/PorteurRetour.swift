import AppKit
import ApplicationServices
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Le porteur du ⏎ — S54, spécification § 9.10, correction 3
//
// Après la publication, le HUD propose « ⏎ Envoyer à <agent> ». Le ⏎ qui suit
// active la fenêtre de l'agent et y injecte la phrase — AX d'abord, ⌘V
// synthétique en repli, presse-papiers seul en dernier recours, en silence.
//
// LA FENÊTRE DE GRÂCE est la seule chose qui autorise le tap à toucher un ⏎ :
//
//   · armée à la publication, pour quelques secondes, désarmée au premier
//     usage ou à l'échéance ;
//   · UN ⏎ NU, dans la fenêtre : avalé et porté. Tout le reste — ⏎ modifié,
//     autre touche, hors fenêtre — passe INTACT. « Aucun ⏎ n'est avalé hors
//     de la fenêtre de grâce » est un critère du plan, et le lot 2 a payé pour
//     apprendre ce que coûte une touche volée (⌘Z, le raccourci le plus
//     utilisé de macOS, intercepté en permanence — défaut n°11 de sa recette).
//
// La DÉCISION est une fonction pure sur (grâce, touche, modificateurs) ; l'état
// de grâce est un atomique lu sur le thread du tap — une charge, pas un verrou,
// le budget de latence du tap ne bouge pas.
// ─────────────────────────────────────────────────────────────────────────────

enum PorteurRetour {

    private static let log = Logger(subsystem: logSubsystem, category: "porteur")

    /// L'échéance de la grâce, en secondes d'époque — 0 = désarmée. Atomique :
    /// écrite sur le MainActor, lue sur le thread du tap.
    private static let echeance = OSAllocatedUnfairLock(initialState: 0.0)
    /// La phrase à porter, posée à l'armement.
    private static let phrasePortee = OSAllocatedUnfairLock(initialState: "")

    static var graceActive: Bool {
        Date().timeIntervalSince1970 < echeance.withLock { $0 }
    }

    @MainActor
    static func armer(phrase: String, duree: TimeInterval = 8) {
        phrasePortee.withLock { $0 = phrase }
        echeance.withLock { $0 = Date().timeIntervalSince1970 + duree }
        HUDWindow.shared.announce("⏎ Envoyer à l'agent",
                                  detail: "pendant \(Int(duree)) s — sinon la phrase reste au presse-papiers",
                                  duration: duree)
    }

    static func desarmer() { echeance.withLock { $0 = 0 } }

    /// LA décision, pure. `true` = le tap avale ce ⏎ et le porteur s'en charge.
    ///
    /// Le ⏎ doit être NU : un ⌘⏎ ou un ⇧⏎ appartient à l'application qui le
    /// reçoit — l'avaler recréerait le défaut du ⌘Z.
    static func decision(graceActive: Bool, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard graceActive, keyCode == 36 else { return false }
        let modificateurs: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate,
                                           .maskControl, .maskSecondaryFn]
        return flags.intersection(modificateurs).isEmpty
    }

    /// Appelé du thread du tap quand la décision a dit oui : désarme (un seul
    /// port par grâce) et passe la main au MainActor pour le geste.
    static func porter() {
        desarmer()
        let phrase = phrasePortee.withLock { $0 }
        Task { @MainActor in injecter(phrase) }
    }

    // MARK: - L'injection, best-effort à trois étages

    /// AX d'abord — poser la valeur dans l'élément focalisé de l'agent —, ⌘V
    /// synthétique ensuite, et si tout échoue : rien, en silence. La phrase est
    /// DÉJÀ au presse-papiers ; l'injection est un confort, pas un contrat.
    @MainActor
    private static func injecter(_ phrase: String) {
        guard let provider = DecisionProjet.providers().first(where: { kill($0.pid, 0) == 0 }),
              let application = NSRunningApplication(processIdentifier: provider.pid)
                ?? porteurDeFenetre(de: provider.pid) else {
            Journal.event(.system, "porteur — aucun agent à activer, la phrase reste au presse-papiers")
            return
        }
        application.activate()
        Metriques.enregistrer(["event": "injection", "agent": provider.pid])

        // Étage 1 : AX. L'élément focalisé de l'application, s'il accepte une
        // valeur, reçoit la phrase — sans passer par le clavier.
        let ax = AXUIElementCreateApplication(application.processIdentifier)
        var focalise: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString,
                                         &focalise) == .success,
           let element = focalise,
           AXUIElementSetAttributeValue(element as! AXUIElement,
                                        kAXValueAttribute as CFString,
                                        phrase as CFString) == .success {
            Journal.event(.system, "porteur — phrase injectée par AX")
            return
        }

        // Étage 2 : ⌘V synthétique, la phrase étant déjà au presse-papiers.
        // Repli, pas premier choix : il dépend du focus et d'un raccourci que
        // l'application peut avoir remappé.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let src = CGEventSource(stateID: .hidSystemState)
            for (down, code) in [(true, CGKeyCode(9)), (false, CGKeyCode(9))] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                e?.flags = .maskCommand
                e?.post(tap: .cghidEventTap)
            }
            Journal.event(.system, "porteur — repli ⌘V synthétique")
        }
    }

    /// Un agent CLI (claude dans un terminal) n'est pas une application à
    /// fenêtres : on remonte au TERMINAL qui l'héberge — son ancêtre porteur de
    /// fenêtre le plus proche.
    private static func porteurDeFenetre(de pid: pid_t) -> NSRunningApplication? {
        var courant = pid
        for _ in 0..<10 {
            var info = proc_bsdinfo()
            let taille = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(courant, PROC_PIDTBSDINFO, 0, &info, taille) == taille else {
                return nil
            }
            let parent = pid_t(info.pbi_ppid)
            guard parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent),
               app.activationPolicy == .regular {
                return app
            }
            courant = parent
        }
        return nil
    }
}
