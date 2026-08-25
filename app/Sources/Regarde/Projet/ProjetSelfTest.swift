import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du projet — S51 (pastilles, énumération), étendu en S52 (décision)
//
// Les teintes se mesurent SUR CAPTURES — le bitmap rendu, pas les constantes.
// Le seuil est celui de lot4-seuils.md n°8 : ΔE*ab ≥ 20 entre chaque paire, et
// le test REFUSE DE CONCLURE sous le seuil — il ne « passe » pas tristement, il
// dit quelle paire est illisible.
//
// L'énumération se juge sur des shells RÉELS : trois /bin/zsh lancés dans trois
// projets fabriqués — pas un tableau de chemins simulés. Ce que proc_pidinfo
// rapporte de vrais processus est exactement ce que le sélecteur montrera.
// ─────────────────────────────────────────────────────────────────────────────

enum ProjetSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du projet (S51+) ──\n")
        pastilles(t)
        enumeration(t)
        decision(t)
        cibleDuPorteur(t)
        collecteurs(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - Les pastilles, au pixel

    private static func pastilles(_ t: Tally) {
        print("· Les trois teintes, mesurées sur captures (seuil n°8 : ΔE*ab ≥ 20)")

        var labs: [(EtatProjet, (Double, Double, Double))] = []
        for etat in EtatProjet.allCases {
            guard let rep = PastilleProjet.rendre(etat) else {
                check(t, "pastille \(etat.libelle) rendue", false); return
            }
            // La couleur MOYENNE du disque, sur les pixels opaques — c'est la
            // capture qui parle, pas la constante.
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let p = rep.colorAt(x: x, y: y), p.alphaComponent > 0.9 else { continue }
                    r += p.redComponent; g += p.greenComponent; b += p.blueComponent; n += 1
                }
            }
            guard n > 50 else { check(t, "pastille \(etat.libelle) — des pixels", false); return }
            labs.append((etat, lab(r / n, g / n, b / n)))
        }

        var minimum = Double.infinity
        for i in 0..<labs.count {
            for j in (i + 1)..<labs.count {
                let d = deltaE(labs[i].1, labs[j].1)
                minimum = min(minimum, d)
                check(t, "\(labs[i].0.libelle) ↔ \(labs[j].0.libelle) — ΔE*ab ≥ 20",
                      d >= 20, String(format: "%.1f", d))
            }
        }
        // Le REFUS de conclure : sous le seuil, le verdict global est un refus
        // nommé, pas un échec parmi d'autres.
        if minimum < 20 {
            check(t, "REFUS DE CONCLURE — deux teintes sont plus proches que le seuil n°8",
                  false, String(format: "minimum %.1f", minimum))
        }
    }

    /// sRGB → Lab (D65), pour le ΔE*ab (CIE76) du seuil n°8.
    private static func lab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        func lineaire(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = lineaire(r), gl = lineaire(g), bl = lineaire(b)
        let x = (0.4124 * rl + 0.3576 * gl + 0.1805 * bl) / 0.95047
        let y = 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
        let z = (0.0193 * rl + 0.1192 * gl + 0.9505 * bl) / 1.08883
        func f(_ v: Double) -> Double {
            v > 0.008856 ? pow(v, 1.0 / 3.0) : 7.787 * v + 16.0 / 116.0
        }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    private static func deltaE(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        sqrt(pow(a.0 - b.0, 2) + pow(a.1 - b.1, 2) + pow(a.2 - b.2, 2))
    }

    // MARK: - L'énumération, sur trois shells réels

    private static func enumeration(_ t: Tally) {
        print("\n· Trois shells réels, trois projets fabriqués")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("projets-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        var shells: [Process] = []
        var chemins: [String] = []
        for nom in ["alpha", "beta", "gamma"] {
            let dossier = base.appendingPathComponent(nom, isDirectory: true)
            try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            // Le chemin canonique par realpath(3) — PAS resolvingSymlinksInPath,
            // dont la bizarrerie documentée fait l'INVERSE du noyau : il retire
            // le préfixe /private pour /var, /tmp et /etc, là où proc_pidinfo
            // rapporte le vrai chemin du vnode. Une heure de « absent » pour
            // deux chaînes qui désignaient le même répertoire.
            var reel = [CChar](repeating: 0, count: Int(PATH_MAX))
            realpath(dossier.path, &reel)
            chemins.append(String(cString: reel))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // COMPOSÉE, pas simple : zsh -c « commande simple unique » s'exec
            // dedans et le processus n'est plus un zsh — le test cherchait des
            // shells et trouvait des sleep.
            p.arguments = ["-c", "sleep 15; true"]
            p.currentDirectoryURL = dossier
            do { try p.run() } catch {
                check(t, "lancement des shells", false, "\(error)"); return
            }
            shells.append(p)
        }
        defer { shells.forEach { $0.terminate() } }
        usleep(300_000)   // le temps que les shells soient réellement dans leur cwd

        let candidats = ProjetCandidats.enumerer()
        for chemin in chemins {
            let trouve = candidats.first { $0.chemin == chemin }
            check(t, "candidat \((chemin as NSString).lastPathComponent) trouvé, avec son motif",
                  trouve != nil && trouve!.motif.contains("cwd de zsh (pid "),
                  trouve?.motif ?? "absent")
        }
        check(t, "l'ordre est stable — deux appels, même liste",
              candidats.map(\.chemin) == ProjetCandidats.enumerer().map(\.chemin))
        check(t, "ni « / » ni le dossier personnel nu parmi les candidats",
              !candidats.contains { $0.chemin == "/" || $0.chemin == NSHomeDirectory() })
    }

    // MARK: - La décision, cas par cas (S52)

    private static func decision(_ t: Tally) {
        print("\n· La décision — fonction pure, cas par cas")
        func signaux(_ chemin: String, shells: Int = 0, vivant: Bool = false,
                     frais: Bool = false, titre: Bool = false) -> SignauxProjet {
            var s = SignauxProjet(chemin: chemin)
            s.shells = shells; s.providerVivant = vivant
            s.providerFrais = frais; s.providerPid = 4242; s.titreConcorde = titre
            return s
        }

        // Deux signaux forts concordants → certain.
        var v = DecisionProjet.decider([signaux("/p/a", shells: 1, vivant: true, frais: true)])
        check(t, "shell + provider frais concordants → certain",
              v.etat == .certain && v.retenu == "/p/a", v.motif)

        // Un seul signal fort → probable, avec son motif.
        v = DecisionProjet.decider([signaux("/p/a", shells: 2)])
        check(t, "shells seuls → probable, motif nommé",
              v.etat == .probable && v.motif.contains("2 shells"), v.motif)

        // Plusieurs cwd crédibles → ambigu, JAMAIS tranché.
        v = DecisionProjet.decider([signaux("/p/a", shells: 1),
                                    signaux("/p/b", vivant: true, frais: true)])
        check(t, "deux répertoires crédibles → ambigu, jamais tranché",
              v.etat == .ambigu && v.motif.contains("jamais tranché"))

        // Le titre seul ne décide JAMAIS.
        v = DecisionProjet.decider([signaux("/p/a", titre: true)])
        check(t, "titre seul → ambigu — il ne décide jamais seul",
              v.etat == .ambigu && v.retenu == nil)

        // LE CAS DU TITRE : provider vivant mais pas frais (0,8) + shell (1,0)
        // = 1,8 → probable ; le titre (0,2) complète à 2,0 → certain. Retirer
        // le titre change le verdict — c'est le critère du plan, prouvé ici.
        let cas = [signaux("/p/a", shells: 1, vivant: true, frais: false, titre: true)]
        let avec = DecisionProjet.decider(cas)
        let sans = DecisionProjet.decider(cas, titreActif: false)
        check(t, "provider pas frais + shell + titre → certain",
              avec.etat == .certain, avec.motif)
        check(t, "le MÊME cas sans le titre → probable — le retirer change le verdict",
              sans.etat == .probable)
    }

    // MARK: - Les collecteurs, sur la machine réelle

    // MARK: - La cible du porteur (recette lot 4, test 5.4)

    private static func cibleDuPorteur(_ t: Tally) {
        print("\n· La cible du porteur — jamais le premier venu")

        // Le filtre des chemins : ce que la recette a réellement rencontré.
        check(t, "« / » (codex de ChatGPT.app) n'est pas un projet",
              !DecisionProjet.cheminExploitable("/", home: "/Users/x"))
        check(t, "le home (daemon d'arrière-plan) non plus",
              !DecisionProjet.cheminExploitable("/Users/x", home: "/Users/x"))
        check(t, "un répertoire temporaire non plus",
              !DecisionProjet.cheminExploitable("/private/tmp/cc-daemon-502/a/spare",
                                                home: "/Users/x")
                && !DecisionProjet.cheminExploitable("/var/folders/dl/xyz/T/w", home: "/Users/x"))
        check(t, "un vrai répertoire de travail, oui",
              DecisionProjet.cheminExploitable("/Users/x/DEV/projet", home: "/Users/x"))

        // La sélection, à contre-épreuve : le projet bat la fraîcheur.
        let frais = DecisionProjet.Provider(pid: 1, chemin: "/u/autre", fraicheurSecondes: 5)
        let dessus = DecisionProjet.Provider(pid: 2, chemin: "/u/projet", fraicheurSecondes: 900)
        let muet = DecisionProjet.Provider(pid: 3, chemin: "/u/tiers", fraicheurSecondes: nil)
        check(t, "l'agent DU projet gagne, même moins frais",
              DecisionProjet.agentCible(parmi: [frais, dessus, muet],
                                        projet: "/u/projet")?.pid == 2)
        check(t, "un sous-répertoire du projet compte aussi",
              DecisionProjet.agentCible(parmi: [frais, dessus],
                                        projet: "/u/projet/sous")?.pid == 2)
        check(t, "sans agent sur le projet : le plus frais",
              DecisionProjet.agentCible(parmi: [muet, dessus, frais],
                                        projet: "/ailleurs")?.pid == 1)
        check(t, "sans fraîcheur mesurable : le premier vivant",
              DecisionProjet.agentCible(parmi: [muet], projet: nil)?.pid == 3)
        check(t, "aucun vivant : personne — la phrase reste au presse-papiers",
              DecisionProjet.agentCible(parmi: [], projet: "/u/projet") == nil)
    }

    private static func collecteurs(_ t: Tally) {
        print("\n· Les collecteurs, sur la machine réelle")
        // Ce test tourne sur une machine de développement où un agent PILOTE ce
        // dépôt : au moins un provider doit se voir, vivant. C'est une
        // assertion sur l'environnement de développement, assumée comme telle.
        let providers = DecisionProjet.providers()
        check(t, "au moins un provider d'agent vivant est vu",
              providers.contains { kill($0.pid, 0) == 0 },
              "\(providers.count) provider(s)")
        let signaux = DecisionProjet.collecter()
        check(t, "les signaux s'assemblent sans doublon de chemin",
              Set(signaux.map(\.chemin)).count == signaux.count,
              "\(signaux.count) candidat(s)")
    }
}
