import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le barème de jetons visuels — S48, spécification § 9.6
//
//     tokens_visuels(l, h) = min( ⌈l/28⌉ × ⌈h/28⌉ , plafond_du_palier )
//
// Le plafond n'est pas un détail : la conception initiale appliquait la formule
// brute et annonçait 9 920 jetons pour une capture native 3456×2234, alors que
// l'API redimensionne d'elle-même et facture le plafond du palier. Le produit
// vend à l'agent sa capacité d'ARBITRER sur le coût annoncé — une annonce
// fausse de ×2 lui ferait éviter des images qu'il pouvait se payer.
//
// Et le ⌈⌉ n'est pas un détail non plus : sur les quatre vecteurs normatifs du
// § 9.6, un arrondi par le bas passerait inaperçu — trois ont des dimensions
// multiples exactes de 28, le quatrième est masqué par son plafond. C'est le
// cinquième vecteur, 8:1 non multiple, qui garde l'arrondi (voir l'autotest).
// ─────────────────────────────────────────────────────────────────────────────

public enum Bareme {

    /// Les deux paliers de l'API vision, et leurs plafonds mesurés (§ 9.6).
    public enum Palier: Int, Sendable {
        /// `crop` et `full` — l'API standard.
        case standard = 1568
        /// Capture native et `full_hires` — le palier haute résolution.
        case hauteResolution = 4784
    }

    /// Patches AVANT plafond. Public parce que l'autotest vérifie séparément la
    /// formule et le plafond : c'est ce qui fait que « retirer le plafond »
    /// échoue en annonçant 9 920 au lieu de rendre un test muet.
    public static func patches(largeur: Int, hauteur: Int) -> Int {
        // ⌈n/28⌉ en arithmétique entière. 28 px est le côté du patch de l'API.
        ((largeur + 27) / 28) * ((hauteur + 27) / 28)
    }

    /// Le barème complet : la formule, plafonnée.
    public static func jetonsVisuels(largeur: Int, hauteur: Int, palier: Palier) -> Int {
        min(patches(largeur: largeur, hauteur: hauteur), palier.rawValue)
    }
}
