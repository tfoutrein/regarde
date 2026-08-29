import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le rendu — S49, spécification § 9.3 et § 9.4
//
// UNE fonction pure : manifeste → texte. Pas d'acteur, pas d'état, pas d'horloge
// — le rendu de S46 est figé sous empreinte SHA-256, et une empreinte ne se
// reproduit que si RIEN d'autre que l'entrée ne participe. C'est aussi la
// condition du lot 6 : le sidecar rendra les mêmes octets, application fermée.
//
// DEUX sorties, TROIS profils, QUATRE options :
//
//   `.disque`  — le `report.md` versionnable, la cible de l'empreinte.
//   `.sidecar` — le même rapport, mais le lot 6 doit pouvoir préfixer un
//                bandeau « DÉJÀ TRAITÉ », filtrer par marques et retirer le
//                contexte : les trois options existent et sont exercées ICI,
//                sans appelant — S37 a montré qu'une frontière posée à moitié
//                ne tient pas, et une option jamais appelée est une frontière
//                à moitié posée.
//   `.chatWeb` — `paste-web.md`, bloc autonome pour un chat sans MCP ni accès
//                aux fichiers : pas de chemins absolus, pas de
//                `resolve_feedback`, les images se joignent à la main.
//
//   `includeHires` — posée, INERTE : elle ne change rien tant que S58 n'a pas
//   livré le second palier. La poser aujourd'hui, c'est garantir que le lot 6
//   compile contre la signature définitive.
//
// LE FORMATAGE EST LOCAL ET DÉTERMINISTE. Aucun DateFormatter à locale, aucun
// NumberFormatter : la table des mois est écrite ici, les milliers se séparent
// à la main. Un rendu qui dépend des réglages de la machine produirait deux
// empreintes sur deux machines — et l'empreinte est le contrat.
// ─────────────────────────────────────────────────────────────────────────────

public enum Rendu {

    public enum Profil: Sendable { case disque, sidecar, chatWeb }

    public struct Options: Sendable {
        public var profil: Profil
        /// Préfixé tel quel avant l'en-tête, suivi d'une ligne vide (sidecar).
        public var bandeau: String?
        /// Ne rendre que ces marques ; nil = toutes.
        public var marques: [Int]?
        /// `false` : la section Contexte est omise (§ 9.3, `include_context`).
        public var includeContext: Bool
        /// Posée pour la signature, inerte jusqu'à S58.
        public var includeHires: Bool

        public init(profil: Profil = .disque, bandeau: String? = nil,
                    marques: [Int]? = nil, includeContext: Bool = true,
                    includeHires: Bool = false) {
            self.profil = profil
            self.bandeau = bandeau
            self.marques = marques
            self.includeContext = includeContext
            self.includeHires = includeHires
        }
    }

    /// Rend le rapport. La sortie pour `Options()` par défaut est la cible de
    /// l'empreinte de S46 — octet pour octet.
    public static func rendre(_ m: Manifeste.Racine, options: Options = Options()) -> String {
        var s = ""
        let web = options.profil == .chatWeb
        let marques = m.marks.filter { options.marques?.contains($0.number) ?? true }

        if let bandeau = options.bandeau { s += bandeau + "\n\n" }

        // ── En-tête et chapeau ──
        let projet = (m.session.context?.project).map {
            ($0 as NSString).lastPathComponent
        } ?? m.session.id
        s += "# Feedback #\(m.session.number) — \(projet) — \(date(m.session.startedAt))\n\n"
        // Les commentaires généraux : ceux de la session, plus les segments
        // rattachés à une marque que le filtre `marques` a écartée — sans quoi
        // un rendu partiel perdrait de la parole sans le dire.
        let generaux = (m.session.voice ?? []).sorted { $0.onset < $1.onset }
        let voixDesMarques = marques.flatMap { $0.voice ?? [] }
        let porteDeLaVoix = !generaux.isEmpty || !voixDesMarques.isEmpty

        s += "Session de test de \(duree(m.session.durationSeconds)). "
        s += "**\(marques.count) marque\(marques.count > 1 ? "s" : "")**"
        if !generaux.isEmpty {
            s += ", **\(generaux.count) commentaire\(generaux.count > 1 ? "s généraux" : " général")**"
        }
        s += ".\n"
        s += "\(m.session.tool.name) \(m.session.tool.version) (\(m.session.tool.os)). "
        // La locale ne se dit que s'il y a eu de la parole : une session au
        // micro refusé n'a rien à en dire (lot5-seuils § 4).
        if porteDeLaVoix {
            s += "Transcription locale \(m.session.locale), aucune donnée sortie de la machine.\n\n"
        } else {
            s += "Aucune donnée sortie de la machine.\n\n"
        }

        // ── Comment lire ──
        s += "## Comment lire ce rapport\n\n"
        s += "Le développeur a testé son application en la manipulant normalement. Quand quelque chose l'a\n"
        s += "gêné, il a maintenu ⌥⌘ et entouré la zone à l'écran : cela a créé une **marque numérotée**.\n"
        if porteDeLaVoix {
            s += "Ce qu'il disait à voix haute pendant ce geste a été transcrit et rattaché à la marque.\n"
        }
        s += "\n"
        s += "- Les marques sont dans l'ordre chronologique, pas par importance. Les numéros peuvent\n"
        s += "  comporter des trous : une marque supprimée n'est jamais renumérotée.\n"
        // Le lexique (S68) n'écrit ses `[terme ?]` que quand il a proposé
        // quelque chose : annoncer une convention absente serait du bruit.
        let avecLexique = (voixDesMarques + generaux).contains { !$0.lexiconSuggestions.isEmpty }
        if avecLexique {
            s += "- Les termes notés `[terme ?]` sont des corrections proposées par le lexique local sur des\n"
            s += "  mots que la reconnaissance vocale a mal entendus. Rétablis-les depuis le code.\n"
        }
        if web {
            s += "- **Le texte suffit dans la majorité des cas.** Les captures listées sous chaque marque\n"
            s += "  peuvent être jointes à la main si un doute reste sur l'élément visé.\n"
        } else {
            s += "- **Le texte suffit dans la majorité des cas.** Ne charge une capture que si tu ne sais pas\n"
            s += "  quel élément est visé, ou si le problème est purement visuel (alignement, espacement,\n"
            s += "  chevauchement). Le chemin absolu et le coût en jetons sont sous chaque marque.\n"
            s += "- Quand tu as appliqué ou écarté ces retours, appelle `resolve_feedback(number: \(m.session.number))`.\n"
            s += "  Sans cela, ce feedback te sera re-servi.\n"
        }
        s += "\n"

        // ── Contexte ──
        if options.includeContext, let c = m.session.context {
            s += "## Contexte\n\n| | |\n|---|---|\n"
            if let v = c.project {
                // En chat web, le projet se NOMME mais ne se localise pas : un
                // chemin absolu n'est ni utile ni discret dans une page tierce.
                let affiche = web ? (v as NSString).lastPathComponent : v
                s += "| Projet | `\(affiche)` |\n"
            }
            if let v = c.detection { s += "| Détection | \(v) |\n" }
            if let v = c.git { s += "| Git | \(v) |\n" }
            if let v = c.application { s += "| Application testée | \(v) |\n" }
            if let v = c.screen { s += "| Écran | \(v) |\n" }
            if let v = c.interruptions { s += "| Interruptions | \(v) |\n" }
            if let v = c.status { s += "| Statut | \(v) |\n" }
            s += "\n"
        }

        // ── Les marques ──
        let framesParID = Dictionary(uniqueKeysWithValues: m.frames.map { ($0.id, $0) })
        for marque in marques {
            s += "## Marque \(marque.number) — \(mmss(marque.sessionTime)) — `\(libelle(marque.intents))`\n\n"

            // Ce qui a été DIT, avant la géométrie : c'est l'intention de
            // l'utilisateur, le rectangle n'en est que la localisation.
            let paroles = (marque.voice ?? []).sorted { $0.onset < $1.onset }
            for segment in paroles {
                s += citation(segment.text) + "\n"
            }
            if !paroles.isEmpty { s += "\n" }

            let g = marque.geometry.points
            s += "**Zone entourée** : rectangle \(entier(g.w))×\(entier(g.h)) pt à "
            s += "(\(entier(g.x)), \(entier(g.y)))"
            if let note = marque.zoneNote { s += ", \(note)" }
            s += ".\n"
            if marque.screenWasMoving, let n = marque.contextFramesAvailable, n == 2 {
                s += "**Écran en mouvement à cet instant** : oui — deux frames de contexte disponibles (`-0,8 s`, `+0,4 s`).\n"
            }
            s += "\n**Captures**\n"
            if let id = marque.frames?.crop, let f = framesParID[id] {
                s += ligneCapture("Recadrage", f, web: web) + " ← à privilégier\n"
            }
            if let id = marque.frames?.full, let f = framesParID[id] {
                s += ligneCapture("Fenêtre entière", f, web: web) + "\n"
            }
            s += "\n"
        }

        // ── Commentaires généraux ── la forme est celle du lot 4, le contenu
        //    est arrivé avec la voix (S67). Sans parole : « - aucun. », et
        //    l'empreinte du rapport de référence du lot 4 ne bouge pas.
        s += "## Commentaires généraux\n\n"
        if generaux.isEmpty {
            s += "- aucun.\n\n"
        } else {
            for segment in generaux {
                s += puce(mmss(segment.onset), segment.text) + "\n"
            }
            s += "\n"
        }

        // ── Récapitulatif ──
        s += "## Récapitulatif\n\n"
        s += "| Marque | Recadrage | Jetons | Fenêtre entière | Jetons |\n|---|---|---|---|---|\n"
        var totalCrop = 0, totalFull = 0
        for marque in marques {
            let crop = m.frames.first { $0.role == "crop" && $0.marks.contains(marque.number) }
            let full = m.frames.first { $0.role == "full" && $0.marks.contains(marque.number) }
            let c = crop.map { "`\(nomFichier($0))` \($0.size.w)×\($0.size.h) | \(nombre($0.visualTokens))" } ?? "— | —"
            let f = full.map { "`\(nomFichier($0))` \($0.size.w)×\($0.size.h) | \(nombre($0.visualTokens))" } ?? "— | —"
            s += "| \(marque.number) | \(c) | \(f) |\n"
            totalCrop += crop?.visualTokens ?? 0
            totalFull += full?.visualTokens ?? 0
        }
        s += "| | **Total recadrages** | **\(nombre(totalCrop))** | **Total fenêtres** | **\(nombre(totalFull))** |\n\n"

        // ── Suite ──
        s += "## Suite\n\n"
        s += "1. Applique marque par marque. En cas d'ambiguïté, charge le **recadrage**, pas la fenêtre.\n"
        s += "2. Un commit par marque facilite la relecture.\n"
        if web {
            s += "3. Réponds par la liste des marques traitées, pour pointage manuel.\n"
        } else {
            s += "3. Termine par `resolve_feedback(number: \(m.session.number), status: \"handled\", note: \"…\")`.\n"
        }
        return s
    }

    // MARK: - Briques de formatage, locales et déterministes

    private static func ligneCapture(_ role: String, _ f: Manifeste.Frame, web: Bool) -> String {
        if web {
            // Pas de chemin absolu dans un bloc destiné à un chat web : le
            // fichier s'y joint à la main, le nom suffit à le retrouver.
            return "- \(role) : \(nomFichier(f)) — \(f.size.w)×\(f.size.h) px (à joindre manuellement)"
        }
        return "- \(role) : `\(f.absolutePath)` — \(f.size.w)×\(f.size.h) px, **\(nombre(f.visualTokens)) jetons**"
    }

    private static func nomFichier(_ f: Manifeste.Frame) -> String {
        (f.absolutePath as NSString).lastPathComponent
    }

    /// Les intentions du produit, vers leur libellé de rapport. Une intention
    /// inconnue passe telle quelle : le rendu ne censure pas ce qu'il ne
    /// connaît pas.
    private static func libelle(_ intents: [String]) -> String {
        let table = [
            "alignement": "mal aligné",
            "a-revoir": "à revoir",
            "ne-marche-pas": "ne marche pas",
            "lent": "lent",
            "texte-a-corriger": "texte à corriger",
        ]
        guard let premier = intents.first else { return "sans intention" }
        return table[premier] ?? premier
    }

    private static let mois = ["janvier", "février", "mars", "avril", "mai", "juin",
                               "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

    /// « 19 août 2026, 14 h 32 » depuis l'ISO 8601 du manifeste, dans le fuseau
    /// QUE LA CHAÎNE PORTE — pas celui de la machine qui rend.
    static func date(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        var secondes = 0
        if let m = iso.range(of: #"[+-]\d\d:\d\d$"#, options: .regularExpression) {
            let z = iso[m]
            let signe = z.hasPrefix("-") ? -1 : 1
            let h = Int(z.dropFirst().prefix(2)) ?? 0
            let mn = Int(z.suffix(2)) ?? 0
            secondes = signe * (h * 3600 + mn * 60)
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: secondes) ?? .gmt
        let c = cal.dateComponents([.day, .month, .year, .hour, .minute], from: d)
        return "\(c.day!) \(mois[c.month! - 1]) \(c.year!), \(c.hour!) h \(String(format: "%02d", c.minute!))"
    }

    /// « 2 min 14 s » — arrondi à la seconde inférieure, comme un chronomètre.
    static func duree(_ secondes: Double) -> String {
        let total = Int(secondes)
        return total < 60 ? "\(total) s" : "\(total / 60) min \(total % 60) s"
    }

    /// « 00:21 » — position dans la session.
    static func mmss(_ t: Double) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    /// Milliers séparés par une espace : « 1 457 ». À la main — un
    /// NumberFormatter suivrait la locale de la machine, et l'empreinte est le
    /// contrat.
    static func nombre(_ n: Int) -> String {
        let chiffres = String(n)
        guard chiffres.count > 3 else { return chiffres }
        var sortie = ""
        for (i, c) in chiffres.enumerated() {
            if i > 0 && (chiffres.count - i) % 3 == 0 { sortie += " " }
            sortie.append(c)
        }
        return sortie
    }

    /// Une citation en blockquote, repliée à 92 colonnes — la largeur du reste
    /// du rapport. Le repli est déterministe : le même texte rend les mêmes
    /// octets, sur toutes les machines.
    static func citation(_ texte: String) -> String {
        // Les guillemets français encadrent la citation (§ 9.4) : ce qui est
        // entre eux a été DIT, le reste du rapport est écrit par l'outil.
        replier("« \(texte) »", largeur: 92, premier: "> ", suivants: "> ")
    }

    /// Une puce de commentaire général : `- **01:52** — « … »`.
    static func puce(_ temps: String, _ texte: String) -> String {
        replier("**\(temps)** — « \(texte) »", largeur: 92, premier: "- ", suivants: "  ")
    }

    /// Repli sur les espaces, sans jamais couper un mot. Un mot plus long que
    /// la largeur tient seul sur sa ligne plutôt que d'être tronqué.
    private static func replier(_ texte: String, largeur: Int,
                                premier: String, suivants: String) -> String {
        var lignes: [String] = []
        var courante = premier
        var vide = true
        for mot in texte.split(separator: " ", omittingEmptySubsequences: true) {
            if !vide, courante.count + 1 + mot.count > largeur {
                lignes.append(courante)
                courante = suivants + mot
            } else {
                courante += (vide ? "" : " ") + mot
                vide = false
            }
        }
        lignes.append(courante)
        return lignes.joined(separator: "\n")
    }

    private static func entier(_ v: Double) -> String {
        // Arrondi au dixième AVANT le test d'intégrité : le bruit flottant d'un
        // produit bbox × écran (« 300.00000000000006 pt », défaut D-03 de la
        // recette du lot 4) n'est pas une fraction à montrer au lecteur.
        let dixieme = (v * 10).rounded() / 10
        return dixieme == dixieme.rounded() ? String(Int(dixieme)) : String(dixieme)
    }
}
