import Foundation
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// Codes de touches des outils, résolus hors du callback du tap
//
// Les lettres se résolvent par CARACTÈRE (ADR-0021), donc via `UCKeyTranslate` sur la
// disposition courante — une opération qui alloue et qui touche des dictionnaires. La
// faire dans le callback violerait le budget du § 6.2 : zéro allocation, zéro verrou.
// Un dépassement déclenche `kCGEventTapDisabledByTimeout` et la bascule cesse en
// silence, ce qui est le risque R9.
//
// La résolution a donc lieu au démarrage et à chaque changement de disposition ; le
// callback ne fait que comparer quatre entiers.
//
// Quatre atomiques indépendantes plutôt qu'un instantané cohérent : une frappe qui
// tomberait pile pendant un changement de disposition pourrait lire un code neuf et un
// code ancien. Sans conséquence — au pire un outil ne répond pas à cette frappe-là —
// alors qu'un verrou dans le callback serait, lui, une vraie panne.
// ─────────────────────────────────────────────────────────────────────────────

final class ToolKeyCache: Sendable {
    static let shared = ToolKeyCache()

    // `-1` signifie « non résolu » : aucun code réel ne vaut −1, donc l'outil est
    // simplement inerte au clavier plutôt que d'atterrir sur la mauvaise touche.
    //
    // Quatre champs nommés et non un tableau : `Atomic` est non copiable, ce qu'un
    // `Array` exige. La contrainte du langage rejoint ici celle du callback — pas
    // d'indirection, pas de vérification de borne, quatre chargements directs.
    private let arrow = Atomic<Int64>(-1)
    private let rect = Atomic<Int64>(-1)
    private let point = Atomic<Int64>(-1)
    private let highlight = Atomic<Int64>(-1)

    /// Résout une première fois et se réabonne aux changements de disposition.
    ///
    /// Sans ce réabonnement, basculer d'AZERTY vers QWERTY en cours de session laisserait
    /// les quatre touches sur les codes de l'ancienne disposition — donc `⌥⌘C` ouvrirait
    /// le point plutôt que le cadre, sans rien signaler.
    func start() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: .keyboardLayoutChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Re-résout les quatre touches. Appelé hors du callback, sur le thread principal.
    ///
    /// Quatre lignes explicites : une fonction qui RENVERRAIT l'atomique à écrire ne
    /// compile pas — un type non copiable ne se retourne pas depuis une propriété
    /// empruntée. La répétition est le prix de la garantie.
    func refresh() {
        // La résolution passe par `KeyboardLayout.keyCode(for:)` — l'appel DIRECT à
        // `UCKeyTranslate` — et non par la table partagée.
        //
        // La table ne contient que les caractères qu'on a pensé à lui déclarer au
        // démarrage. Ajouter un cinquième outil sans toucher cette liste laisserait sa
        // touche muette, sans erreur et sans trace : le genre de dépendance qui ne se
        // voit qu'à l'usage. Ici, ajouter un cas à `MarkTool` suffit.
        func code(_ tool: MarkTool) -> Int64 {
            KeyboardLayout.keyCode(for: tool.key) ?? -1
        }
        arrow.store(code(.arrow), ordering: .relaxed)
        rect.store(code(.rect), ordering: .relaxed)
        point.store(code(.point), ordering: .relaxed)
        highlight.store(code(.highlight), ordering: .relaxed)
    }

    /// Outil associé à un code physique. Quatre comparaisons, aucune allocation.
    @inline(__always)
    func tool(forCode code: Int64) -> MarkTool? {
        guard code >= 0 else { return nil }
        if arrow.load(ordering: .relaxed) == code { return .arrow }
        if rect.load(ordering: .relaxed) == code { return .rect }
        if point.load(ordering: .relaxed) == code { return .point }
        if highlight.load(ordering: .relaxed) == code { return .highlight }
        return nil
    }
}
