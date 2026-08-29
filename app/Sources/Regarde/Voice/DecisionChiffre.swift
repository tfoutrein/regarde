import Carbon.HIToolbox
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// `⌥⌘ + chiffre` — la règle de désambiguïsation, ADR-0021 et § 6.7
//
// Trois fonctions revendiquent le même accord : la marque rétroactive à T−N
// (§ 5.1), la palette d'intentions (§ 7.4) et la réaffectation du segment de
// parole (§ 3.5). Le discriminant n'est ni la tenue du modificateur ni
// l'ouverture de la fenêtre — c'est LA PRÉSENCE D'UNE MARQUE attachée à la
// fenêtre de parole courante, évaluée à l'instant de la frappe :
//
//   fenêtre sans marque   `1`..`9` → marque rétroactive à T−N
//   fenêtre avec marque   `1`..`6` → intention ; `7`..`9` → flash d'invalidité
//                         `⇧`+`1`..`9` → réaffectation du segment à la marque N
//   `0`                   → le segment bascule en commentaire général
//
// La règle s'enchaîne d'elle-même : `⌥⌘` `3` `2` pose une rétroactive à T−3 s
// puis lui applique « erreur », parce que poser la rétroactive ATTACHE une
// marque à la fenêtre — le chiffre suivant change donc de sens tout seul. Le
// prix assumé : deux rétroactives d'affilée demandent de relâcher ⌥⌘.
//
// La décision est PURE. Le tap ne fait que la consulter, et l'autotest la juge
// sur la table entière, ligne par ligne — un `switch` sur des entiers, aucune
// allocation dans le callback (R9).
// ─────────────────────────────────────────────────────────────────────────────

enum DecisionChiffre {

    /// Ce que le chiffre veut dire, ici et maintenant.
    enum Sens: Equatable, Sendable {
        /// Poser une marque datée de N secondes avant maintenant.
        case retroactive(secondes: Int)
        /// Qualifier la marque attachée.
        case intention(Intention)
        /// `7`..`9` avec une marque attachée : avalé, le HUD dit pourquoi.
        case horsPalette(rang: Int)
        /// `⇧`+`N` : le segment de parole en cours part à la marque N.
        case reaffecter(marque: Int)
        /// `0` : le segment en cours devient un commentaire général.
        case enGlobal
        /// Rien à faire — le chiffre appartient à l'application testée.
        case aucun
    }

    /// Le rang d'un chiffre par son code PHYSIQUE (ADR-0021) : résoudre le
    /// caractère « 1 » renverrait le pavé numérique sur un clavier AZERTY,
    /// absent de tout MacBook. L'ordre des constantes Carbon n'est pas celui
    /// des chiffres — `5` vaut 23 et `6` vaut 22 — d'où le `switch` explicite.
    @inline(__always)
    static func rang(deCode code: Int64) -> Int? {
        switch Int(code) {
        case kVK_ANSI_0: 0
        case kVK_ANSI_1: 1
        case kVK_ANSI_2: 2
        case kVK_ANSI_3: 3
        case kVK_ANSI_4: 4
        case kVK_ANSI_5: 5
        case kVK_ANSI_6: 6
        case kVK_ANSI_7: 7
        case kVK_ANSI_8: 8
        case kVK_ANSI_9: 9
        default: nil
        }
    }

    /// LA décision — la table du § 6.7, au mot près.
    ///
    /// `marqueAttachee` est le numéro de la marque de la fenêtre de parole
    /// courante, `nil` quand rien n'a encore été tracé dedans. L'appelant a
    /// déjà vérifié que ⌥⌘ est tenu et que la cible est l'application active.
    @inline(__always)
    static func sens(rang: Int, shift: Bool, marqueAttachee: Int?) -> Sens {
        // `0` bascule le segment en cours en général, avec ou sans marque : il
        // dit « ce que je raconte là ne vise rien de précis », et cette phrase
        // a le même sens dans les deux états.
        if rang == 0 { return .enGlobal }
        guard (1...9).contains(rang) else { return .aucun }

        guard let marqueAttachee else {
            // Rien de tracé : le chiffre ne peut désigner qu'un INSTANT. ⇧ n'a
            // rien à réaffecter — aucune marque n'existe pour recevoir — et
            // pose donc la même rétroactive, plutôt que de ne rien faire.
            return .retroactive(secondes: rang)
        }
        if shift { return .reaffecter(marque: rang) }
        if let intention = Intention.forKeyCode(Intention.codePour(rang: rang)) {
            return .intention(intention)
        }
        return .horsPalette(rang: rang)
    }
}

extension Intention {
    /// Le code physique d'un rang — l'inverse de `keyCode`, pour la décision.
    @inline(__always)
    static func codePour(rang: Int) -> Int64 {
        switch rang {
        case 1: Int64(kVK_ANSI_1)
        case 2: Int64(kVK_ANSI_2)
        case 3: Int64(kVK_ANSI_3)
        case 4: Int64(kVK_ANSI_4)
        case 5: Int64(kVK_ANSI_5)
        case 6: Int64(kVK_ANSI_6)
        default: -1
        }
    }
}
