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
        onStateChanged?(next)
        return true
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
        onStateChanged?(state)
    }

    func resumeFromSuspension() {
        guard state == .suspended else { return }
        transition(to: .idle)
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
