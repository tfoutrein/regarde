import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// T0.2 — L'element de barre de menus
//
// Au lot 0 il ne pilote rien : il rend l'etat LISIBLE. C'est ce qui permet
// d'appliquer la regle de survie du § 4.2 — ne jamais deboguer plus de dix minutes
// sans avoir verifie que le tap est vivant — sans avoir a lire un journal.
//
// L'icone porte l'etat reel : gris au repos, bleu quand le calque est ordonne,
// rouge quand le tap est mort. Un indicateur qui ment est pire que pas d'indicateur.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class StatusItemController {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private var refreshTimer: Timer?
    private let healthItem = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
    private let latencyItem = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
    private let benchItem = NSMenuItem(title: "Activer le banc C11", action: nil, keyEquivalent: "")

    func setUp() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◎"
        item.button?.toolTip = "Regarde — prototype lot 0"

        let menu = NSMenu()
        menu.autoenablesItems = false

        healthItem.isEnabled = false
        latencyItem.isEnabled = false
        menu.addItem(healthItem)
        menu.addItem(latencyItem)
        menu.addItem(.separator())

        addItem(to: menu, "Rapport des permissions", key: "p") { Preflight.logReport() }
        addItem(to: menu, "Rapport de latence (C7)", key: "l") {
            Self.emit(LatencyHistogram.shared.report())
        }
        addItem(to: menu, "Disposition des ecrans", key: "e") {
            Self.emit(Coordinates.describeScreens())
        }
        menu.addItem(.separator())

        addItem(to: menu, "Épingler / libérer le calque", key: "o") {
            OverlayController.shared.debugToggle()
            Self.emit(OverlayController.shared.isPinned
                      ? "Calque épinglé — il reste à l'écran pour mesurer C8 et C9."
                      : "Calque libéré — retour au comportement normal.")
        }
        addItem(to: menu, "Effacer les traits", key: "k") {
            OverlayController.shared.clearAll()
        }
        addItem(to: menu, "Remettre les mesures a zero", key: "r") {
            LatencyHistogram.shared.reset()
            Self.emit("Mesures de latence remises a zero.")
        }
        menu.addItem(.separator())

        benchItem.target = self
        benchItem.action = #selector(toggleBench)
        menu.addItem(benchItem)
        addItem(to: menu, "Rapport du banc C11", key: "") {
            Task { Self.emit(await SnapshotBench.shared.report()) }
        }
        menu.addItem(.separator())

        addItem(to: menu, "Tout exporter (JSON)", key: "j") {
            Task { Self.emit(await RunReport.json()) }
        }
        menu.addItem(.separator())
        addItem(to: menu, "Quitter", key: "q") { NSApp.terminate(nil) }

        item.menu = menu
        self.item = item

        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated { StatusItemController.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    private func addItem(to menu: NSMenu, _ title: String, key: String, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: key)
        let box = MenuAction(action)
        item.target = box
        item.representedObject = box   // conserve la reference : NSMenuItem.target est faible
        menu.addItem(item)
    }

    private func refresh() {
        let tap = EventTap.shared
        let showing = OverlayController.shared.isShowing

        item?.button?.title = !tap.isEnabled ? "◉" : (showing ? "◍" : "◎")
        item?.button?.contentTintColor = !tap.isEnabled ? .systemRed
                                       : (showing ? .systemBlue : nil)

        healthItem.title = tap.healthLine()
        let s = LatencyHistogram.shared.summary()
        // « ech. » et non « pts » : `count` compte des echantillons de latence, pas des
        // points ajoutes au tracé. Le filtre des 0,75 px et le garde sur le trait vide
        // rejettent des evenements qui produisent pourtant un echantillon.
        latencyItem.title = s.count == 0
            ? "latence : aucun echantillon"
            : String(format: "latence p50 %.1f ms · p95 %.1f ms · %llu ech. · %d traits",
                     s.p50, s.p95, s.count, OverlayController.shared.totalStrokes)
    }

    @objc private func toggleBench() {
        Task {
            if await SnapshotBench.shared.isEnabled {
                await SnapshotBench.shared.disable()
                await MainActor.run { self.benchItem.title = "Activer le banc C11" }
                Self.emit("Banc C11 desactive.")
            } else {
                let dir = RunReport.outputDirectory.appendingPathComponent("c11", isDirectory: true)
                do {
                    try await SnapshotBench.shared.enable(directory: dir)
                    await SnapshotBench.shared.warmUp()
                    await MainActor.run { self.benchItem.title = "Desactiver le banc C11" }
                    Self.emit("Banc C11 actif → \(dir.path)\nPasse le temoin 1 en mode compteur (touche 3).")
                } catch {
                    Self.emit("Banc C11 : \(error.localizedDescription)")
                }
            }
        }
    }

    /// Sortie unique : stderr pour un lancement en terminal, ET un fichier journal.
    ///
    /// Le fichier n'est pas un confort. Lancee par `open`, l'application n'a pas de
    /// terminal ou ecrire, et `os_log` ne remonte rien pour ce bundle : sans trace sur
    /// disque, son etat reel n'est observable par aucun moyen. Or c'est precisement dans
    /// ce mode de lancement — le seul qui porte la vraie identite TCC de l'application —
    /// que les preflights disent la verite.
    nonisolated static func emit(_ text: String) {
        let block = "\n" + text + "\n"
        FileHandle.standardError.write(Data(block.utf8))

        let url = RunReport.outputDirectory.appendingPathComponent("journal.txt")
        if let data = block.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Boite a fermeture pour les elements de menu : `NSMenuItem` exige une cible
/// Objective-C, et une fermeture Swift n'en est pas une.
private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}
