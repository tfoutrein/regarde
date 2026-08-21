import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Options réservées à la vérification, jamais atteignables en usage normal
//
// Le calque est invisible aux captures (`sharingType = .none`, R12) — c'est la garantie
// qui empêche l'encre de contaminer les PNG du rapport. Mais elle empêche aussi de
// VÉRIFIER le rendu autrement qu'à l'œil, et « je l'ai regardé » n'est pas une mesure.
//
// D'où ce drapeau. Il ne s'active que par un argument de ligne de commande : une
// application lancée depuis le Finder, le Dock ou un raccourci n'en reçoit aucun, donc
// aucun chemin d'usage réel ne peut l'allumer par accident.
// ─────────────────────────────────────────────────────────────────────────────

enum TestFlags {
    /// Rend le calque visible aux captures d'écran, le temps d'une vérification.
    ///
    /// À n'utiliser que depuis un script de contrôle. Le journal le signale à chaque
    /// démarrage, pour qu'une session menée par erreur dans ce mode ne passe pas
    /// inaperçue — ses captures porteraient l'encre en double, gravée ET incrustée.
    static let visibleCapture = CommandLine.arguments.contains("--visible-capture")

    /// Arme le banc C11 : les clics nus sont horodatés, et un `c11.json` est déposé
    /// à côté des images à la publication. Aucun effet sur le chemin nominal.
    static let c11Bench = CommandLine.arguments.contains("--c11-bench")
}
