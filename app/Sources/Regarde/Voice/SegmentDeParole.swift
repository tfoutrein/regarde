import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le segment de parole — spécification § 3.4, adapté au dépôt
//
// Deux textes, toujours : `texte` est éditable en revue, `texteBrut` ne l'est
// JAMAIS — c'est le témoin que le rapport conserve quoi qu'il arrive
// (« texte brut toujours conservé », livrable du lot). L'onset est le début du
// premier mot ; à défaut, le début de la plage du moteur — et c'est l'onset,
// pas la plage, qui décide du rattachement (ADR-0011, le premier mot).
// ─────────────────────────────────────────────────────────────────────────────

struct SegmentDeParole: Codable, Sendable, Equatable {
    let id: UUID
    let mots: [Mot]
    var texte: String
    let texteBrut: String
    /// La plage annoncée par le moteur — diagnostic, jamais le rattachement.
    let plageDebut: SessionTime
    let plageFin: SessionTime
    /// Posé par S64 depuis la machine ; nil tant que personne n'a tranché.
    var attachement: FenetreDeParole.Attachement?

    var onset: SessionTime { mots.first?.debut ?? plageDebut }
    var fin: SessionTime { mots.last?.fin ?? plageFin }

    init(id: UUID = UUID(), mots: [Mot], texte: String,
         plageDebut: SessionTime, plageFin: SessionTime,
         attachement: FenetreDeParole.Attachement? = nil) {
        self.id = id
        self.mots = mots
        self.texte = texte
        self.texteBrut = texte
        self.plageDebut = plageDebut
        self.plageFin = plageFin
        self.attachement = attachement
    }
}

// L'attachement de S63 devient Codable ici : le segment part au manifeste,
// et le § 9.5 écrit `attachment.rule` — la règle voyage avec la décision.
extension FenetreDeParole.Attachement: Codable {
    private enum Cles: String, CodingKey { case marque, regle }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Cles.self)
        let regle = try c.decode(FenetreDeParole.Regle.self, forKey: .regle)
        if let marque = try c.decodeIfPresent(Int.self, forKey: .marque) {
            self = .marque(marque, regle: regle)
        } else {
            self = .global(regle: regle)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Cles.self)
        switch self {
        case .marque(let marque, let regle):
            try c.encode(marque, forKey: .marque)
            try c.encode(regle, forKey: .regle)
        case .global(let regle):
            try c.encode(regle, forKey: .regle)
        }
    }
}
