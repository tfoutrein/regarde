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
    /// Calque maintenu a l'ecran par le menu de diagnostic, pour mesurer C8 et C9 sans
    /// avoir a tenir le modificateur. Sans ce drapeau, `afterFrame` retire le calque
    /// 0,35 s apres l'avoir affiche et les deux criteres deviennent non mesurables.
    private var pinned = false

    /// Ecran dont le display link pilote le drainage. Un seul, quel que soit le nombre
    /// de panneaux — voir `pump()`. Reelu a chaque reconstruction : si le pilote est
    /// debranche, le drainage s'arreterait en silence.
    private var pumpDisplayID: CGDirectDisplayID?

    /// Instants d'entree des evenements draines dans le cycle courant.
    /// Reserve une fois : le chemin de rendu ne doit pas reallouer par frame.
    private var stamps: [UInt64] = []
    /// Echantillons de latence dont l'horodatage materiel etait inutilisable.
    private(set) var latencyFallbacks: UInt64 = 0

    /// Delai de grace avant retrait, en secondes.
    ///
    /// Sans lui, relacher ⌥⌘ une fraction de seconde pour le represser ferait
    /// disparaitre puis reapparaitre le calque, avec un clignotement visible et un
    /// cout de composition a chaque aller-retour.
    private static let hideGrace: TimeInterval = 0.35
    private var hideWorkItem: DispatchWorkItem?

    func setUp() {
        stamps.reserveCapacity(8192)   // capacite du ring
        rebuildPanels()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { OverlayController.shared.rebuildPanels() }
            // Le contenu partageable en cache reference les anciens ecrans : sans ce
            // rafraichissement, le banc capturerait le mauvais ecran via son repli.
            Task.detached(priority: .utility) { await SnapshotBench.shared.warmUp() }
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

        // Le verrou remis a plat doit entrainer l'abandon du trait vivant, sinon il
        // reapparait au geste suivant et suit le curseur sans bouton enfonce.
        OptionGate.shared.onResetRequested = {
            DispatchQueue.main.async {
                OverlayController.shared.forEachView { $0.cancelLiveStroke() }
            }
        }
    }

    // MARK: - Drainage

    /// Unique consommateur du ring. Draine, diffuse a tous les panneaux, puis publie.
    ///
    /// Appele par le display link du panneau pilote, une fois par cycle.
    private func pump() {
        stamps.removeAll(keepingCapacity: true)
        let views = panels.values.map(\.inkView)

        InkRing.shared.drain { event in
            if event.eventKind == .down {
                // Une seule capture C11 par trait, quel que soit le nombre de panneaux :
                // diffuser cet appel lancerait N captures ScreenCaptureKit concurrentes
                // et fausserait l'etalonnage.
                self.strokeDidBegin(event)
            }
            for v in views { v.consume(event) }
            self.stamps.append(self.latencyOrigin(of: event))
        }

        guard !stamps.isEmpty else { afterFrame(); return }

        for v in views { v.commitFrame() }

        // T0.7 : un echantillon PAR EVENEMENT, apres le commit. Enregistrer le seul
        // `max(enqueuedTicks)` reviendrait a garder la plus PETITE latence du lot et
        // a jeter systematiquement le point le plus ancien — celui qui interesse un p95.
        let committedAt = SessionClock.hostTicksNow()
        for origin in stamps {
            LatencyHistogram.shared.record(millis: SessionClock.millis(from: origin, to: committedAt))
        }

        afterFrame()
    }

    /// Origine de la mesure de latence.
    ///
    /// T0.7 demande `CGEvent.timestamp`, ce qui inclut le segment materiel → livraison
    /// au tap, precisement celui qu'un tap insere en tete peut allonger. Mais un
    /// horodatage synthetique peut valoir zero ou pointer vers le futur : on ne le retient
    /// que s'il est anterieur a l'entree dans le callback, sinon on se replie sur celle-ci
    /// — sans ce garde, `millis(from:to:)` renverrait 0 et injecterait des echantillons
    /// nuls qui flatteraient le p95.
    private func latencyOrigin(of event: InkEvent) -> UInt64 {
        guard event.hostTicks != 0, event.hostTicks <= event.enqueuedTicks else {
            latencyFallbacks &+= 1
            return event.enqueuedTicks
        }
        return event.hostTicks
    }

    private func strokeDidBegin(_ event: InkEvent) {
        let stamped = SessionClock.shared.stamp(hostTicks: event.hostTicks)
        let requested = SessionClock.hostTicksNow()
        Task.detached(priority: .userInitiated) {
            await SnapshotBench.shared.capture(
                at: stamped.time, eventLocation: event.point, requestedAtTicks: requested
            )
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

        electPump()

        if visible { showPanels() }
        log.notice("panneaux reconstruits : \(self.panels.count) ecran(s), pilote \(self.pumpDisplayID ?? 0)")
    }

    /// Designe le panneau dont le display link draine le ring.
    ///
    /// Reelu a chaque reconstruction : si le pilote precedent etait porte par un ecran
    /// debranche, son display link a ete invalide et le drainage se serait arrete sans
    /// le moindre message.
    private func electPump() {
        for panel in panels.values { panel.inkView.onFrame = nil }
        let elected = panels[CGMainDisplayID()] ?? panels.values.first
        pumpDisplayID = elected?.displayID
        elected?.inkView.onFrame = { [weak self] in
            MainActor.assumeIsolated { self?.pump() }
        }
    }

    private func configure(_ panel: OverlayPanel, for screen: NSScreen) {
        // `onFrame` est cable par `electPump` : une seule vue pilote le drainage.
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
        guard !pinned else { hideWorkItem = nil; return }

        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Remis a nil AVANT les gardes : sans cela, un retrait annule laisse un
                // element consomme en place, `afterFrame` cesse de replanifier et le
                // filet de securite est desarme pour le reste de l'execution.
                self.hideWorkItem = nil
                // Ne jamais retirer sous un geste : entre la planification et
                // l'execution, l'utilisateur a pu represser le modificateur.
                guard !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
                guard !self.pinned else { return }
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

    /// Dernier filet si une transition de desarmement s'est perdue.
    private func afterFrame() {
        guard visible, !pinned, !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
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
    var isPinned: Bool { pinned }

    /// Nombre de traits d'UN panneau, pas la somme.
    ///
    /// Chaque panneau recoit tous les evenements et valide sa propre copie du trait
    /// (voir `pump`) : sommer rendrait N pour un seul geste sur N ecrans.
    var totalStrokes: Int { panels.values.map(\.inkView.strokeCount).max() ?? 0 }

    /// Plus long trait vivant observe, en points. Sert a trancher si la reconstruction
    /// integrale du chemin a chaque frame coute reellement quelque chose (§ 6.4).
    var maxLivePoints: Int { panels.values.map(\.inkView.maxLivePoints).max() ?? 0 }

    /// Epingle ou libere le calque, pour verifier C8 et C9 sans avoir a tracer.
    func debugToggle() {
        pinned.toggle()
        if pinned {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showPanels()
        } else if !OptionGate.shared.isArmed, !OptionGate.shared.isStroking {
            // Ne jamais arracher le calque sous un geste en cours : la porte continuerait
            // de capturer et l'utilisateur tracerait a l'aveugle.
            hidePanels()
        }
    }
}
