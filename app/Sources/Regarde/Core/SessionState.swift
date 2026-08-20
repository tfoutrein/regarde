import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Cycle de vie d'une session — specification § 4
//
// La machine a etats est ecrite AVANT les fonctionnalites qui la peuplent, parce que
// tout le reste s'y accroche : le calque s'ordonne selon elle, la porte passe en
// passthrough selon elle, l'icone de la barre de menus la reflete, et les greffons
// contextuels ne sont interroges que dans certains de ses etats.
//
// Au lot 1, seuls `idle`, `preflight` et `blocked` sont reellement atteints. Les autres
// existent pour que leur place soit tenue et que les transitions soient ecrites une fois.
// ─────────────────────────────────────────────────────────────────────────────

enum SessionState: String, Sendable, CaseIterable {
    /// Aucune session. Le pre-roll peut tourner si l'utilisateur l'a active.
    case idle
    /// Verification des permissions, avant tout engagement. Doit rester sous 50 ms :
    /// c'est du preflight, jamais une demande — une invite volerait le focus.
    case preflight
    /// Le flux bascule en pleine resolution, le calque se prepare. 0,3 a 1,5 s.
    case arming
    /// Session ouverte : capture continue, marques et parole acceptees.
    case recording
    /// Arret du flux, drain de la transcription, extraction des frames. Budget : < 2 s.
    case finalizing
    /// Ecriture des artefacts, attribution du numero, presse-papiers.
    case publishing
    /// Suspendue par le systeme — veille, ecran verrouille, changement d'utilisateur.
    /// La porte est en passthrough : un doute se resout toujours en faveur de
    /// l'application testee.
    case suspended
    /// Une permission requise manque. Le doctor est atteignable, rien d'autre ne l'est.
    case blocked

    /// La porte doit-elle arbitrer, ou tout laisser passer ?
    var arbitrates: Bool {
        switch self {
        case .arming, .recording: true
        case .idle, .preflight, .finalizing, .publishing, .suspended, .blocked: false
        }
    }

    /// Etat porte par l'icone de la barre de menus.
    var indicator: Indicator {
        switch self {
        case .blocked: .fault
        case .idle, .preflight: .ready
        case .arming, .recording: .active
        case .finalizing, .publishing: .working
        case .suspended: .suspended
        }
    }

    enum Indicator: Sendable {
        case ready       // gris — au repos, tout va bien
        case active      // rouge — session en cours, l'ecran est enregistre
        case working     // ambre — traitement de fin de session
        case suspended   // gris barre — le systeme a suspendu
        case fault       // rouge plein — une permission manque, rien ne marchera
    }
}

/// Transition refusee, avec sa raison. Une transition impossible est un defaut de
/// logique, pas un cas d'usage : on veut le voir plutot que de le rattraper.
struct InvalidTransition: Error, CustomStringConvertible {
    let from: SessionState
    let to: SessionState
    var description: String { "transition refusée : \(from.rawValue) → \(to.rawValue)" }
}

extension SessionState {
    /// Transitions autorisees. Ecrites une fois, ici, plutot que dispersees en gardes
    /// dans le code appelant.
    func canTransition(to next: SessionState) -> Bool {
        switch (self, next) {
        // Ouverture
        case (.idle, .preflight), (.blocked, .preflight): true
        case (.preflight, .arming): true
        case (.preflight, .blocked): true        // une permission manque
        case (.preflight, .idle): true           // annulation
        case (.arming, .recording): true
        case (.arming, .idle): true              // echec du demarrage du flux

        // Fermeture
        case (.recording, .finalizing): true
        case (.finalizing, .publishing): true
        case (.publishing, .idle): true

        // Suspension : depuis tout etat vif, et retour vers idle uniquement —
        // une session interrompue par une veille ne reprend pas, elle se termine.
        case (.arming, .suspended), (.recording, .suspended),
             (.finalizing, .suspended), (.preflight, .suspended): true
        case (.suspended, .idle), (.suspended, .finalizing): true

        // Une permission peut tomber a tout moment.
        case (_, .blocked): true

        default: false
        }
    }
}
