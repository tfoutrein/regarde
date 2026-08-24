import CoreVideo
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'épreuve d'identité — S45, spécification § 5.1 bis
//
// Certains écrans mentent. Mesuré le 24 août 2026 sur un moniteur 1080p branché
// en HDMI DIRECT — la configuration la plus banale qui soit : le compositeur
// re-présente la dalle entière à chaque frame (`dirtyRects` = un rect pleine
// taille, 643 frames sur 644, Bureau nu) alors que deux captures à une seconde
// d'écart diffèrent de 0,03 % des pixels. Phénomène connu des Mac Apple Silicon
// sur HDMI ; un papier peint vidéo produit le même symptôme, pour une cause
// réelle cette fois.
//
// Ce que ces dégâts fantômes coûtaient, en chaîne : l'encodeur ne s'arrêtait
// jamais (7,95 Mb/s mesurés pour un Bureau FIGÉ, 970 MiB en dix minutes à deux
// écrans — budget : 500), le critère de burst du § 5.4 voyait un écran animé
// partout, et le CPU tenait 5 % là où le § 4.4 en promet 3.
//
// Le § 5.1 a exclu la comparaison intégrale des pixels — 440 MiB/s de bande
// passante mémoire. Celle-ci échantillonne ~2 000 points, soit huit kilo-octets
// lus par frame : sans rapport. Une frame déclarée sale dont TOUS les
// échantillons égalent ceux de la dernière frame acceptée est tenue pour
// identique, et traitée comme du repos — ni écrite, ni comptée au mouvement —
// exactement ce qu'un écran honnête aurait produit : pas de frame du tout.
//
// LES POSITIONS TOURNENT. Fixes, elles seraient des angles morts permanents :
// un petit changement réel tombé entre les mailles y resterait invisible à
// jamais. À chaque frame, un seizième des positions est retiré et remplacé par
// des fraîches — l'ensemble se renouvelle en ~une seconde, et un changement
// persistant que l'échantillonnage a d'abord manqué finit sous une maille.
// Les positions fraîches ne votent pas à leur première frame : elles n'ont pas
// encore de valeur de référence, elles s'amorcent et voteront à la suivante.
//
// Ce que l'épreuve NE risque PAS : rater un grand changement (2 000 mailles sur
// l'écran, la probabilité de tout rater s'effondre exponentiellement avec la
// surface) ni casser l'extraction (une frame sautée est un trou de PTS, et le
// second passage du § 5.2 sait déjà servir les instants tombés dans un trou —
// l'image d'avant, dont l'épreuve vient de prouver qu'elle est la même).
//
// Tout vit sur `encodeQueue`, comme B2 l'exige : aucun verrou, aucun partage.
// ─────────────────────────────────────────────────────────────────────────────

final class EpreuveIdentite {

    static let mailles = 2048
    static let renouvellementParFrame = 128

    private var largeur = 0
    private var hauteur = 0
    /// Positions échantillonnées, en pixels du tampon.
    private var positions: [(x: Int, y: Int)] = []
    /// Valeur de référence par position — celle de la dernière frame ACCEPTÉE.
    private var references: [UInt32] = []
    /// Les positions fraîchement renouvelées, qui s'amorcent et ne votent pas.
    private var amorcees: Set<Int> = []
    /// Graine du générateur — délibérément déterministe, pour que les tests
    /// puissent rejouer la même séquence de positions.
    private var graine: UInt64 = 0x9E3779B97F4A7C15

    private(set) var ignorees = 0

    private func suivant() -> UInt64 {
        // xorshift64* — il ne faut ici que de la dispersion, pas de la crypto.
        graine ^= graine >> 12
        graine ^= graine << 25
        graine ^= graine >> 27
        return graine &* 0x2545F4914F6CDD1D
    }

    private func position() -> (x: Int, y: Int) {
        let r = suivant()
        return (Int(r % UInt64(largeur)), Int((r >> 24) % UInt64(hauteur)))
    }

    /// Rend `true` si la frame est identique à la dernière frame acceptée.
    ///
    /// `false` veut dire « acceptée » : la référence est remise à jour depuis
    /// cette frame, et l'appelant doit la traiter normalement.
    func estIdentique(_ tampon: CVPixelBuffer) -> Bool {
        let w = CVPixelBufferGetWidth(tampon)
        let h = CVPixelBufferGetHeight(tampon)

        CVPixelBufferLockBaseAddress(tampon, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(tampon, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(tampon) else { return false }
        let pas = CVPixelBufferGetBytesPerRow(tampon)
        let octets = base.assumingMemoryBound(to: UInt8.self)

        @inline(__always) func lire(_ p: (x: Int, y: Int)) -> UInt32 {
            let o = p.y * pas + p.x * 4
            return UInt32(octets[o]) | UInt32(octets[o+1]) << 8
                 | UInt32(octets[o+2]) << 16 | UInt32(octets[o+3]) << 24
        }

        // Première frame, ou géométrie changée : tout se réamorce, frame acceptée.
        if w != largeur || h != hauteur {
            largeur = w; hauteur = h
            positions = (0..<Self.mailles).map { _ in position() }
            references = positions.map(lire)
            amorcees = []
            return false
        }

        var change = false
        for i in positions.indices where !amorcees.contains(i) {
            if lire(positions[i]) != references[i] { change = true; break }
        }

        if change {
            // Frame acceptée : elle devient la référence, partout.
            references = positions.map(lire)
            amorcees = []
            return false
        }

        // Identique. Les positions amorcées à la frame précédente prennent leur
        // valeur de référence maintenant — l'épreuve vient d'établir que cette
        // frame égale la référence, la lecture est donc légitime.
        for i in amorcees { references[i] = lire(positions[i]) }
        amorcees = []
        // Et un seizième des mailles se déplace, contre les angles morts.
        for _ in 0..<Self.renouvellementParFrame {
            let i = Int(suivant() % UInt64(Self.mailles))
            positions[i] = position()
            amorcees.insert(i)
        }
        ignorees += 1
        return true
    }
}
