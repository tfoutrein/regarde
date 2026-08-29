import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// transcript.txt — S66, spécification § 9.2, format tranché en lot5-seuils § 3
//
// Une ligne par segment FINAL, dans l'ordre du premier mot :
//
//     [MM:SS.d] (marque 2|global|éclair) texte brut du segment
//
// Le texte est `texteBrut`, jamais la version corrigée par le lexique : le
// fichier est le témoin brut, la correction vit au manifeste. Il s'écrit par
// LA porte d'append (S47) — jamais réécrit — et n'existe que s'il a quelque
// chose à dire : une session sans parole n'a pas de transcript, et le rendu
// ne mentionne jamais un fichier absent (amendement S46). Dans le projet il
// est VERSIONNABLE — le cinquième chemin que `git status` propose.
// ─────────────────────────────────────────────────────────────────────────────

enum Transcript {
    enum Contexte { case session, eclair }

    /// La ligne d'un segment — PURE, jugée par l'autotest.
    static func ligne(_ segment: SegmentDeParole, contexte: Contexte = .session) -> String {
        let t = max(0, segment.onset.seconds)
        let temps = String(format: "%02d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
        let qui: String
        switch segment.attachement {
        case .marque(let n, _)?: qui = "marque \(n)"
        case .global?: qui = contexte == .eclair ? "éclair" : "global"
        case nil: qui = "global"
        }
        let texte = segment.texteBrut.replacingOccurrences(of: "\n", with: " ")
        return "[\(temps)] (\(qui)) \(texte)"
    }

    /// Écrit `transcript.txt` dans `dossier`. Rien à dire → aucun fichier, et
    /// `nil` pour le dire. Les segments sortent dans l'ordre du premier mot.
    @discardableResult
    static func ecrire(_ segments: [SegmentDeParole], dans dossier: URL,
                       contexte: Contexte = .session,
                       permissions: mode_t = 0o600) throws -> URL? {
        guard !segments.isEmpty else { return nil }
        let url = dossier.appendingPathComponent("transcript.txt")
        let porte = try AppendOnlyLog(url: url, permissions: permissions)
        defer { porte.fermer() }
        for segment in segments.sorted(by: { $0.onset < $1.onset }) {
            try porte.append(ligne: ligne(segment, contexte: contexte))
        }
        return url
    }
}
