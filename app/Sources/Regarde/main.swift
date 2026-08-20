import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Point d'entrée de Regarde.
//
// Ordre de démarrage, et il compte — le lot 0 a montré ce que coûte l'inverse :
//   1. la barre de menus, pour qu'un état soit visible même si la suite échoue
//   2. l'observation de l'état système
//   3. la prise de contact TCC, hors de tout chemin de session (R1)
//
// Rien ici ne demande de permission. Une invite volerait le focus, et à ce stade
// l'application n'a encore rien à capturer.
// ─────────────────────────────────────────────────────────────────────────────

// Auto-test de la porte à verrou : 13 séquences d'événements, sans permission ni écran.
// Reprises telles quelles du lot 0, où elles ont été vérifiées comme détectant
// réellement les défauts qu'elles couvrent.
if CommandLine.arguments.contains("--selftest") {
    exit(GateSelfTest.runAll() == 0 ? 0 : 1)
}

// La table de cas de la conversion de coordonnées tourne sans écran, sans permission
// et sans interface : elle vérifie des dispositions qu'on n'a pas sous la main.
if CommandLine.arguments.contains("--geometry-test") {
    exit(GeometrySelfTest.runAll() == 0 ? 0 : 1)
}

// Les marques : numérotation, modes de peinture, ancrage des badges, codes de la palette
// et confinement à la fenêtre cible. Tourne sans écran et sans permission — ce qu'il
// vérifie est du calcul, pas de l'affichage.
if CommandLine.arguments.contains("--marks-test") {
    exit(MainActor.assumeIsolated { MarksSelfTest.run() } ? 0 : 1)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: logSubsystem, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.reset()
        Journal.write("démarrage")

        // La disposition du clavier doit être résolue AVANT l'enregistrement des
        // raccourcis : ils s'appuient sur elle pour trouver la bonne touche.
        KeyboardLayout.shared.start(resolving:
            HotKeyAction.allCases.map(\.character) + MarkTool.allCases.map(\.key) + ["z"])
        ToolKeyCache.shared.start()
        Journal.section("Clavier", KeyboardLayout.shared.describe())

        StatusItemController.shared.setUp()
        OverlayController.shared.setUp()
        SessionCoordinator.shared.observeSystemState()

        HotKeyCenter.shared.onAction = { action in
            MainActor.assumeIsolated { AppDelegate.handle(action) }
        }
        // Le tap alimente le ring que le contrôleur draine. Sans les deux autorisations
        // d'entrée, il ne démarre pas — le doctor le dit, et ⌃⌥S reste atteignable.
        // La porte démarre FERMÉE. Depuis S22, ⌥⌘ n'arme que dans la fenêtre cible, et
        // la cible n'existe qu'à partir de l'ouverture d'une session : hors session, la
        // porte doit laisser passer, sans quoi elle retiendrait des clics au nom d'une
        // cible qu'elle n'a pas.
        OptionGate.shared.currentMode = .passthrough

        if TestFlags.visibleCapture {
            Journal.write("⚠ --visible-capture : le calque APPARAÎT dans les captures")
        }

        if EventTap.shared.start() {
            EventTap.shared.startWatchdog()
            Journal.write("tap démarré — ⌃⌥S pour ouvrir une session")
        } else {
            Journal.write("⚠ tap non démarré : voir le diagnostic (⌃⌥S)")
        }

        HotKeyCenter.shared.install()
        Journal.section("Raccourcis", HotKeyCenter.shared.describe())

        // Diagnostic complet au démarrage, sous la vraie identité de l'application.
        // Chaque ligne exécute son opération réelle — c'est tout l'objet de S11.
        Task { await Doctor.shared.runAll() }
    }

    /// Aiguillage des raccourcis. Au lot 1, seul le diagnostic a une destination
    /// réelle : les autres actions attendent les lots qui les portent.
    @MainActor
    static func handle(_ action: HotKeyAction) {
        switch action {
        case .openSession:
            // ⌃⌥S ouvre une session, et retombe sur le diagnostic quand elle ne peut pas
            // s'ouvrir. Le critère de S10 tient toujours : le raccourci répond sans
            // aucune permission, et sans permission il montre justement le diagnostic.
            SessionCoordinator.shared.openSession()
        case .endSession:
            SessionCoordinator.shared.closeSession()
        case .toggleMicrophoneLock:
            Journal.write("⌃⌥M — verrou du micro (lot 5)")
        case .toggleAnnotationLock:
            Journal.write("⌃⌥L — mode annotation verrouillé (lot 2)")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// `.accessory` : aucune icône dans le Dock, ignoré par Stage Manager, et surtout
// incapable de devenir actif de lui-même. C'est ce qui garantit par construction que
// l'application testée ne perd jamais le focus.
app.setActivationPolicy(.accessory)
app.run()
