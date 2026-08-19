import AppKit
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Orchestration des panneaux — ADR-0010, specification § 6.1
//
// La decision que ce fichier incarne : le calque n'est ordonne a l'ecran QUE pendant
// le geste. Une couche de composition permanente fait perdre a l'application testee
// les chemins optimises du WindowServer — l'outil cense diagnostiquer une lenteur en
// deviendrait la cause. C'est le critere C3b, et son etat 2 doit couter moins de 1 %.
//
// Sequence, telle que le § 6.1 la decrit :
//   ⌥⌘ presse   → le tap l'a deja decide, les points sont bufferises dans le ring,
//                 les panneaux sont ordonnes ici et le trait apparait complet quand
//                 la fenetre arrive.
//   geste fini  → les panneaux sont retires.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private let log = Logger(subsystem: logSubsystem, category: "overlay")
    private var panels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var visible = false

    /// Delai de grace avant retrait, en secondes.
    ///
    /// Sans lui, relacher ⌥⌘ une fraction de seconde pour le represser ferait
    /// disparaitre puis reapparaitre le calque, avec un clignotement visible et un
    /// cout de composition a chaque aller-retour.
    private static let hideGrace: TimeInterval = 0.35
    private var hideWorkItem: DispatchWorkItem?

    func setUp() {
        rebuildPanels()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { OverlayController.shared.rebuildPanels() }
        }

        // Le tap notifie les transitions d'armement ; c'est ce qui declenche
        // l'ordonnancement, sans aucun polling au repos.
        OptionGate.shared.onStateChanged = { armed, stroking in
            DispatchQueue.main.async {
                OverlayController.shared.stateChanged(armed: armed, stroking: stroking)
            }
        }

        EventTap.shared.onControlKey = { key in
            DispatchQueue.main.async {
                switch key {
                case .escape: OverlayController.shared.forEachView { $0.cancelLiveStroke() }
                case .undo:   OverlayController.shared.forEachView { $0.undoLastStroke() }
                }
            }
        }
    }

    // MARK: - Panneaux

    private func rebuildPanels() {
        var kept: [CGDirectDisplayID: OverlayPanel] = [:]

        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? 0

            let panel: OverlayPanel
            if let existing = panels.removeValue(forKey: id) {
                existing.realign(to: screen)
                panel = existing
            } else {
                panel = OverlayPanel(screen: screen)
                configure(panel, for: screen)
            }
            // Le cadre a pu changer sans que l'ecran change d'identifiant : la fonction
            // de conversion est donc reinstallee a chaque reconstruction.
            configureConversion(panel, for: screen)
            kept[id] = panel
        }

        // Les panneaux restants correspondent a des ecrans debranches.
        for (_, orphan) in panels {
            orphan.inkView.stopRendering()
            orphan.orderOut(nil)
            orphan.close()
        }
        panels = kept

        if visible { showPanels() }
        log.notice("panneaux reconstruits : \(self.panels.count) ecran(s)")
    }

    private func configure(_ panel: OverlayPanel, for screen: NSScreen) {
        panel.inkView.onFrame = { [weak self] in
            MainActor.assumeIsolated { self?.afterFrame() }
        }
        panel.inkView.onStrokeBegan = { eventLocation, hostTicks in
            let stamped = SessionClock.shared.stamp(hostTicks: hostTicks)
            let requested = SessionClock.hostTicksNow()
            Task.detached(priority: .userInitiated) {
                await SnapshotBench.shared.capture(
                    at: stamped.time, eventLocation: eventLocation, requestedAtTicks: requested
                )
            }
        }
    }

    private func configureConversion(_ panel: OverlayPanel, for screen: NSScreen) {
        let frame = screen.frame
        panel.inkView.eventToLocal = { p in
            Coordinates.windowLocal(fromEventLocation: p, windowFrame: frame)
        }
    }

    // MARK: - Transitions

    private func stateChanged(armed: Bool, stroking: Bool) {
        if armed || stroking {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showPanels()
        } else {
            scheduleHide()
        }
    }

    private func showPanels() {
        guard !visible || panels.values.contains(where: { !$0.isVisible }) else { return }
        visible = true
        for panel in panels.values {
            panel.show()
            panel.inkView.startRendering()
        }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Ne jamais retirer sous un geste : entre la planification et
                // l'execution, l'utilisateur a pu represser le modificateur.
                guard !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
                self.hidePanels()
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideGrace, execute: item)
    }

    private func hidePanels() {
        visible = false
        for panel in panels.values {
            panel.inkView.stopRendering()
            panel.hide()
        }
    }

    /// Appelee a chaque cycle de rendu d'une vue : dernier filet si une transition
    /// de desarmement s'est perdue.
    private func afterFrame() {
        guard visible, !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
        if hideWorkItem == nil { scheduleHide() }
    }

    // MARK: - Divers

    func forEachView(_ body: (InkView) -> Void) {
        for panel in panels.values { body(panel.inkView) }
    }

    func clearAll() {
        forEachView { $0.clearAll() }
    }

    var panelCount: Int { panels.count }
    var isShowing: Bool { visible }
    var totalStrokes: Int { panels.values.reduce(0) { $0 + $1.inkView.strokeCount } }

    /// Force l'affichage, pour verifier C8 et C9 sans avoir a tracer.
    func debugToggle() {
        if visible { hidePanels() } else { showPanels() }
    }
}
