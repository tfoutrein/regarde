import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le lexique déterministe — S68, § 7.3 et ADR-0012
//
// `contextualStrings` n'a AUCUN effet mesurable (A/B strict, ADR-0012) : le
// moteur ne se laisse pas guider. Ce qui reste possible, c'est de proposer
// APRÈS coup — et seulement là où le moteur doute lui-même.
//
// DEUX PORTES, et il faut les passer toutes les deux :
//
//   LA CONFIANCE. Seuls les mots sous 0,6 sont candidats. C'est la porte qui
//   rend l'ensemble sûr : « bouton » et « button » ont le même squelette
//   phonétique, mais « bouton » dans une phrase française sort à confiance
//   haute et n'est jamais soumis au lexique.
//
//   LA RESSEMBLANCE. Le squelette phonétique doit être proche (Phonetique).
//
// Et la proposition n'écrase RIEN : les deux versions vont au rapport —
// `*pratique* **[padding ?]**` — parce que seule la relecture humaine sait
// laquelle est la bonne. `rawText` reste intact quoi qu'il arrive.
//
// La limite, écrite ici plutôt que découverte : une erreur phonétiquement
// LOINTAINE — « Tou » pour « timeout », « ste » pour « state » — n'est pas
// rattrapée. Elle reste visible autrement : le moteur lui donne une confiance
// basse, et le mot lu de travers saute aux yeux dans la citation.
// ─────────────────────────────────────────────────────────────────────────────

enum Lexique {

    /// Le seuil de confiance sous lequel un mot devient candidat (§ 7.3).
    static let seuilConfiance = 0.6

    /// Les termes du front, figés. Ni exhaustifs ni savants : ceux qu'on
    /// prononce en testant une interface, et que le moteur écorche.
    static let termesFront: [String] = [
        // Mise en page et style
        "padding", "margin", "border", "flexbox", "grid", "gap", "overflow",
        "z-index", "viewport", "breakpoint", "responsive", "layout", "wrapper",
        "container", "sticky", "absolute", "relative", "inline", "block",
        "opacity", "hover", "focus", "placeholder", "tooltip", "dropdown",
        "modale", "modal", "popover", "toast", "spinner", "skeleton", "carousel",
        "sidebar", "navbar", "footer", "header", "breadcrumb", "accordion",
        "checkbox", "radio", "toggle", "slider", "stepper", "badge", "chip",
        "scroll", "sticky", "backdrop", "overlay", "shadow", "gradient",
        // React et compagnie
        "useEffect", "useState", "useCallback", "useMemo", "useRef", "useContext",
        "useReducer", "props", "state", "context", "provider", "reducer",
        "dispatch", "render", "rerender", "mount", "unmount", "hook", "hooks",
        "component", "composant", "callback", "ref", "key", "children",
        "fragment", "portal", "suspense", "lazy", "memo", "virtual", "diffing",
        // Réseau, données
        "endpoint", "payload", "request", "response", "fetch", "axios", "query",
        "mutation", "GraphQL", "REST", "API", "websocket", "polling", "webhook",
        "timeout", "retry", "cache", "invalidation", "pagination", "offset",
        "cursor", "token", "bearer", "cookie", "session", "CORS", "preflight",
        "middleware", "proxy", "backend", "frontend", "serverless", "edge",
        // Outillage
        "build", "bundle", "bundler", "webpack", "vite", "rollup", "esbuild",
        "transpile", "polyfill", "minify", "sourcemap", "hotreload", "watcher",
        "linter", "eslint", "prettier", "typescript", "javascript", "tsconfig",
        "npm", "yarn", "pnpm", "monorepo", "workspace", "dependency", "devDependency",
        // Test et qualité
        "snapshot", "mock", "stub", "fixture", "coverage", "assertion",
        "playwright", "cypress", "jest", "vitest", "storybook", "regression",
        // Accessibilité et sémantique
        "accessibilité", "aria", "tabindex", "screenreader", "contraste",
        "sémantique", "landmark", "alt", "label", "fieldset", "legend",
        // Le domaine qu'on teste le plus souvent
        "checkout", "panier", "commande", "paiement", "livraison", "facture",
        "connexion", "inscription", "profil", "réglages", "tableau de bord",
        "formulaire", "validation", "erreur", "avertissement", "confirmation",
        // Git et déploiement
        "commit", "branche", "merge", "rebase", "conflit", "pipeline",
        "déploiement", "staging", "production", "rollback", "feature flag",
    ]

    /// Une proposition, avec de quoi la juger.
    struct Suggestion: Codable, Equatable, Sendable {
        let entendu: String
        let propose: String
        let confiance: Double
        let instant: Double
    }

    /// Le résultat : le texte MARQUÉ et les propositions faites.
    struct Resultat: Equatable, Sendable {
        let texte: String
        let suggestions: [Suggestion]
    }

    /// Applique le lexique à un segment. PURE — c'est elle que l'autotest juge.
    ///
    /// `mots` porte la confiance de chaque mot ; `termes` est le lexique
    /// (front + identifiants du projet). Un mot sans confiance connue n'est
    /// JAMAIS candidat : ne pas savoir n'est pas douter.
    static func appliquer(texte: String, mots: [Mot], termes: [String]) -> Resultat {
        var suggestions: [Suggestion] = []
        var remplacements: [String: String] = [:]

        for mot in mots {
            guard let confiance = mot.confiance, confiance < seuilConfiance else { continue }
            let nu = mot.texte.trimmingCharacters(
                in: CharacterSet.alphanumerics.inverted)
            guard nu.count >= 2, remplacements[nu] == nil else { continue }
            // Le meilleur candidat, pas le premier : deux termes peuvent être
            // proches, et proposer au hasard serait pire que de se taire.
            //
            // À ÉGALITÉ PHONÉTIQUE, l'orthographe tranche. « modèle » sonne
            // exactement comme « modal » ET comme « modale » ; c'est
            // « modale » qu'il faut proposer, parce que c'est celui dont
            // l'écriture ressemble à ce qui a été transcrit — le moteur a
            // entendu juste et écrit de travers, pas l'inverse.
            let squeletteNu = Phonetique.squelette(nu)
            func rang(_ terme: String) -> (Int, Int, String) {
                (Phonetique.levenshtein(squeletteNu, Phonetique.squelette(terme)),
                 Phonetique.levenshtein(nu.lowercased(), terme.lowercased()),
                 terme)
            }
            guard let meilleur = termes.filter({ Phonetique.proche(nu, $0) })
                .min(by: { rang($0) < rang($1) }) else { continue }
            // Un terme IDENTIQUE n'est pas une correction. La casse, elle, en
            // est une : « promocode » entendu pour `promoCode` doit donner à
            // l'agent l'identifiant exact, qu'il ira chercher dans le code.
            guard meilleur != nu else { continue }
            remplacements[nu] = meilleur
            suggestions.append(Suggestion(entendu: nu, propose: meilleur,
                                          confiance: confiance,
                                          instant: mot.debut.seconds))
        }

        guard !suggestions.isEmpty else { return Resultat(texte: texte, suggestions: []) }

        // Le marquage : `*entendu* **[proposé ?]**`, § 9.4. Les DEUX versions,
        // jamais l'une à la place de l'autre — la relecture tranche.
        var marque = texte
        for (entendu, propose) in remplacements {
            marque = marque.replacingOccurrences(
                of: entendu, with: "*\(entendu)* **[\(propose) ?]**")
        }
        return Resultat(texte: marque, suggestions: suggestions)
    }
}
