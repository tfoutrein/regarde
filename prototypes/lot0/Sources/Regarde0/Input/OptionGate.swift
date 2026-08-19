import CoreGraphics
import Foundation
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// La porte a verrou — specification § 6.2, ADR-0005
//
// C'est la piece qui decide, evenement par evenement, si un clic va a l'application
// testee ou au calque. Tout le produit repose dessus.
//
// Pourquoi un verrou et pas une simple lecture des modificateurs : l'utilisateur peut
// relacher ⌥⌘ EN PLEIN TRACE. Sans verrou, le mouseUp partirait a l'application testee
// alors qu'elle n'a jamais recu le mouseDown correspondant — elle se retrouverait avec
// un bouton enfonce qui ne se relache jamais, ou un drag fantome dans le Finder.
// C'est le critere C6.
//
// Symetriquement, `mouseDownInApp` retient qu'un clic a demarre DANS l'application :
// le drag et le mouseUp qui suivent doivent lui parvenir meme si l'utilisateur presse
// ⌥⌘ entre-temps.
//
// Un seul point de decision d'entree : `leftMouseDown`. Partout ailleurs, on ne fait
// que suivre l'etat etabli la.
// ─────────────────────────────────────────────────────────────────────────────

/// Mode global de la porte. Ecrit depuis le thread principal, lu depuis le thread du tap.
enum GateMode: UInt8, Sendable {
    /// La porte arbitre normalement.
    case active = 0
    /// Tout passe sans condition. Etat impose pendant la veille, Mission Control,
    /// le changement d'utilisateur — et par le mode securise de saisie.
    /// Un doute sur l'etat du systeme se resout TOUJOURS en faveur de l'application testee.
    case passthrough = 1
}

/// Ce que la porte a decide pour un evenement.
enum GateDecision: Sendable {
    /// L'evenement continue vers l'application testee.
    case pass
    /// L'evenement est consomme et devient de l'encre.
    case capture(InkEvent.Kind)
    /// L'evenement est consomme sans produire d'encre (touche de controle).
    case swallow
}

/// Rectangle de la fenetre cible, publie sans verrou.
///
/// Le callback du tap ne peut pas prendre de verrou (§ 6.2), et un `CGRect` fait
/// 32 octets — trop pour une seule operation atomique. D'ou ce double tampon : le
/// thread principal ecrit dans le slot inactif puis bascule l'index ; le tap lit
/// l'index puis le slot. Le pire cas est de lire un rectangle d'une generation de
/// retard, ce qui est sans consequence.
private final class TargetRectBox: @unchecked Sendable {
    private var slots: (CGRect, CGRect) = (.infinite, .infinite)
    private let active = Atomic<UInt8>(0)

    func publish(_ rect: CGRect) {
        let next: UInt8 = active.load(ordering: .relaxed) == 0 ? 1 : 0
        if next == 0 { slots.0 = rect } else { slots.1 = rect }
        active.store(next, ordering: .releasing)
    }

    @inline(__always)
    func read() -> CGRect {
        active.load(ordering: .acquiring) == 0 ? slots.0 : slots.1
    }
}

final class OptionGate: @unchecked Sendable {
    static let shared = OptionGate()

    // ── Etat partage (ecrit hors du tap) ─────────────────────────────────────
    private let mode = Atomic<UInt8>(GateMode.active.rawValue)
    private let targetRect = TargetRectBox()
    /// Modificateur d'armement. ⌥⌘ par defaut (ADR-0006), configurable.
    private let armingFlags = Atomic<UInt64>(
        UInt64(CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue)
    )

    // ── Etat du verrou (thread du tap EXCLUSIVEMENT) ─────────────────────────
    // Ces deux variables ne sont touchees que dans `decide`, appele depuis le seul
    // thread du tap. Aucune synchronisation n'est necessaire, et en ajouter une
    // couterait le budget du callback.
    private var strokeActive = false
    private var mouseDownInApp = false

    // ── Observabilite ────────────────────────────────────────────────────────
    private let capturedCount = Atomic<UInt64>(0)
    private let passedCount = Atomic<UInt64>(0)
    /// Passe a vrai des qu'un tracé est en cours ; lu par le thread principal pour
    /// ordonner le calque a l'ecran (ADR-0010).
    private let strokeFlag = Atomic<Bool>(false)
    /// Modificateur tenu, curseur dans la cible : le HUD peut afficher « arme ».
    private let armedFlag = Atomic<Bool>(false)
    /// Remise a plat demandee depuis un autre thread, consommee par le thread du tap.
    ///
    /// `strokeActive` et `mouseDownInApp` appartiennent au thread du tap et a lui seul.
    /// Les ecrire depuis le thread principal serait une course — precisement le genre de
    /// defaut que ce lot doit eliminer, pas introduire. Le drapeau est donc leve ici et
    /// consomme la-bas, au debut du prochain evenement traite.
    private let pendingReset = Atomic<Bool>(false)

    /// Notifie un changement d'armement ou de tracé, depuis le thread du tap.
    ///
    /// C'est le SEUL franchissement de frontiere autorise depuis le chemin critique, et
    /// il n'a lieu qu'aux transitions — quelques fois par seconde au pire, jamais par
    /// point. Le § 6.4 interdit `DispatchQueue.main.async` par point ; il ne l'interdit
    /// pas a la pression du modificateur, et c'est ce qui permet d'ordonner le calque
    /// AVANT le premier `mouseDown`, sans aucun polling au repos.
    var onStateChanged: (@Sendable (_ armed: Bool, _ stroking: Bool) -> Void)?

    // MARK: - Configuration (thread principal)

    var currentMode: GateMode {
        get { GateMode(rawValue: mode.load(ordering: .acquiring)) ?? .active }
        set { mode.store(newValue.rawValue, ordering: .releasing) }
    }

    /// Cadre de la fenetre testee, en coordonnees `CGEvent.location`.
    /// `.infinite` au lot 0 : l'ancrage reel vient au lot 2 (§ 6.3).
    func setTargetRect(_ rect: CGRect) { targetRect.publish(rect) }

    var isStroking: Bool { strokeFlag.load(ordering: .acquiring) }
    var isArmed: Bool { armedFlag.load(ordering: .acquiring) }
    var captured: UInt64 { capturedCount.load(ordering: .relaxed) }
    var passed: UInt64 { passedCount.load(ordering: .relaxed) }

    // MARK: - Decision (thread du tap, chemin critique)

    /// Decide du sort d'un evenement souris.
    ///
    /// Transcription directe du § 6.2. Toute divergence ici est une divergence du produit.
    @inline(__always)
    func decide(type: CGEventType, flags: CGEventFlags, location: CGPoint) -> GateDecision {
        consumePendingReset()

        guard currentMode != .passthrough else {
            passedCount.wrappingAdd(1, ordering: .relaxed)
            return .pass
        }

        let required = CGEventFlags(rawValue: armingFlags.load(ordering: .relaxed))
        let armed = flags.isSuperset(of: required) && targetRect.read().contains(location)

        var capture = strokeActive
        var kind = InkEvent.Kind.drag

        switch type {
        case .leftMouseDown:
            // LE seul point de decision d'entree. Ce qui est decide ici tient jusqu'au mouseUp.
            capture = armed && !mouseDownInApp
            strokeActive = capture
            mouseDownInApp = !capture
            kind = .down

        case .leftMouseUp:
            // Le verrou tient jusqu'ici, modificateur relache ou non. C'est C6.
            capture = strokeActive
            strokeActive = false
            mouseDownInApp = false
            kind = .up

        case .leftMouseDragged:
            capture = strokeActive
            kind = .drag

        case .mouseMoved:
            // Consomme uniquement pour dessiner le reticule pendant la visee.
            capture = armed && !mouseDownInApp
            kind = .drag

        default:
            break
        }

        publishState(armed: armed, stroking: strokeActive)

        guard capture else {
            passedCount.wrappingAdd(1, ordering: .relaxed)
            return .pass
        }
        capturedCount.wrappingAdd(1, ordering: .relaxed)
        return .capture(kind)
    }

    /// Publie l'etat et ne notifie qu'aux TRANSITIONS.
    ///
    /// `exchange` renvoie l'ancienne valeur : comparer avant de notifier evite de
    /// reveiller le thread principal a chaque `mouseMoved`, ce qui reintroduirait
    /// exactement le cout que le ring lock-free supprime.
    @inline(__always)
    private func publishState(armed: Bool, stroking: Bool) {
        let wasArmed = armedFlag.exchange(armed, ordering: .acquiringAndReleasing)
        let wasStroking = strokeFlag.exchange(stroking, ordering: .acquiringAndReleasing)
        if wasArmed != armed || wasStroking != stroking {
            onStateChanged?(armed, stroking)
        }
    }

    /// Reagit a un changement de modificateurs hors evenement souris.
    ///
    /// Sert a savoir si le calque doit etre ordonne a l'ecran, sans rien consommer :
    /// `flagsChanged` doit TOUJOURS passer, sous peine de laisser l'application testee
    /// avec une vision fausse de l'etat du clavier.
    @inline(__always)
    func noteFlagsChanged(_ flags: CGEventFlags, location: CGPoint) {
        consumePendingReset()

        guard currentMode != .passthrough else {
            publishState(armed: false, stroking: strokeActive)
            return
        }
        let required = CGEventFlags(rawValue: armingFlags.load(ordering: .relaxed))
        let armed = flags.isSuperset(of: required) && targetRect.read().contains(location)
        publishState(armed: armed, stroking: strokeActive)
    }

    /// Annule le tracé en cours sans laisser l'application testee dans un etat incoherent.
    ///
    /// Appele par `Échap` (§ 6.3). Le mouseUp qui suivra sera consomme puisque
    /// `strokeActive` etait vrai jusqu'ici — c'est voulu : l'application n'a pas vu le
    /// mouseDown, elle ne doit pas voir le mouseUp.
    @inline(__always)
    func cancelStroke() {
        strokeActive = false
        strokeFlag.store(false, ordering: .releasing)
    }

    /// Demande la remise a plat du verrou. Appelable depuis n'importe quel thread.
    ///
    /// Utilise a l'entree en `passthrough`, pour ne pas conserver un tracé actif au reveil.
    /// La remise a plat effective a lieu sur le thread du tap, au prochain evenement.
    func requestReset() {
        pendingReset.store(true, ordering: .releasing)
        strokeFlag.store(false, ordering: .releasing)
        armedFlag.store(false, ordering: .releasing)
    }

    /// Consomme une demande de remise a plat. Thread du tap uniquement.
    @inline(__always)
    private func consumePendingReset() {
        // `exchange` plutot que load+store : deux demandes rapprochees ne peuvent pas
        // en perdre une, et le cas courant reste une seule lecture atomique.
        if pendingReset.exchange(false, ordering: .acquiring) {
            strokeActive = false
            mouseDownInApp = false
        }
    }
}
