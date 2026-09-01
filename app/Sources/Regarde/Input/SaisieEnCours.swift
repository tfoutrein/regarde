import Foundation
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// L'indicateur de saisie — S70
//
// Le tap doit savoir, sur son propre thread et sans attente, si une note est en
// cours de saisie : c'est la première question qu'il pose à chaque frappe. Un
// atomique, comme la fenêtre de grâce du porteur (S54) — une charge et une
// comparaison, le budget du callback ne bouge pas (R9).
// ─────────────────────────────────────────────────────────────────────────────

enum SaisieEnCours {
    static let actif = Atomic<Bool>(false)
}
