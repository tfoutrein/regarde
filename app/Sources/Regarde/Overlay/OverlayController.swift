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
                // Le moteur ferme les flux des écrans disparus IMMÉDIATEMENT.
                // Attendre la fin de session les fermerait au milieu de la
                // finalisation des autres, où une erreur emporterait des segments
                // complets (§ 5.5).
                let presents = Set(OverlayController.shared.geometry.screens
                                    .map { CGDirectDisplayID($0.displayID) })
                Task { await CaptureEngine.shared.synchroniser(avec: presents) }
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
                case .saisie(let frappe):
                    self.frapper(frappe)
                case .saisieValidee:
                    self.validerLaNote()
                case .saisieAbandonnee:
                    self.abandonnerLaNote()
                case .chiffre(let rang, let shift):
                    self.chiffre(rang: rang, shift: shift)
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

    /// La fenêtre de parole retient le calque (§ 6.1) : il n'est retiré qu'à
    /// SA fermeture, pas au relâchement de ⌥⌘ — changement assumé face aux
    /// lots 2-4. Sans voix disponible, aucune fenêtre ne retient rien et le
    /// comportement d'avant est intact.
    private var calqueRetenu = false

    func retenirLeCalque(_ retenir: Bool) {
        guard calqueRetenu != retenir else { return }
        calqueRetenu = retenir
        // Le calque est exclu de toute capture d'écran (R12) : seule cette
        // trace permet à la recette de VOIR qu'il a été retenu.
        Journal.event(.system, retenir ? "calque — retenu par la fenêtre de parole"
                                       : "calque — libéré, la fenêtre de parole est close")
        if retenir {
            hideWorkItem?.cancel()
            hideWorkItem = nil
        } else if !OptionGate.shared.isArmed, !OptionGate.shared.isStroking {
            scheduleHide()
        }
    }

    /// Le badge de la marque courante pulse tant que sa fenêtre vit (§ 2.2).
    func pulser(marque: Int?) {
        forEachPanel { $0.inkView.setPulse(marque) }
    }

    private func gateStateChanged(armed: Bool, stroking: Bool) {
        if armed || stroking {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            showPanels()
        } else if !calqueRetenu {
            scheduleHide()
        }
        // Le mode éclair publie au relâchement du modificateur, et lui seul le sait.
        SessionCoordinator.shared.modifierChanged(armed: armed || stroking)
    }

    // MARK: - La note texte (S70)

    /// Entre en saisie : l'ancre est posée, le clavier est détourné.
    func commencerLaNote(_ mark: Mark) {
        SaisieTexte.shared.commencer()
        SaisieEnCours.actif.store(true, ordering: .relaxed)
        Journal.event(.mark, "\(mark.number) · note — saisie ouverte, ⏎ valide, ⎋ abandonne")
        rafraichirLeHUDDeSaisie()
    }

    private func frapper(_ frappe: EventTap.Frappe) {
        // L'événement est RECONSTRUIT ici, sur le MainActor : la frappe a
        // traversé la frontière, pas l'objet (S69).
        guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                              virtualKey: CGKeyCode(frappe.code), keyDown: true) else { return }
        e.flags = frappe.cgFlags
        SaisieTexte.shared.nourrir(e)
        // La note se dessine PENDANT la frappe : le mode silencieux doit se
        // voir, sans quoi rien ne distingue « je tape ma note » de « mon
        // clavier ne répond plus ».
        if let id = MarkStore.shared.marks.last?.displayID {
            MarkStore.shared.mettreAJourLaNote(SaisieTexte.shared.texte)
            redraw(id)
        }
        rafraichirLeHUDDeSaisie()
    }

    private func validerLaNote() {
        SaisieEnCours.actif.store(false, ordering: .relaxed)
        let texte = SaisieTexte.shared.terminer()
        guard let mark = MarkStore.shared.completerTexte(texte) else {
            Journal.event(.mark, "note vide — rien n'est posé, le numéro repart au pot")
            HUDWindow.shared.announce("Note vide", detail: "rien n'a été posé", duration: 2)
            redrawAll()
            return
        }
        Journal.event(.mark, "\(mark.number) · note · \(texte.count) caractère(s) · display \(mark.displayID)")
        HUDWindow.shared.announce("Marque \(mark.number) — note",
                                  detail: texte.prefix(40) + (texte.count > 40 ? "…" : ""), duration: 2)
        redraw(mark.displayID)
        VoixCoordinator.shared.trace(marque: mark.number, t: mark.t)
        Task.detached(priority: .userInitiated) {
            do { try await MarkCapture.shared.capture(mark: mark) } catch {
                await MainActor.run { Journal.warn(.capture, "marque \(mark.number) — \(error)") }
            }
        }
    }

    private func abandonnerLaNote() {
        SaisieEnCours.actif.store(false, ordering: .relaxed)
        SaisieTexte.shared.abandonner()
        if MarkStore.shared.abandonnerNote() {
            Journal.event(.mark, "note abandonnée — le numéro repart au pot")
        }
        redrawAll()
        HUDWindow.shared.announce("Note abandonnée", detail: "⎋", duration: 2)
    }

    private func rafraichirLeHUDDeSaisie() {
        let texte = SaisieTexte.shared.texte
        HUDWindow.shared.announce("Note : \(texte.isEmpty ? "…" : texte)",
                                  detail: "⏎ valide · ⎋ abandonne", duration: 3600)
    }

    /// `⌥⌘ + chiffre` : le sens se décide ICI, où la marque attachée à la
    /// fenêtre de parole est connue (§ 6.7).
    private func chiffre(rang: Int, shift: Bool) {
        let voix = VoixCoordinator.shared
        // La marque attachée : celle de la fenêtre de parole si elle en a une,
        // sinon — voix indisponible, micro refusé — la dernière posée, qui en
        // est l'approximation exacte tant qu'aucune fenêtre ne peut contenir
        // autre chose (le commentaire de MarkStore.apply le disait déjà).
        let attachee = voix.machine.marqueCourante
            ?? (voix.disponible ? nil : MarkStore.shared.marks.last?.number)
        // Le sens choisi est journalisé AVEC son discriminant : sans lui, un
        // chiffre qui ne fait pas ce qu'on attendait est indébogable — c'est
        // ce qui a fait chercher une heure pendant S65.
        let sens = DecisionChiffre.sens(rang: rang, shift: shift, marqueAttachee: attachee)
        Journal.event(.key, "⌥⌘\(shift ? "⇧" : "")\(rang) · marque attachée "
                      + (attachee.map { "\($0)" } ?? "aucune") + " → " + Self.libelle(sens))
        switch sens {
        case .retroactive(let secondes):
            let point = CGEvent(source: nil)?.location ?? .zero
            if let mark = MarkStore.shared.poserRetroactive(
                secondes: secondes, at: point, geometry: geometry) {
                Journal.event(.mark, "\(mark.number) · rétroactive à T−\(secondes) s · display \(mark.displayID)")
                voix.trace(marque: mark.number, t: mark.t)
                pulser(marque: voix.machine.marqueCourante)
                redraw(mark.displayID)
                HUDWindow.shared.announce("Marque \(mark.number) — T−\(secondes) s",
                                          detail: "l'image vient de l'instant désigné", duration: 2)
                Task.detached(priority: .userInitiated) {
                    do { try await MarkCapture.shared.capture(mark: mark) } catch {
                        await MainActor.run { Journal.warn(.capture, "marque \(mark.number) — \(error)") }
                    }
                }
            } else {
                Journal.warn(.mark, "rétroactive T−\(secondes) s refusée — le curseur n'est sur aucun écran annotable")
            }
        case .intention(let intention):
            switch MarkStore.shared.apply(intention) {
            case .applied(let number, let intention):
                Journal.event(.mark, "\(number) · \(intention.label)")
                HUDWindow.shared.announce("Marque \(number) — \(intention.label)",
                                          detail: "⌥⌘ + 1..6", duration: 2)
            case .noMark, .muted:
                Journal.warn(.mark, "intention \(intention.rawValue) sans marque à qualifier")
                HUDWindow.shared.announce("Aucune marque à qualifier",
                                          detail: "Trace d'abord, qualifie ensuite", duration: 2)
            }
        case .horsPalette(let rang):
            Journal.event(.key, "chiffre \(rang) sans effet — la palette s'arrête à 6")
            HUDWindow.shared.announce("\(rang) — hors palette",
                                      detail: "Les intentions vont de 1 à 6", duration: 2)
        case .reaffecter(let marque):
            guard MarkStore.shared.marks.contains(where: { $0.number == marque }) else {
                Journal.warn(.mark, "réaffectation vers la marque \(marque) — elle n'existe pas")
                HUDWindow.shared.announce("Aucune marque \(marque)",
                                          detail: "la réaffectation vise une marque posée", duration: 2)
                return
            }
            voix.reaffecter(marque: marque)
        case .enGlobal:
            voix.basculerEnGlobal()
        case .aucun:
            break
        }
    }

    /// Le sens d'un chiffre, en français — le journal se lit sans le code.
    private static func libelle(_ sens: DecisionChiffre.Sens) -> String {
        switch sens {
        case .retroactive(let n): "marque rétroactive à T−\(n) s"
        case .intention(let i): "intention « \(i.label) »"
        case .horsPalette(let n): "\(n) hors palette"
        case .reaffecter(let m): "réaffectation à la marque \(m)"
        case .enGlobal: "bascule en commentaire général"
        case .aucun: "aucun effet"
        }
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
            store.beginStroke(at: event.point, geometry: geometry,
                              hostTicks: event.hostTicks, snapshot: event.snapshot)
        case .drag:
            // Un `mouseMoved` sans tracé en cours ne doit rien allonger : il n'y a pas
            // de bouton enfoncé, c'est de la visée.
            guard store.hasLiveStroke else { return }
            store.extendStroke(to: event.point, geometry: geometry)
            VoixCoordinator.shared.mouvement()
        case .up:
            guard store.hasLiveStroke else { return }
            store.extendStroke(to: event.point, geometry: geometry)
            if let mark = store.endStroke() {
                // Une NOTE n'est pas finie au relâchement : l'ancre est posée,
                // le texte s'écrit maintenant (S70, § 7.4).
                if case .text = mark.shape {
                    commencerLaNote(mark)
                    if let id = store.marks.last?.displayID { touched.insert(id) }
                    return
                }
                Journal.event(.mark, "\(mark.number) · \(mark.tool.label) · display \(mark.displayID)")
                // La fenêtre de parole apprend sa marque — le premier mot
                // prononcé avant ce tracé lui appartient déjà (§ 3.5).
                VoixCoordinator.shared.trace(marque: mark.number, t: mark.t)
                pulser(marque: VoixCoordinator.shared.machine.marqueCourante)
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

        // Les écrans écartés sont NOMMÉS à chaque reconstruction. Un écran
        // silencieusement absent donne un ⌥⌘-glisser qui trace, un numéro qui
        // s'incrémente, et un dossier où l'image manque — panne découverte en
        // relisant le rapport, quand la scène a disparu.
        for ecarte in Self.currentGeometry().refuses {
            Journal.warn(.system, "écran \(ecarte.displayID) écarté — \(ecarte.refus!)")
        }

        // Et les écrans que NSScreen ne montre PLUS DU TOUT — S43 terdecies.
        //
        // En recopie vidéo, macOS retire l'écran copieur de `NSScreen.screens` :
        // la boucle ci-dessus tourne sur une liste où il n'est déjà plus, et il
        // disparaissait sans être nommé. Mesuré le 23 août : au passage en
        // recopie, le bloc PANNEAUX tombait à un seul écran sans un mot sur le
        // second — la ligne « écarté — recopie vidéo » que la recette attendait ne
        // pouvait pas exister, la détection étant branchée sur une énumération qui
        // cache précisément ce qu'elle devait détecter.
        //
        // Core Graphics, lui, voit encore ces écrans. On l'interroge SÉPARÉMENT,
        // pour le journal seulement : injecter un fantôme dans la géométrie serait
        // pire — `screen(containingEvent:)` pourrait le trouver sous un geste
        // légitime, l'écran copieur partageant ses coordonnées avec la source.
        var enLigne = [CGDirectDisplayID](repeating: 0, count: 16)
        var nEnLigne: UInt32 = 0
        if CGGetOnlineDisplayList(16, &enLigne, &nEnLigne) == .success {
            let visibles = Set(NSScreen.screens.map { OverlayPanel.displayID(of: $0) })
            for id in enLigne.prefix(Int(nEnLigne)) where !visibles.contains(id) {
                if let refus = ScreenInfo.refus(
                    rotation: Double(CGDisplayRotation(id)),
                    dansJeuDeRecopie: CGDisplayIsInMirrorSet(id) != 0,
                    recopieDe: CGDisplayMirrorsDisplay(id)) {
                    Journal.warn(.system, "écran \(id) écarté — \(refus)")
                }
            }
        }

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
            let id = OverlayPanel.displayID(of: screen)
            // Les trois questions à Core Graphics sont posées ICI, à la frontière,
            // et leur RÉPONSE traverse sous forme de donnée. La décision, elle,
            // est une fonction pure — donc vérifiable sur un écran en rotation
            // portrait, ce qu'on ne met pas en place pour lancer un test.
            return ScreenInfo(displayID: id,
                              cocoaFrame: screen.frame,
                              scale: screen.backingScaleFactor,
                              refus: ScreenInfo.refus(
                                rotation: Double(CGDisplayRotation(id)),
                                dansJeuDeRecopie: CGDisplayIsInMirrorSet(id) != 0,
                                recopieDe: CGDisplayMirrorsDisplay(id)))
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
