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
            Journal.write("⌃⌥S ignoré — déjà en \(state.rawValue)")
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

        guard let target = TargetWindow.shared.acquire() else {
            HUDWindow.shared.announce("Aucune fenêtre à annoter",
                                      detail: "Mets l'application au premier plan, puis ⌃⌥S",
                                      duration: 3)
            transition(to: .idle)
            return
        }

        MarkStore.shared.reset()
        sessionDirectory = try? SessionPaths.makeSessionDirectory()
        Task { await MarkCapture.shared.reset() }
        OptionGate.shared.currentMode = .active
        transition(to: .recording)
        HUDWindow.shared.announce("Session ouverte — \(target.name)",
                                  detail: "⌥⌘ + glisser pour tracer", duration: 3)
    }

    /// Termine la session. `⌃⌥F`. La publication des artefacts arrive en S27.
    func closeSession() {
        guard state == .recording else {
            Journal.write("⌃⌥F ignoré — aucune session en cours (\(state.rawValue))")
            return
        }
        let count = MarkStore.shared.count
        transition(to: .finalizing)

        // La porte se ferme AVANT tout le reste. Tant qu'elle est ouverte, un ⌥⌘-clic
        // pendant la finalisation créerait une marque que personne ne publierait.
        OptionGate.shared.currentMode = .passthrough
        TargetWindow.shared.release()

        Journal.section("Marques de la session", MarkStore.shared.describe())

        // Les marques encore présentes, avec leur intention. Ce dictionnaire EST le
        // filtre : une marque supprimée par ⌘Z n'y figure pas, donc son recadrage est
        // jeté sans avoir jamais touché le disque.
        var keep: [Int: String?] = [:]
        for mark in MarkStore.shared.marks { keep[mark.number] = mark.intention?.label }
        let directory = sessionDirectory
        sessionDirectory = nil

        transition(to: .publishing)
        Task {
            var written = 0
            if let directory {
                do {
                    let frames = try await MarkCapture.shared.finalize(
                        keeping: keep, into: SessionPaths.frames(of: directory))
                    written = frames.count
                } catch {
                    await MainActor.run { Journal.write("⚠ gravure : \(error)") }
                }
            }
            await MainActor.run {
                Journal.write("\(written) image\(written > 1 ? "s" : "") écrite"
                              + (written > 1 ? "s" : "")
                              + (directory.map { " dans \($0.path)" } ?? ""))
                self.transition(to: .idle)
                HUDWindow.shared.announce(
                    "Session terminée — \(count) marque\(count > 1 ? "s" : "")",
                    detail: directory?.lastPathComponent ?? "aucun artefact", duration: 4)
            }
        }
    }

    /// Force l'etat `suspended` sans passer par la validation.
    ///
    /// Utilise pour les evenements systeme — veille, verrouillage, changement
    /// d'utilisateur. Un doute sur l'etat du systeme se resout TOUJOURS en faveur de
    /// l'application testee : on suspend d'abord, on s'explique ensuite.
    func forceSuspend(reason: String) {
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
