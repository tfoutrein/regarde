import AppKit
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Orchestration des panneaux — ADR-0010, spécification § 6.1
//
// La décision que ce fichier incarne : le calque n'est ordonné à l'écran QUE pendant le
// geste. Une couche de composition permanente fait perdre à l'application testée les
// chemins optimisés du WindowServer — l'outil censé diagnostiquer une lenteur en
// deviendrait la cause.
//
// Le lot 0 l'a mesuré : au repos, le coût est de −0,3 %, dans le bruit ; sous tracé
// continu, +0,21 %, pour un seuil de 5 %.
//
// S18 y ajoute l'industrialisation : une reconfiguration d'écrans en cours d'exécution
// ne doit laisser ni panneau orphelin — qui flotterait sur un écran disparu — ni panneau
// manquant sur un écran fraîchement branché.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private let log = Logger(subsystem: logSubsystem, category: "overlay")
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private(set) var geometry = ScreenGeometry(screens: [])
    private var visible = false

    /// Nombre de reconstructions depuis le lancement. Une reconstruction non provoquée
    /// par un vrai changement d'écrans est un défaut : on la compte pour la voir.
    private(set) var rebuildCount = 0

    // MARK: - Mise en place

    func setUp() {
        rebuildPanels(reason: "démarrage")

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                OverlayController.shared.rebuildPanels(reason: "changement d'écrans")
            }
        }

        // Le gel sur occlusion : quand un panneau passe hors champ — Mission Control,
        // Space voisin — continuer à commiter des transactions coûte sans rien afficher.
        //
        // On ne transporte pas l'objet `Notification` à travers la frontière d'isolation
        // (il n'est pas `Sendable`) : on relit l'état de tous les panneaux, qui sont peu
        // nombreux et déjà sous le contrôle de cet acteur.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { OverlayController.shared.refreshOcclusion() }
        }
    }

    /// Relit l'état d'occlusion de chaque panneau et gèle ceux qui ne sont pas visibles.
    private func refreshOcclusion() {
        for panel in panels.values {
            panel.inkView.setFrozen(!panel.occlusionState.contains(.visible))
        }
    }

    // MARK: - Reconstruction

    /// Reconstruit l'ensemble des panneaux pour coller à la disposition courante.
    ///
    /// Les panneaux dont l'écran existe encore sont RÉALIGNÉS plutôt que recréés : un
    /// panneau recréé perd son contenu, et un changement de résolution en cours de
    /// session effacerait les traits déjà posés.
    func rebuildPanels(reason: String) {
        geometry = Self.currentGeometry()

        var kept: [CGDirectDisplayID: OverlayPanel] = [:]
        var created: [CGDirectDisplayID] = []

        for screen in NSScreen.screens {
            let id = OverlayPanel.displayID(of: screen)
            // Un identifiant nul signale un écran que le système ne sait pas nommer :
            // en fabriquer un panneau produirait un doublon à la reconfiguration
            // suivante, puisque rien ne permettrait de le retrouver.
            guard id != 0 else {
                log.error("écran sans identifiant — panneau non créé")
                continue
            }

            if let existing = panels.removeValue(forKey: id) {
                existing.realign(to: screen, geometry: geometry)
                kept[id] = existing
            } else {
                let panel = OverlayPanel(screen: screen, geometry: geometry)
                created.append(id)
                kept[id] = panel
            }
        }

        // Ce qui reste dans `panels` correspond à des écrans disparus. Sans ce nettoyage,
        // un panneau flotterait sur un écran débranché : invisible, mais consommant un
        // display link et une place dans le compositeur.
        let orphans = Array(panels.keys)
        for (_, orphan) in panels {
            orphan.hide()
            orphan.close()
        }
        panels = kept
        rebuildCount += 1

        if visible { showPanels() }

        var lines = ["raison     \(reason)",
                     "panneaux   \(panels.count)"]
        if !created.isEmpty { lines.append("créés      \(created.map(String.init).joined(separator: ", "))") }
        if !orphans.isEmpty { lines.append("retirés    \(orphans.map(String.init).joined(separator: ", "))") }
        lines.append(contentsOf: geometry.describe())
        Journal.section("Panneaux", lines)
    }

    /// Lit la disposition courante depuis AppKit et la convertit en valeurs pures.
    ///
    /// `NSScreen` s'arrête ici : au-delà, tout raisonne sur `ScreenGeometry`, testable
    /// sur des dispositions absentes de la machine (S17).
    static func currentGeometry() -> ScreenGeometry {
        ScreenGeometry(screens: NSScreen.screens.map { screen in
            ScreenInfo(displayID: OverlayPanel.displayID(of: screen),
                       cocoaFrame: screen.frame,
                       scale: screen.backingScaleFactor)
        })
    }

    // MARK: - Affichage

    func showPanels() {
        visible = true
        for panel in panels.values { panel.show() }
    }

    func hidePanels() {
        visible = false
        for panel in panels.values { panel.hide() }
    }

    // MARK: - Accès

    func panel(for displayID: CGDirectDisplayID) -> OverlayPanel? { panels[displayID] }
    func forEachPanel(_ body: (OverlayPanel) -> Void) { panels.values.forEach(body) }

    var panelCount: Int { panels.count }
    var isShowing: Bool { visible }

    func clearAll() {
        forEachPanel { $0.inkView.clear() }
    }

    // MARK: - Diagnostic

    /// Vérifie que chaque écran a exactement un panneau, et réciproquement.
    ///
    /// C'est le critère de fin de S18, exprimé en code plutôt qu'en protocole : « ni
    /// panneau orphelin ni panneau manquant » se constate, il ne se raconte pas.
    func audit() -> [String] {
        let screenIDs = Set(NSScreen.screens.map(OverlayPanel.displayID).filter { $0 != 0 })
        let panelIDs = Set(panels.keys)

        var lines = ["reconstructions  \(rebuildCount)",
                     "écrans           \(screenIDs.count)",
                     "panneaux         \(panelIDs.count)"]

        let missing = screenIDs.subtracting(panelIDs)
        let orphans = panelIDs.subtracting(screenIDs)
        if !missing.isEmpty { lines.append("⚠ écran sans panneau : \(missing.map(String.init).joined(separator: ", "))") }
        if !orphans.isEmpty { lines.append("⚠ panneau orphelin : \(orphans.map(String.init).joined(separator: ", "))") }
        if missing.isEmpty && orphans.isEmpty { lines.append("✓ correspondance exacte écran ↔ panneau") }

        for panel in panels.values.sorted(by: { $0.displayID < $1.displayID }) {
            let f = panel.frame
            let matches = NSScreen.screens.first { OverlayPanel.displayID(of: $0) == panel.displayID }
                .map { $0.frame == f } ?? false
            lines.append(String(format: "display %u — cadre %.0f×%.0f à (%.0f, %.0f) @%.0f×%@",
                                panel.displayID, f.width, f.height, f.minX, f.minY,
                                panel.screenInfo.scale,
                                matches ? "" : "  ⚠ cadre désaccordé de son écran"))
        }
        return lines
    }
}
