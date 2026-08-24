import AppKit
import Darwin
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La décision de projet — S52, ADR-0017
//
// Trois signaux, deux poids et une règle qui ne se négocie pas :
//
//   FORT  1,0   un shell vivant dont le cwd est le candidat
//   FORT  1,0   un provider (session d'agent) VIVANT — kill(pid, 0) — et FRAIS
//               (activité < 120 s) sur ce répertoire ; vivant mais pas frais,
//               il se dégrade à 0,8 : l'agent d'hier soir n'atteste plus grand-
//               chose sur la session de maintenant
//   FAIBLE 0,2  le titre de la fenêtre au premier plan contient le nom du
//               candidat. Il COMPLÈTE, il ne fonde jamais : seul, il ne fait
//               ni un probable ni un candidat
//
//   certain   = UN SEUL candidat crédible, et score ≥ 2,0 — deux signaux forts
//               concordants, ou un fort dégradé que le titre complète
//   probable  = un seul candidat crédible, score ≥ 1,0
//   ambigu    = plusieurs candidats crédibles — JAMAIS tranché : c'est l'état
//               qui pousse un rapport dans le bon dépôt en forçant un regard,
//               et le trancher automatiquement est exactement le réflexe que
//               R2 interdit. Ambigu aussi quand personne n'atteint 1,0.
//
// La décision est une fonction PURE sur des signaux — fabricables à volonté —
// et les collecteurs qui la nourrissent sont séparés : libproc, kill(0),
// l'index d'activité de l'agent, le titre de fenêtre. Chaque collecteur peut
// échouer en silence (P5) ; la décision, elle, est vérifiée cas par cas.
// ─────────────────────────────────────────────────────────────────────────────

struct SignauxProjet: Equatable {
    let chemin: String
    var shells: Int = 0
    var providerVivant: Bool = false
    var providerFrais: Bool = false
    var providerPid: pid_t = 0
    var titreConcorde: Bool = false

    var score: Double {
        var s = 0.0
        if shells > 0 { s += 1.0 }
        if providerVivant { s += providerFrais ? 1.0 : 0.8 }
        if titreConcorde { s += 0.2 }
        return s
    }

    /// Le motif que le sélecteur et le rapport affichent — chaque signal nommé,
    /// dans l'ordre de son poids.
    var motif: String {
        var parts: [String] = []
        if providerVivant {
            parts.append("session d'agent vivante (pid \(providerPid)\(providerFrais ? "" : ", pas fraîche"))")
        }
        if shells > 0 { parts.append("\(shells) shell\(shells > 1 ? "s" : "") sur ce répertoire") }
        if titreConcorde { parts.append("titre de fenêtre concordant") }
        return parts.isEmpty ? "aucun signal" : parts.joined(separator: " · ")
    }
}

enum DecisionProjet {

    struct Verdict: Equatable {
        let etat: EtatProjet
        /// Le chemin retenu — présent pour certain et probable, nil pour ambigu
        /// SANS candidat ; pour ambigu AVEC candidats, le meneur est proposé en
        /// tête du sélecteur mais rien n'est tranché.
        let retenu: String?
        let motif: String
    }

    /// La fonction pure. `titreActif` permet à l'autotest de prouver que le
    /// titre change le verdict d'au moins un cas — le retirer doit se voir.
    static func decider(_ signaux: [SignauxProjet], titreActif: Bool = true) -> Verdict {
        let effectifs = titreActif ? signaux : signaux.map {
            var s = $0; s.titreConcorde = false; return s
        }
        let credibles = effectifs.filter { $0.score >= 1.0 }.sorted { $0.score > $1.score }

        guard let meneur = credibles.first else {
            return Verdict(etat: .ambigu, retenu: nil,
                           motif: "aucun candidat crédible — le titre seul ne décide jamais")
        }
        guard credibles.count == 1 else {
            return Verdict(etat: .ambigu, retenu: meneur.chemin,
                           motif: "\(credibles.count) répertoires crédibles — jamais tranché automatiquement")
        }
        if meneur.score >= 2.0 {
            return Verdict(etat: .certain, retenu: meneur.chemin, motif: meneur.motif)
        }
        return Verdict(etat: .probable, retenu: meneur.chemin, motif: meneur.motif)
    }

    // MARK: - Les collecteurs réels

    /// Assemble les signaux de la machine : shells (S51), providers, titre.
    static func collecter() -> [SignauxProjet] {
        var parChemin: [String: SignauxProjet] = [:]

        for candidat in ProjetCandidats.enumerer() {
            parChemin[candidat.chemin, default: SignauxProjet(chemin: candidat.chemin)].shells += 1
        }
        for provider in providers() {
            var s = parChemin[provider.chemin, default: SignauxProjet(chemin: provider.chemin)]
            // kill(pid, 0) : le droit d'envoyer un signal atteste l'existence —
            // sans rien envoyer. Un provider dont le processus a disparu entre
            // l'énumération et cette ligne n'atteste rien.
            s.providerVivant = kill(provider.pid, 0) == 0
            s.providerFrais = provider.fraicheurSecondes.map { $0 < 120 } ?? false
            s.providerPid = provider.pid
            parChemin[provider.chemin] = s
        }
        if let titre = titreFenetreFrontale() {
            for (chemin, var s) in parChemin {
                let nom = (chemin as NSString).lastPathComponent
                if !nom.isEmpty, titre.localizedCaseInsensitiveContains(nom) {
                    s.titreConcorde = true
                    parChemin[chemin] = s
                }
            }
        }
        return parChemin.values.sorted { $0.chemin < $1.chemin }
    }

    struct Provider {
        let pid: pid_t
        let chemin: String
        let fraicheurSecondes: Double?
    }

    /// Les processus d'agent qu'on sait reconnaître, et leur répertoire.
    ///
    /// La fraîcheur vient de l'index d'activité de l'agent quand il en tient un
    /// (Claude Code : `~/.claude/projects/<chemin-aplati>/`, mtime du fichier le
    /// plus récent). Absente, elle vaut nil — le provider reste vivant mais non
    /// frais, à 0,8 : l'absence est silencieuse, pas gratuite.
    static func providers() -> [Provider] {
        var tailles = proc_listallpids(nil, 0)
        guard tailles > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(tailles) + 64)
        tailles = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<pid_t>.size))

        let agents: Set<String> = ["claude", "cursor", "codex"]
        var sortie: [Provider] = []
        for pid in pids.prefix(Int(max(0, tailles))) where pid > 0 {
            var nomTampon = [CChar](repeating: 0, count: 64)
            guard proc_name(pid, &nomTampon, UInt32(nomTampon.count)) > 0 else { continue }
            guard agents.contains(String(cString: nomTampon)) else { continue }
            guard let cwd = ProjetCandidats.repertoireDeTravail(pid) else { continue }
            sortie.append(Provider(pid: pid, chemin: cwd,
                                   fraicheurSecondes: fraicheurClaude(cwd)))
        }
        return sortie
    }

    /// L'âge de la dernière activité Claude Code sur un répertoire, si l'index
    /// existe. Convention observée : le chemin s'aplatit en remplaçant `/` par
    /// `-` sous `~/.claude/projects/`.
    static func fraicheurClaude(_ chemin: String) -> Double? {
        let aplati = chemin.replacingOccurrences(of: "/", with: "-")
        let dossier = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(aplati)")
        guard let fichiers = try? FileManager.default.contentsOfDirectory(
            at: dossier, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let dates = fichiers.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let recente = dates.max() else { return nil }
        return Date().timeIntervalSince(recente)
    }

    /// Le titre de la fenêtre au premier plan — best-effort : sans autorisation
    /// d'enregistrement d'écran, les titres sont absents et le signal vaut nil.
    static func titreFenetreFrontale() -> String? {
        guard let fenetres = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return fenetres.first {
            ($0[kCGWindowLayer as String] as? Int) == 0
                && (($0[kCGWindowName as String] as? String)?.isEmpty == false)
        }?[kCGWindowName as String] as? String
    }
}
