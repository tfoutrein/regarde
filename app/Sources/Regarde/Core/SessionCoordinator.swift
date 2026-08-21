import AppKit
import Foundation
import os

let logSubsystem = "dev.tfoutrein.regarde"

// ─────────────────────────────────────────────────────────────────────────────
// SessionCoordinator — proprietaire du cycle de vie, arbitre des degradations
//
// Une seule piece decide de l'etat de la session. Tout le reste l'observe : c'est ce
// qui evite qu'un module se croie en session pendant qu'un autre l'a deja fermee.
//
// Au lot 1, il ne pilote encore ni capture ni calque. Il porte la machine a etats,
// l'observation de l'etat systeme, et la publication vers l'interface — c'est-a-dire
// exactement ce dont le doctor et la barre de menus ont besoin.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SessionCoordinator {
    static let shared = SessionCoordinator()

    private let log = Logger(subsystem: logSubsystem, category: "session")
    private(set) var state: SessionState = .idle

    /// Notifie tout changement d'etat. La barre de menus et le HUD s'y abonnent
    /// plutot que d'interroger en boucle.
    var onStateChanged: ((SessionState) -> Void)?

    /// Raison de l'etat `blocked`, affichee telle quelle par le doctor.
    private(set) var blockingReason: String?

    /// Répertoire de la session en cours. `nil` hors session.
    private(set) var sessionDirectory: URL?

    /// Nom de la cible et instant d'ouverture, pour le compte rendu de fin.
    private var sessionTarget: String?
    private var sessionStart: Date?

    // MARK: - Transitions

    @discardableResult
    func transition(to next: SessionState, reason: String? = nil) -> Bool {
        guard state.canTransition(to: next) else {
            // Une transition refusee est un defaut de logique. On la journalise en
            // erreur plutot que de l'absorber : la voir en developpement coute moins
            // cher que de la debusquer en session.
            log.error("\(InvalidTransition(from: self.state, to: next).description, privacy: .public)")
            return false
        }
        let previous = state
        state = next
        if next == .blocked { blockingReason = reason } else { blockingReason = nil }
        log.notice("état \(previous.rawValue, privacy: .public) → \(next.rawValue, privacy: .public)")
        publish(next)
        return true
    }

    // MARK: - Session d'annotation (lot 2)

    /// Ouvre une session. `⌃⌥S`.
    ///
    /// Trois étapes, dans cet ordre, parce que chacune peut échouer et qu'échouer tard
    /// coûte plus cher : le tap doit tourner, la cible doit exister, et seulement alors
    /// la porte s'ouvre. Une session ouverte sans cible armerait ⌥⌘ sur tout l'écran,
    /// donc sur l'éditeur — exactement ce que S22 existe pour empêcher.
    func openSession() {
        guard state == .idle || state == .blocked else {
            Journal.warn(.session, "⌃⌥S ignoré — déjà en \(state.rawValue)")
            return
        }
        guard transition(to: .preflight) else { return }

        guard EventTap.shared.isInstalled else {
            transition(to: .blocked, reason: "le tap n'est pas installé")
            // Le diagnostic s'ouvre de lui-même : dire « ça n'a pas marché » sans montrer
            // quelle permission manque laisserait l'utilisateur chercher.
            DoctorWindow.shared.show()
            return
        }

        guard transition(to: .arming) else { return }

        // L'origine de l'horloge est recalée ICI, et nulle part ailleurs.
        //
        // À l'entrée en `arming` : avant la première frame, avant la première marque,
        // et après que la session est certaine de s'ouvrir. Sans ce recalage,
        // l'origine resterait celle du lancement de l'application — une session
        // ouverte six heures plus tard donnerait à ses marques des `SessionTime` de
        // six heures, et `assetTime()` les clamperait toutes hors bornes sans qu'une
        // seule image ne soit extraite. Le bug serait muet : le journal dirait
        // « 6 marques », le dossier ne contiendrait rien.
        SessionClock.shared.rearm()

        // Le banc C11 s'arme avec la session, pas avant : son pont d'horloge doit
        // partager l'origine des marques qu'il mesure.
        if TestFlags.c11Bench {
            C11Bench.shared.marquerDebut()
            C11Bench.shared.demarrer()
        }

        // Le répertoire AVANT la cible, et son échec refuse la session.
        //
        // Avant la cible, parce qu'échouer après aurait laissé la cible figée sur une
        // session qui ne s'ouvre pas — constaté en la refusant pour de bon, avec
        // `chmod 500` sur ~/Regarde/sessions.
        //
        // Et un refus, pas un `try?`. Cette ligne était `sessionDirectory = try? …` : la
        // session s'ouvrait quand même, l'utilisateur posait ses marques, et à ⌃⌥F le
        // `if let directory` sautait toute la publication. Le journal disait « 0 image
        // écrite » sans un mot sur la cause, et quatre marques partaient à la poubelle.
        // Le mode éclair, lui, journalisait déjà son échec : l'asymétrie suffisait à
        // montrer que l'omission n'était pas un choix.
        let directory: URL
        do {
            directory = try SessionPaths.makeSessionDirectory()
        } catch {
            Journal.warn(.session, "répertoire impossible — \(error)")
            HUDWindow.shared.announce("Impossible d'écrire les artefacts",
                                      detail: SessionPaths.root.path, duration: 5)
            transition(to: .blocked, reason: "répertoire de session : \(error)")
            return
        }

        guard let target = TargetWindow.shared.acquire(announcing: false) else {
            HUDWindow.shared.announce("Aucune fenêtre à annoter",
                                      detail: "Mets l'application au premier plan, puis ⌃⌥S",
                                      duration: 3)
            transition(to: .idle)
            return
        }

        Journal.rule("SESSION · \(target.name)")
        Journal.event(.target, String(format: "figée — cadre (%.0f, %.0f) %.0f×%.0f",
                                      target.frame.minX, target.frame.minY,
                                      target.frame.width, target.frame.height))
        // Le mode éclair a pu programmer une publication : elle appartient aux marques
        // qu'on jette juste en dessous, pas à la session qui s'ouvre. Le modèle et le pot
        // sont déjà abandonnés ici — le minuteur est le troisième objet en vol, et le
        // seul endroit qui l'annulait, `modifierChanged`, sort sur sa garde d'état avant
        // d'y toucher. Sans cette ligne, ouvrir une session moins de 0,8 s après avoir
        // relâché ⌥⌘ fait publier la première marque de la SESSION dans un dossier
        // « ÉCLAIR » séparé, puis efface l'encre de l'écran en pleine session.
        flashWorkItem?.cancel()
        flashWorkItem = nil
        MarkStore.shared.reset()
        sessionDirectory = directory
        sessionTarget = target.name
        sessionStart = Date()
        Task { await MarkCapture.shared.reset() }
        OptionGate.shared.currentMode = .active
        transition(to: .recording)
        HUDWindow.shared.announce("Session ouverte — \(target.name)",
                                  detail: "⌥⌘ + glisser pour tracer", duration: 3)
    }

    /// Termine la session. `⌃⌥F`. La publication des artefacts arrive en S27.
    func closeSession() {
        guard state == .recording else {
            Journal.warn(.session, "⌃⌥F ignoré — aucune session en cours (\(state.rawValue))")
            return
        }
        let count = MarkStore.shared.count
        let target = sessionTarget ?? "?"
        let marked = MarkStore.shared.targets
        let seconds = sessionStart.map { Int(Date().timeIntervalSince($0).rounded()) }
        transition(to: .finalizing)

        // La cible est dégelée, pas relâchée : le mode éclair reprend la main dès la
        // session close, et ⌥⌘ doit continuer d'armer sur la fenêtre regardée.
        TargetWindow.shared.release()

        // Les marques encore présentes, avec leur intention. Ce dictionnaire EST le
        // filtre : une marque supprimée par ⌘Z n'y figure pas, donc son recadrage est
        // jeté sans avoir jamais touché le disque.
        let keep = MarkStore.shared.marks.map {
            MarkCapture.Keep(id: $0.id, number: $0.number, intention: $0.intention?.label)
        }
        let directory = sessionDirectory
        sessionDirectory = nil
        sessionTarget = nil
        sessionStart = nil

        // Le modèle est vidé MAINTENANT, avant toute reprise du mode éclair. Sans cela,
        // le premier relâchement de ⌥⌘ après la session republierait ses marques, dans
        // un second dossier, en double.
        // Écrit AVANT le vidage, faute de quoi la liste sort vide.
        Journal.list("MARQUES", MarkStore.shared.describe())

        MarkStore.shared.reset()
        OverlayController.shared.redrawAll()

        transition(to: .publishing)
        Task {
            var written = 0
            var overviews = 0
            if let directory {
                do {
                    let frames = try await MarkCapture.shared.finalize(
                        keeping: keep, into: SessionPaths.frames(of: directory))
                    if TestFlags.c11Bench {
                        await MainActor.run {
                            C11Bench.shared.arreter()
                            try? C11Bench.shared.ecrire(dans: SessionPaths.frames(of: directory))
                        }
                    }
                    // Comptés à part : une vue d'ensemble n'est pas le recadrage d'une
                    // marque, et les additionner déclencherait l'avertissement
                    // « marque sans image » à contresens.
                    written = frames.filter { $0.role == .crop }.count
                    overviews = frames.filter { $0.role == .overview }.count
                } catch {
                    await MainActor.run { Journal.warn(.capture, "gravure — \(error)") }
                }
            } else {
                // Ne peut plus arriver depuis que l'ouverture refuse un répertoire
                // manquant, mais se taire ici serait rejouer exactement le défaut qu'on
                // vient de corriger.
                await MarkCapture.shared.reset()
                await MainActor.run {
                    Journal.warn(.session, "aucun répertoire — \(keep.count) marque(s) perdue(s)")
                }
            }
            await MainActor.run {
                // Un bloc de FIN, et pas seulement une ligne de plus.
                //
                // Les sessions s'enchaînaient dans le journal sans rien pour les séparer :
                // impossible, en relisant, de dire où l'une finissait. Le compte rendu
                // répond aux quatre questions qu'on se pose alors — sur quoi, combien de
                // temps, combien de marques, et où sont les images.
                var pairs = [
                    ("cible", target),
                    ("durée", seconds.map { "\($0) s" } ?? "?"),
                    ("marques", "\(count)"),
                    ("recadrages", "\(written)"),
                    ("ensembles", "\(overviews)"),
                    ("dossier", directory?.lastPathComponent ?? "aucun"),
                ]
                if written != count {
                    pairs.append(("⚠", "\(count - written) marque(s) sans image"))
                }
                if marked.count > 1 {
                    pairs.append(("⚠", "réparties sur " + marked.joined(separator: ", ")))
                }

                // La durée MURALE à côté de la durée d'horloge, et l'écart nommé quand
                // il existe. `mach_absolute_time` s'arrête pendant la veille : une
                // session ouverte avant une mise en veille et fermée après annoncerait
                // sinon quelques minutes pour plusieurs heures.
                let murale = SessionClock.shared.wallSeconds()
                if let s = seconds, murale - Double(s) > 2 {
                    pairs.append(("veille", String(format: "%.0f s d'écart — durée murale %.0f s",
                                                   murale - Double(s), murale)))
                }

                // `fallbackCount` sans condition : zéro est une information, et c'est
                // celle qu'on veut lire en constatant qu'un appariement est flou.
                let replis = SessionClock.shared.fallbackCount
                pairs.append(("horodatages en repli", "\(replis)"))
                if replis > 0 {
                    pairs.append(("⚠", "horodatage matériel inutilisable — pilote tiers "
                                       + "ou événement synthétique (C12)"))
                }
                Journal.block("FIN DE SESSION", pairs)

                self.transition(to: .idle)
                HUDWindow.shared.announce(
                    "Session terminée — \(count) marque\(count > 1 ? "s" : "")",
                    detail: directory?.lastPathComponent ?? "aucun artefact", duration: 4)
            }
        }
    }

    // MARK: - Mode éclair (§ 2.1)

    private var flashWorkItem: DispatchWorkItem?

    /// Délai de grâce entre le relâchement de ⌥⌘ et la publication.
    ///
    /// Il existe pour la RAFALE : poser deux marques d'affilée demande de relâcher entre
    /// les deux, et publier au premier relâchement couperait l'observation en deux
    /// dossiers dont aucun ne serait complet. Assez long pour enchaîner sans y penser,
    /// assez court pour que le dossier soit là quand on va le chercher.
    static let flashGrace: TimeInterval = 0.8

    /// Le modificateur vient d'être pris ou relâché.
    func modifierChanged(armed: Bool) {
        // Une session explicite publie à ⌃⌥F, jamais au relâchement : c'est toute la
        // différence entre les deux modes.
        guard state == .idle else { return }

        if armed {
            flashWorkItem?.cancel()
            flashWorkItem = nil
            return
        }

        guard MarkStore.shared.count > 0 else { return }
        flashWorkItem?.cancel()
        let item = DispatchWorkItem { MainActor.assumeIsolated { self.publishFlash() } }
        flashWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashGrace, execute: item)
    }

    /// Publie une observation isolée : recadrages gravés, sans session ouverte.
    private func publishFlash() {
        flashWorkItem = nil
        let marks = MarkStore.shared.marks
        guard !marks.isEmpty else { return }

        let keep = marks.map {
            MarkCapture.Keep(id: $0.id, number: $0.number, intention: $0.intention?.label)
        }
        let count = marks.count
        let targets = MarkStore.shared.targets
        MarkStore.shared.reset(keepingTool: true)
        OverlayController.shared.redrawAll()

        Task {
            var written = 0
            var overviews = 0
            var directory: URL?
            do {
                let dir = try SessionPaths.makeSessionDirectory()
                directory = dir
                let frames = try await MarkCapture.shared.finalize(
                    keeping: keep, into: SessionPaths.frames(of: dir))
                written = frames.filter { $0.role == .crop }.count
                overviews = frames.filter { $0.role == .overview }.count
            } catch {
                await MainActor.run { Journal.warn(.capture, "mode éclair — \(error)") }
            }
            await MainActor.run {
                Journal.block("ÉCLAIR", [
                    ("marques", "\(count)"),
                    ("recadrages", "\(written)"),
                    ("ensembles", "\(overviews)"),
                    ("dossier", directory?.lastPathComponent ?? "aucun"),
                ])
                if targets.count > 1 {
                    // Hors session la cible suit l'application au premier plan : une
                    // rafale peut donc mélanger plusieurs applications sans que rien ne
                    // l'annonce. Le dire est le minimum ; voir si l'observation doit se
                    // couper d'elle-même reste ouvert.
                    Journal.warn(.session, "observation répartie sur \(targets.count) "
                                 + "applications : " + targets.joined(separator: ", "))
                }
                HUDWindow.shared.announce(
                    "\(count) marque\(count > 1 ? "s" : "") publiée\(count > 1 ? "s" : "")",
                    detail: directory?.lastPathComponent ?? "aucun artefact", duration: 3)
            }
        }
    }

    /// Force l'etat `suspended` sans passer par la validation.
    ///
    /// Utilise pour les evenements systeme — veille, verrouillage, changement
    /// d'utilisateur. Un doute sur l'etat du systeme se resout TOUJOURS en faveur de
    /// l'application testee : on suspend d'abord, on s'explique ensuite.
    func forceSuspend(reason: String) {
        // Ce qui est en vol est abandonné D'ABORD, et sans condition d'état.
        //
        // Le mode éclair vit ENTIÈREMENT à `.idle` — voir `modifierChanged`, qui sort
        // sur tout autre état. Une marque tracée hors session y laisse deux choses : un
        // recadrage dans le pot de `MarkCapture`, et une publication programmée 0,8 s
        // plus tard. L'ancienne garde sortait avant d'y toucher, si bien qu'un
        // verrouillage d'écran pendant une observation éclair laissait le recadrage
        // survivre au verrou et la publication partir derrière lui.
        //
        // C'est ce que l'ADR-0020 interdit, et l'exemption portait précisément sur le
        // mode majoritaire : un doute sur l'état du système se résout en faveur de
        // l'application testée à TOUT état, pas seulement pendant une session.
        //
        // C'est aussi la couture par laquelle le pré-roll s'arrêtera : il tourne au
        // repos, donc à `.idle`, donc sous une garde qui l'aurait ignoré.
        flashWorkItem?.cancel()
        flashWorkItem = nil
        // Les recadrages en attente n'iront nulle part, et les garder ferait ressortir
        // des images périmées dans une session ultérieure.
        Task { await MarkCapture.shared.reset() }

        // Le tracé EN COURS ne figure pas dans `count`, qui ne compte que les marques
        // POSÉES. C'est pourtant l'objet le plus en vol qui soit : un geste interrompu
        // par le verrou a déjà réservé son numéro et peint son encre. Sans cet appel il
        // survit au verrou, réapparaît au geste suivant en suivant le curseur sans
        // bouton enfoncé, et décale d'un tout le reste de la numérotation.
        //
        // `requestReset` est écrit pour ce cas exact : il remet le verrou du tap à plat
        // SANS rendre à l'application testée le milieu d'un clic dont elle a manqué le
        // début, et déclenche `cancelStroke` + `redrawAll` par `onResetRequested`.
        OptionGate.shared.requestReset()

        // La cible est dégelée ici, et non après la garde d'état.
        //
        // Une session suspendue ne reprend pas : `resumeFromSuspension` la ramène à
        // `.idle`, c'est donc une FIN de session, et une fin de session dégèle la cible
        // — exactement ce que fait `closeSession`. Sans cela `isPinned` reste vrai pour
        // toujours, `refreshTarget` sort sur sa garde à chaque tour, et le mode éclair
        // reste braqué sur la fenêtre d'une session morte : ⌥⌘ n'arme plus nulle part,
        // sans le moindre message. Le seul remède serait un ⌃⌥S suivi d'un ⌃⌥F.
        if TargetWindow.shared.isPinned { TargetWindow.shared.release() }

        let abandoned = MarkStore.shared.count
        if abandoned > 0 {
            Journal.warn(.session, "\(abandoned) marque(s) abandonnée(s) — \(reason)")
            MarkStore.shared.reset(keepingTool: true)
            OverlayController.shared.redrawAll()
        }

        // La transition d'état, elle, reste gardée. À `.idle` il n'y a pas de session à
        // suspendre, et publier `suspended` ferait dire à la barre de menus qu'une
        // session est interrompue alors qu'aucune n'était ouverte.
        guard state != .suspended, state != .idle else { return }
        let previous = state
        state = .suspended
        log.notice("suspension forcée depuis \(previous.rawValue, privacy: .public) — \(reason, privacy: .public)")
        publish(state)
    }

    func resumeFromSuspension() {
        guard state == .suspended else { return }
        transition(to: .idle)
    }

    /// Diffuse l'état à tout ce qui le reflète : barre de menus, HUD, et plus tard le
    /// calque. Un seul point de publication évite qu'un module se croie en session
    /// pendant qu'un autre l'a déjà fermée.
    private func publish(_ state: SessionState) {
        onStateChanged?(state)
        HUDWindow.shared.follow(state)
        NotificationCenter.default.post(name: .sessionStateChanged, object: state)
    }

    // MARK: - Observation de l'etat systeme

    func observeSystemState() {
        let dnc = DistributedNotificationCenter.default()
        let wnc = NSWorkspace.shared.notificationCenter

        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    SessionCoordinator.shared.forceSuspend(reason: name)
                }
            }
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            dnc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SessionCoordinator.shared.resumeFromSuspension() }
            }
        }

        let suspendOn: [NSNotification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in suspendOn {
            wnc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    SessionCoordinator.shared.forceSuspend(reason: name.rawValue)
                }
            }
        }

        let resumeOn: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in resumeOn {
            wnc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    SessionCoordinator.shared.resumeFromSuspension()
                    // Le reveil est le moment ou l'autorisation de capture a pu expirer.
                    // On la reverifie ici, hors de tout chemin de session (R1).
                    TCCContact.shared.refresh(trigger: .wake)
                }
            }
        }
    }

    // MARK: - Simulation, pour le critere de fin de S9

    /// Fait defiler les etats pour verifier que l'icone les reflete tous.
    /// N'existe qu'au lot 1 : elle disparait des que les vraies transitions arrivent.
    func runStateDemo() {
        let sequence: [SessionState] = [.preflight, .arming, .recording, .finalizing, .publishing, .idle]
        var delay = 0.0
        for s in sequence {
            delay += 1.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { _ = SessionCoordinator.shared.transition(to: s) }
            }
        }
    }
}
