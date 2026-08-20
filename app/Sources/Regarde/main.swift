import AppKit
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: logSubsystem, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.reset()
        Journal.write("démarrage")

        StatusItemController.shared.setUp()
        SessionCoordinator.shared.observeSystemState()

        TCCContact.shared.refresh(trigger: .launch)
        Task { await TCCContact.shared.startHourlyProbe() }
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
