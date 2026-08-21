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

        // Le tap notifie les transitions d'armement, jamais chaque point : c'est ce qui
        // permet d'ordonner le calque AVANT le premier mouseDown, sans aucun polling au
        // repos. Le § 6.4 interdit un réveil du thread principal par point, pas à la
        // pression du modificateur.
        OptionGate.shared.onStateChanged = { armed, stroking in
            DispatchQueue.main.async {
                OverlayController.shared.gateStateChanged(armed: armed, stroking: stroking)
            }
        }

        // Le verrou remis à plat doit entraîner l'abandon du trait vivant, sinon il
        // réapparaît au geste suivant et suit le curseur sans bouton enfoncé.
        OptionGate.shared.onResetRequested = {
            DispatchQueue.main.async {
                MarkStore.shared.cancelStroke()
                OverlayController.shared.redrawAll()
            }
        }

        EventTap.shared.onControlKey = { key in
            DispatchQueue.main.async {
                // Le ring est vidé AVANT de traiter la touche, et c'est indispensable.
                //
                // Les événements souris traversent le ring et n'atteignent le modèle
                // qu'au prochain tick du display link — jusqu'à 8 ms plus tard. Les
                // touches, elles, arrivent directement par ce chemin. Sans ce drainage,
                // relâcher le bouton et frapper un chiffre dans la foulée — le geste
                // naturel, puisque ⌥⌘ est déjà tenu — appliquerait l'intention à la
                // marque PRÉCÉDENTE, celle d'avant le tracé qu'on vient de finir.
                //
                // Le symptôme n'est pas une panne : c'est un rapport faux, où chaque
                // marque porte l'intention de sa voisine. Le décalage a été observé sur
                // la première exécution du scénario S20-S23, quatre intentions sur
                // quatre décalées d'un cran.
                OverlayController.shared.pump()

                switch key {
                case .escape:
                    MarkStore.shared.cancelStroke()
                case .undo:
                    if let removed = MarkStore.shared.undoLast() {
                        Journal.event(.mark, "\(removed.number) · supprimée, le numéro est rendu")
                    }
                case .selectTool(let tool):
                    MarkStore.shared.tool = tool
                    Journal.event(.tool, tool.label)
                    HUDWindow.shared.announce("Outil : \(tool.label)",
                                              detail: "⌥⌘ + F C P S", duration: 2)
                case .intention(let intention):
                    switch MarkStore.shared.apply(intention) {
                    case .applied(let number, let intention):
                        Journal.event(.mark, "\(number) · \(intention.label)")
                        HUDWindow.shared.announce("Marque \(number) — \(intention.label)",
                                                  detail: "⌥⌘ + 1..6", duration: 2)
                    case .noMark, .muted:
                        // Aucune marque à qualifier. Le dire, plutôt que de laisser
                        // l'utilisateur croire que sa frappe a porté.
                        Journal.warn(.mark, "intention \(intention.rawValue) sans marque à qualifier")
                        HUDWindow.shared.announce("Aucune marque à qualifier",
                                                  detail: "Trace d'abord, qualifie ensuite",
                                                  duration: 2)
                    }
                case .mutedDigit(let rank):
                    // Le chiffre a été avalé : la palette s'arrête à 6 (ADR-0021).
                    Journal.event(.key, "chiffre \(rank) sans effet — la palette s'arrête à 6")
                    HUDWindow.shared.announce("\(rank) — hors palette",
                                              detail: "Les intentions vont de 1 à 6",
                                              duration: 2)
                }
                OverlayController.shared.redrawAll()
            }
        }
    }

    // MARK: - Ordonnancement à la demande (ADR-0010)

    /// Délai de grâce avant retrait.
    ///
    /// Sans lui, relâcher ⌥⌘ une fraction de seconde pour le represser ferait
    /// disparaître puis réapparaître le calque, avec un clignotement visible et un coût
    /// de composition à chaque aller-retour.
    private static let hideGrace: TimeInterval = 0.35
    private var hideWorkItem: DispatchWorkItem?

    private func gateStateChanged(armed: Bool, stroking: Bool) {
        if armed || stroking {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showPanels()
        } else {
            scheduleHide()
        }
        // Le mode éclair publie au relâchement du modificateur, et lui seul le sait.
        SessionCoordinator.shared.modifierChanged(armed: armed || stroking)
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Remis à nil AVANT les gardes : sans cela, un retrait annulé laisse un
                // élément consommé en place et le filet est désarmé pour la suite.
                self.hideWorkItem = nil
                guard !OptionGate.shared.isArmed, !OptionGate.shared.isStroking else { return }
                self.hidePanels()
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideGrace, execute: item)
    }

    /// Relit l'état d'occlusion de chaque panneau et gèle ceux qui ne sont pas visibles.
    private func refreshOcclusion() {
        for panel in panels.values {
            panel.inkView.setFrozen(!panel.occlusionState.contains(.visible))
        }
    }

    // MARK: - Drainage et rendu

    /// Vue dont le display link pilote le drainage. Une seule, quel que soit le nombre
    /// de panneaux : `InkRing` est un ring à consommateur unique, et `drain` avance la
    /// queue. Avec un display link par écran, le premier déclenché emporterait tout et
    /// l'autre trouverait la file vide — un tracé sur deux ne dessinerait rien. C'est le
    /// défaut que la revue du lot 0 avait relevé.
    private var pumpDisplayID: CGDirectDisplayID?

    /// Instants d'entrée des événements drainés, pour la mesure de latence. Réservé une
    /// fois : le chemin de rendu ne doit pas réallouer par frame.
    private var stamps: [UInt64] = []
    private(set) var latencyFallbacks: UInt64 = 0

    /// Désigne le panneau dont le display link draine le ring.
    ///
    /// Réélu à chaque reconstruction : si le pilote était porté par un écran débranché,
    /// son display link a été invalidé et le drainage s'arrêterait sans le moindre message.
    private func electPump() {
        for panel in panels.values { panel.inkView.onFrame = nil }
        let elected = panels[CGMainDisplayID()] ?? panels.values.first
        pumpDisplayID = elected?.displayID
        elected?.inkView.startRendering()
        elected?.inkView.onFrame = { [weak self] in
            MainActor.assumeIsolated { self?.pump() }
        }

        // Le dégel est branché sur TOUS les panneaux, pas seulement sur celui qui draine.
        // Un écran où l'on ne trace pas ne reçoit aucun événement : sans ce rappel, il
        // garderait indéfiniment le dessin qu'il avait avant d'être masqué.
        for panel in panels.values {
            let id = panel.displayID
            panel.inkView.onThaw = { [weak self] in
                MainActor.assumeIsolated { self?.redraw(id) }
            }
        }
    }

    /// Unique consommateur du ring : draine, applique, publie.
    ///
    /// Appelé par le display link, et aussi à la main avant de traiter une touche de
    /// contrôle, pour que souris et clavier atteignent le modèle dans l'ordre où
    /// l'utilisateur les a produits.
    func pump() {
        stamps.removeAll(keepingCapacity: true)
        var touched = Set<CGDirectDisplayID>()

        InkRing.shared.drain { event in
            self.apply(event, touched: &touched)
            self.stamps.append(self.latencyOrigin(of: event))
        }

        guard !stamps.isEmpty else { return }

        // Un seul commit par écran touché, après tout le lot d'événements : c'est ce qui
        // remplace les mille réveils par seconde qu'un `async` par point produirait.
        for id in touched { redraw(id) }

        let committedAt = SessionClock.hostTicksNow()
        for origin in stamps {
            LatencyHistogram.shared.record(millis: SessionClock.millis(from: origin, to: committedAt))
        }
    }

    private func apply(_ event: InkEvent, touched: inout Set<CGDirectDisplayID>) {
        let store = MarkStore.shared
        switch event.eventKind {
        case .down:
            store.beginStroke(at: event.point, geometry: geometry)
        case .drag:
            // Un `mouseMoved` sans tracé en cours ne doit rien allonger : il n'y a pas
            // de bouton enfoncé, c'est de la visée.
            guard store.hasLiveStroke else { return }
            store.extendStroke(to: event.point, geometry: geometry)
        case .up:
            guard store.hasLiveStroke else { return }
            store.extendStroke(to: event.point, geometry: geometry)
            if let mark = store.endStroke() {
                Journal.event(.mark, "\(mark.number) · \(mark.tool.label) · display \(mark.displayID)")
                // La capture part MAINTENANT, sans attendre la fin de session : une
                // infobulle se referme, une animation se termine, un menu disparaît.
                // Capturer plus tard donnerait six images d'un même écran au repos, où
                // aucune des six marques n'aurait plus de sens.
                Task.detached(priority: .userInitiated) {
                    do {
                        try await MarkCapture.shared.capture(mark: mark)
                    } catch {
                        await MainActor.run {
                            Journal.warn(.capture, "marque \(mark.number) — \(error)")
                        }
                    }
                }
            }
        }
        if let id = store.liveDisplayID ?? store.marks.last?.displayID { touched.insert(id) }
    }

    /// Origine de la mesure de latence.
    ///
    /// `CGEvent.timestamp` inclut le segment matériel → livraison au tap, précisément
    /// celui qu'un tap inséré en tête peut allonger. Mais un horodatage synthétique peut
    /// valoir zéro ou pointer vers le futur : sans ce garde, la mesure renverrait 0 ms et
    /// flatterait le p95. Le lot 0 l'a établi.
    private func latencyOrigin(of event: InkEvent) -> UInt64 {
        guard event.hostTicks != 0, event.hostTicks <= event.enqueuedTicks else {
            latencyFallbacks &+= 1
            return event.enqueuedTicks
        }
        return event.hostTicks
    }

    /// Recompose les chemins d'un écran depuis le modèle.
    ///
    /// Le rendu dérive entièrement de `MarkStore` : la vue ne conserve aucun état propre,
    /// donc elle ne peut pas diverger du modèle.
    func redraw(_ displayID: CGDirectDisplayID) {
        guard let panel = panels[displayID] else { return }
        let size = panel.inkView.bounds.size
        let store = MarkStore.shared
        panel.inkView.setCommittedPaths(
            store.committedPaths(for: displayID, size: size, lineWidth: InkStyle.width))
        panel.inkView.setLivePaths(
            store.livePaths(for: displayID, size: size, lineWidth: InkStyle.width))
        panel.inkView.setBadges(store.badges(for: displayID, size: size))
    }

    func redrawAll() {
        for id in panels.keys { redraw(id) }
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
        electPump()

        // Les marques sont en coordonnées normalisées : elles suivent le changement de
        // résolution sans transformation.
        redrawAll()
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
        for panel in panels.values {
            panel.show()
            // Le panneau reprend l'état du MODÈLE à l'instant où il redevient visible.
            //
            // Il a pu être vidé pendant qu'il était masqué — c'est ce que fait une
            // publication — et un ordre de dessin adressé à une vue gelée est ignoré. Sans
            // cette resynchronisation, les marques déjà publiées réapparaissaient au
            // ré-armement, et ne s'effaçaient que sur l'écran où l'on recommençait à
            // tracer.
            panel.inkView.setFrozen(false)
        }
        redrawAll()
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
