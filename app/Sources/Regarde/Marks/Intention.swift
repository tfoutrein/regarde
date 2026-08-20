import Carbon.HIToolbox
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Palette d'intentions — spécification § 7.4, ADR-0021
//
// Six étiquettes qui couvrent la moitié des retours réels. Elles existent pour le mode
// silencieux : sans elles, une marque ne porterait AUCUN mot avant le lot 4, et le
// rapport se réduirait à des flèches numérotées — ce qui ne teste pas la promesse.
//
// Les touches sont désignées par leur CODE PHYSIQUE, à l'inverse des lettres.
//
// La raison est mesurée, pas supposée : sur un clavier AZERTY français, demander le code
// du caractère « 1 » renvoie 83 — le pavé numérique, absent de tout MacBook. La rangée du
// haut y produit `& é " ' ( -`. Une palette résolue par caractère serait donc
// inaccessible à un utilisateur français, ce qui est précisément le cas d'usage de départ.
// Les codes physiques, eux, ne bougent pas d'une disposition à l'autre.
// ─────────────────────────────────────────────────────────────────────────────

enum Intention: Int, CaseIterable, Sendable, Codable {
    case misaligned = 1
    case error = 2
    case missingState = 3
    case slow = 4
    case textToFix = 5
    case broken = 6

    /// Libellé, tel qu'il apparaît dans le rapport et sur le badge.
    var label: String {
        switch self {
        case .misaligned: "mal aligné"
        case .error: "erreur"
        case .missingState: "manque un état"
        case .slow: "lent"
        case .textToFix: "texte à corriger"
        case .broken: "ne marche pas"
        }
    }

    /// Code physique de la touche, rangée du haut.
    ///
    /// L'ordre des constantes Carbon n'est PAS celui des chiffres : `5` vaut 23 et `6`
    /// vaut 22. Les écrire à la main en supposant une suite contiguë interposerait
    /// silencieusement deux intentions — le genre de bug qu'on ne voit qu'en relisant un
    /// rapport où « lent » et « texte à corriger » ont été échangés.
    var keyCode: Int64 {
        switch self {
        case .misaligned: Int64(kVK_ANSI_1)      // 18
        case .error: Int64(kVK_ANSI_2)           // 19
        case .missingState: Int64(kVK_ANSI_3)    // 20
        case .slow: Int64(kVK_ANSI_4)            // 21
        case .textToFix: Int64(kVK_ANSI_5)       // 23, et non 22
        case .broken: Int64(kVK_ANSI_6)          // 22, et non 23
        }
    }

    /// Un `switch` sur des constantes, et non `allCases.first { ... }`.
    ///
    /// Cette fonction s'exécute DANS le callback du tap, dont le budget interdit toute
    /// allocation (§ 6.2) : `allCases` construit un tableau à chaque appel, et le
    /// dépassement du budget déclenche `kCGEventTapDisabledByTimeout` — la bascule
    /// cesse, en silence. C'est le risque R9.
    @inline(__always)
    static func forKeyCode(_ code: Int64) -> Intention? {
        switch Int(code) {
        case kVK_ANSI_1: .misaligned
        case kVK_ANSI_2: .error
        case kVK_ANSI_3: .missingState
        case kVK_ANSI_4: .slow
        case kVK_ANSI_5: .textToFix
        case kVK_ANSI_6: .broken
        default: nil
        }
    }

    /// Ce qui s'affiche sur le badge. Le libellé en clair, pas un glyphe : un symbole
    /// abrégé demanderait une légende, et le rapport est lu par quelqu'un qui n'a pas
    /// l'application sous les yeux.
    var glyph: String { label }
}

/// Codes physiques des chiffres `7` à `9`, muets quand une marque est attachée.
///
/// Ils sont reconnus pour pouvoir être REFUSÉS visiblement. Les laisser passer au tap
/// enverrait `⌥⌘7` à l'application testée en plein tracé ; les avaler en silence ferait
/// passer l'absence d'effet pour une panne (ADR-0021, conséquences négatives).
enum MuteDigit {
    /// Même contrainte que ci-dessus : trois comparaisons, aucune structure construite.
    @inline(__always)
    static func rank(of code: Int64) -> Int? {
        switch Int(code) {
        case kVK_ANSI_7: 7
        case kVK_ANSI_8: 8
        case kVK_ANSI_9: 9
        default: nil
        }
    }
}
