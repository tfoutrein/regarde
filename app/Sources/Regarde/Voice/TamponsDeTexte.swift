import CoreMedia
import Foundation
import Speech

// ─────────────────────────────────────────────────────────────────────────────
// Les tampons de texte et la timeline — S62, spécification § 7.2, ADR-0012
//
// Tout ce qui se juge SANS moteur vit ici, pur :
//
//   · LA RÈGLE DES DEUX TAMPONS. Un résultat FINAL s'ajoute à la liste des
//     finaux et vide le volatil ; un résultat VOLATIL remplace le volatil —
//     jamais concaténé, parce que les volatils réémettent la phrase ENTIÈRE à
//     chaque fois : concaténer produirait « compos composant composant le ».
//     Le volatil est le seul indicateur fiable d'activité vocale (§ 7.2).
//
//   · L'EXTRACTION DES MOTS depuis l'`AttributedString` du moteur : chaque
//     passe porte sa plage temporelle et sa confiance ; le rapport en a besoin
//     pour le lexique (S68, seuil 0,6) et pour le premier mot (ADR-0011).
//
//   · LA TIMELINE en échantillons ENTIERS. `bufferStartTime` impose au moteur
//     le temps de session (ADR-0012), et le harnais de S59 a payé deux leçons :
//     une somme de secondes flottantes chevauche d'un tick et le moteur refuse
//     l'audio ; et la position suit les échantillons SORTIS du converter — les
//     résidus de conversion créent sinon des trous qui hachent les mots.
// ─────────────────────────────────────────────────────────────────────────────

/// Un mot tel que le moteur le rend : texte, plage en temps de session,
/// confiance (nil quand le moteur n'en donne pas).
struct Mot: Codable, Sendable, Equatable {
    let texte: String
    let debut: SessionTime
    let fin: SessionTime
    let confiance: Double?
}

struct TamponsDeTexte: Equatable, Sendable {
    private(set) var finaux: [String] = []
    private(set) var volatil: String?

    /// La règle des deux tampons — un final ajoute et vide, un volatil remplace.
    mutating func recevoir(final: Bool, texte: String) {
        if final {
            finaux.append(texte)
            volatil = nil
        } else {
            volatil = texte
        }
    }

    /// `bufferStartTime` pour un buffer dont le premier échantillon est le
    /// `echantillonsSortis`-ième depuis l'ouverture d'une fenêtre ouverte à
    /// `origine` (temps de session). Valeur entière, échelle = cadence : deux
    /// fenêtres successives donnent une timeline discontinue mais monotone.
    static func bufferStartTime(origine: SessionTime, echantillonsSortis: Int64,
                                cadence: Double) -> CMTime {
        let base = Int64((origine.seconds * cadence).rounded())
        return CMTime(value: CMTimeValue(base + echantillonsSortis),
                      timescale: CMTimeScale(cadence))
    }

    /// Les mots d'un résultat, passe par passe. Une passe sans plage
    /// temporelle est ignorée : sans instant, un mot ne peut ni s'ancrer ni
    /// se rattacher, et le texte complet reste de toute façon dans le segment.
    static func mots(depuis texte: AttributedString) -> [Mot] {
        var sortie: [Mot] = []
        for passe in texte.runs {
            let fragment = String(texte[passe.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fragment.isEmpty, let plage = passe.audioTimeRange else { continue }
            sortie.append(Mot(texte: fragment,
                              debut: SessionTime(plage.start),
                              fin: SessionTime(plage.end),
                              confiance: passe.transcriptionConfidence.map { Double($0) }))
        }
        return sortie
    }
}
