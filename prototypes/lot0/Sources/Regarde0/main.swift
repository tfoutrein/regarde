import AppKit
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Point d'entree du prototype du lot 0.
//
// Ordre de demarrage, et il compte :
//   1. preflights   — savoir AVANT de conclure quoi que ce soit sur un bug
//   2. ecrans       — la moitie des anomalies de position viennent d'une disposition
//                     qu'on avait en tete de travers
//   3. panneaux     — construits mais NON ordonnes (ADR-0010)
//   4. tap          — en dernier : s'il echoue, les points 1 a 3 ont deja imprime
//                     de quoi savoir pourquoi
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: logSubsystem, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemController.emit(RunReport.startupBanner())

        // 1. Permissions. Aucune demande, uniquement des preflights : une invite
        //    volerait le focus, ce qui est precisement ce que le produit ne doit pas faire.
        Preflight.logReport()

        // 2. Disposition des ecrans.
        StatusItemController.emit(Coordinates.describeScreens())

        // 3. Panneaux et barre de menus.
        StatusItemController.shared.setUp()
        OverlayController.shared.setUp()

        // 4. Le tap.
        if EventTap.shared.start() {
            EventTap.shared.startWatchdog()
            log.notice("tap demarre")
        } else {
            StatusItemController.emit("""
            ✗ Le tap n'a pas pu demarrer.

              La cause est une permission dans plus de neuf cas sur dix, pas le code.
              Verifie Surveillance de la saisie ET Accessibilite dans le rapport ci-dessus,
              puis relance. Si les deux sont accordees et que le tap echoue quand meme,
              c'est le cas du § 4.2 : retire puis remets l'entree dans Surveillance de la
              saisie, et relance.
            """)
        }

        // Prise de contact TCC pour ScreenCaptureKit, hors de tout chemin de geste
        // (§ 11.3, lot 1). Sans effet si Enregistrement de l'ecran n'est pas accorde.
        Task.detached(priority: .utility) { await SnapshotBench.shared.warmUp() }

        observeSystemState()
    }

    /// La porte passe en `passthrough` des que le systeme n'est plus dans un etat ou
    /// arbitrer a un sens. Un doute se resout TOUJOURS en faveur de l'application testee.
    private func observeSystemState() {
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter

        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                OptionGate.shared.currentMode = .passthrough
                OptionGate.shared.requestReset()
            }
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                OptionGate.shared.currentMode = .active
            }
        }

        wnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            OptionGate.shared.currentMode = .passthrough
            OptionGate.shared.requestReset()
        }
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            OptionGate.shared.currentMode = .active
            // Au reveil, le tap est frequemment desarme sans notification.
            Task.detached(priority: .utility) { await SnapshotBench.shared.warmUp() }
        }
        wnc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
            OptionGate.shared.currentMode = .passthrough
            OptionGate.shared.requestReset()
        }
        wnc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
            OptionGate.shared.currentMode = .active
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StatusItemController.emit(EventTap.shared.healthLine())
        StatusItemController.emit(LatencyHistogram.shared.report())
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

// Auto-test de la porte, avant toute initialisation graphique : il ne demande ni
// permission, ni ecran, et rend un code de sortie exploitable en ligne de commande.
if CommandLine.arguments.contains("--selftest") {
    exit(GateSelfTest.runAll() == 0 ? 0 : 1)
}

// Diagnostic en ligne de commande : permissions, ecrans, et surtout ETAT REEL DU TAP
// apres une tentative de demarrage.
//
// Le § 4.2 demande de ne jamais deboguer plus de dix minutes sans avoir verifie que le
// tap est vivant. Quand l'application est lancee par `open`, sa sortie standard n'est
// visible nulle part et `os_log` n'est pas toujours indexe : sans ce mode, la seule
// facon de repondre a la question est d'ouvrir un menu a la souris.
if CommandLine.arguments.contains("--doctor") {
    FileHandle.standardError.write(Data(Preflight.report().utf8))
    FileHandle.standardError.write(Data((Coordinates.describeScreens() + "\n\n").utf8))

    let started = EventTap.shared.start()

    // Generer soi-meme du trafic plutot que d'attendre que l'utilisateur bouge la souris :
    // le compteur d'evenements est le seul temoin fiable de la sante du tap, et un doctor
    // qui repond « 0 evenement » sans savoir si c'est la faute du tap ou de l'immobilite
    // ne diagnostique rien.
    //
    // Ces evenements sont SYNTHETIQUES : leur `timestamp` peut valoir zero, ce qui exerce
    // au passage le chemin de repli d'horodatage — le cas des pilotes tiers du § 3.1,
    // c'est-a-dire une partie de C12, sans avoir a installer Karabiner.
    //
    // Uniquement des mouvements, jamais de clic, et le curseur revient a sa place.
    if started {
        let origin = CGEvent(source: nil)?.location ?? .zero
        for i in 0..<24 {
            let dx = CGFloat((i % 8) - 4)
            let p = CGPoint(x: origin.x + dx, y: origin.y + CGFloat((i / 8) - 1))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: origin, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    // Laisser la run loop du tap s'installer et drainer ce qui precede.
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    var out = ["Tap", "───"]
    out.append("  demarrage        \(started ? "réussi" : "ÉCHOUÉ")")
    out.append("  \(EventTap.shared.healthLine())")
    if !started {
        out.append("")
        out.append("  Le tap n'a pas demarre. La cause est une permission dans plus de neuf")
        out.append("  cas sur dix. Si les deux permissions requises sont accordees ci-dessus,")
        out.append("  c'est le cas du § 4.2 : retire puis remets l'entree dans Surveillance")
        out.append("  de la saisie, et relance.")
    } else if EventTap.shared.eventsSeen == 0 {
        out.append("")
        out.append("  ⚠ Le tap est installe mais n'a vu AUCUN des 25 evenements envoyes.")
        out.append("    C'est la panne silencieuse du § 4.2 : le port se declare actif et")
        out.append("    ne recoit rien. Retire puis remets l'entree dans Surveillance de la")
        out.append("    saisie, et relance.")
    } else {
        let repli = SessionClock.shared.fallbackCount
        out.append("  horodatages en repli  \(repli)\(repli > 0 ? "  (evenements synthetiques — chemin C12 exerce)" : "")")
    }
    out.append("")
    FileHandle.standardError.write(Data((out.joined(separator: "\n") + "\n").utf8))
    exit(started ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// `.accessory` : aucune icone dans le Dock, aucune barre de menus propre, et surtout
// l'application ne devient jamais active — elle ne peut donc pas voler le focus a
// l'application testee. C'est le critere C4, garanti par construction plutot que par
// precaution.
app.setActivationPolicy(.accessory)
app.run()
