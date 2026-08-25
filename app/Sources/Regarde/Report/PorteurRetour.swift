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
    /// Le projet publié — c'est LUI qui départage les agents au moment du port.
    private static let projetPorte = OSAllocatedUnfairLock(initialState: String?.none)

    static var graceActive: Bool {
        Date().timeIntervalSince1970 < echeance.withLock { $0 }
    }

    @MainActor
    static func armer(phrase: String, duree: TimeInterval = 8, projet: String? = nil) {
        phrasePortee.withLock { $0 = phrase }
        projetPorte.withLock { $0 = projet }
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
        let projet = projetPorte.withLock { $0 }
        Task { @MainActor in injecter(phrase, projet: projet) }
    }

    // MARK: - L'injection, best-effort à trois étages

    /// AX d'abord — poser la valeur dans l'élément focalisé de l'agent —, ⌘V
    /// synthétique ensuite, et si tout échoue : rien, en silence. La phrase est
    /// DÉJÀ au presse-papiers ; l'injection est un confort, pas un contrat.
    @MainActor
    private static func injecter(_ phrase: String, projet: String?) {
        // Le PREMIER vivant ne suffit pas : le binaire `codex` de ChatGPT.app
        // porte un nom d'agent et gagnait la course — le ⏎ activait ChatGPT
        // (recette du lot 4, test 5.4). Les agents s'essaient du plus au moins
        // pertinent — projet publié d'abord, fraîcheur ensuite — jusqu'à celui
        // qui résout vers une vraie fenêtre.
        let vivants = DecisionProjet.providers().filter { kill($0.pid, 0) == 0 }
        var retenu: (DecisionProjet.Provider, NSRunningApplication)?
        for provider in DecisionProjet.agentsClasses(parmi: vivants, projet: projet) {
            if let application = NSRunningApplication(processIdentifier: provider.pid)
                ?? porteurDeFenetre(de: provider.pid),
               application.activationPolicy == .regular {
                retenu = (provider, application)
                break
            }
        }
        guard let (provider, application) = retenu else {
            Journal.event(.system, "porteur — aucun agent à activer, la phrase reste au presse-papiers")
            return
        }
        Journal.event(.system, "porteur — cible \(provider.chemin) (pid \(provider.pid))"
                      + " via \(application.localizedName ?? "?")")
        application.activate()
        Metriques.enregistrer(["event": "injection", "agent": provider.pid])

        // Étage 1 : AX, avec CONTRE-LECTURE. Le code retour ne suffit pas :
        // Warp rend son interface au GPU et sa couche d'accessibilité est
        // synthétique — setValue répond « succès » sans rien écrire dans le
        // vrai champ. Le journal disait « phrase injectée par AX » et
        // l'utilisateur regardait un champ vide (recette du lot 4, test 5.4).
        // On ne croit que ce qu'on RELIT.
        let ax = AXUIElementCreateApplication(application.processIdentifier)
        var focalise: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString,
                                         &focalise) == .success,
           let element = focalise,
           AXUIElementSetAttributeValue(element as! AXUIElement,
                                        kAXValueAttribute as CFString,
                                        phrase as CFString) == .success {
            var relu: CFTypeRef?
            AXUIElementCopyAttributeValue(element as! AXUIElement,
                                          kAXValueAttribute as CFString, &relu)
            if let texte = relu as? String, texte.contains(phrase) {
                Journal.event(.system, "porteur — phrase injectée par AX, contre-lue")
                return
            }
            Journal.event(.system, "porteur — AX a dit oui mais la valeur n'a pas pris — repli ⌘V")
        }

        // Étage 2 : ⌘V synthétique, la phrase étant déjà au presse-papiers.
        // La touche ⌘ est une touche RÉELLE (code 55), pressée et TENUE
        // plusieurs frames autour du V : Warp interroge l'état du clavier
        // image par image, et des flags atomiques portés par le seul V
        // retombent avant la frame suivante — le collage ne part jamais.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            let src = CGEventSource(stateID: .hidSystemState)
            func poste(_ code: CGKeyCode, enfoncee: Bool, flags: CGEventFlags = []) {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: enfoncee)
                if !flags.isEmpty { e?.flags = flags }
                e?.post(tap: .cghidEventTap)
            }
            poste(55, enfoncee: true)                       // ⌘ réelle, tenue
            usleep(90_000)
            poste(9, enfoncee: true, flags: .maskCommand)   // V
            usleep(30_000)
            poste(9, enfoncee: false, flags: .maskCommand)
            usleep(60_000)
            poste(55, enfoncee: false)                      // ⌘ relâchée
            Journal.event(.system, "porteur — repli ⌘V synthétique, ⌘ tenue sur plusieurs frames")
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
