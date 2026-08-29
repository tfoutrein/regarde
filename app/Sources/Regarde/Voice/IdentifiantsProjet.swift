import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Les identifiants du projet — S68, § 7.3
//
// Le lexique figé couvre le vocabulaire commun ; ce qui manque, c'est le
// vocabulaire de CE projet — les noms de composants, de routes, de props qu'on
// prononce en testant et que le moteur n'a jamais entendus. Le projet est déjà
// connu : S52 l'a détecté, S53 le publie dedans.
//
// L'extraction est BORNÉE, et il faut qu'elle le soit : elle tourne au moment
// de la publication, dans le budget de 20 s du § 6.6. Plafonds sur le nombre
// de fichiers lus, la taille de chacun, la profondeur, et les répertoires
// qu'on ne visite jamais — `node_modules` contient plus d'identifiants que le
// projet n'en a de lignes.
// ─────────────────────────────────────────────────────────────────────────────

enum IdentifiantsProjet {

    /// Ce qu'on ne visite jamais : ni les dépendances, ni les artefacts, ni
    /// l'historique.
    static let ignores: Set<String> = [
        "node_modules", ".git", ".build", "dist", "build", "out", "vendor",
        "target", "coverage", ".next", ".nuxt", ".svelte-kit", "Pods",
        "DerivedData", ".venv", "venv", "__pycache__", ".regarde",
    ]

    /// Les extensions qui portent du vocabulaire de domaine.
    static let extensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "vue", "svelte", "kt", "java",
        "py", "rb", "go", "rs", "php", "cs", "scss", "css",
    ]

    /// Les mots trop communs pour désigner quoi que ce soit.
    static let bruit: Set<String> = [
        "true", "false", "null", "undefined", "return", "const", "function",
        "import", "export", "default", "class", "public", "private", "static",
        "string", "number", "boolean", "void", "async", "await", "this", "self",
        "value", "index", "item", "data", "result", "error", "type", "name",
    ]

    /// Découpe un identifiant composé en mots prononçables — `CheckoutForm`
    /// donne aussi `Checkout` et `Form`, qu'on prononce séparément.
    static func decomposer(_ identifiant: String) -> [String] {
        var mots: [String] = []
        var courant = ""
        for c in identifiant {
            if c.isUppercase, !courant.isEmpty, courant.last?.isUppercase == false {
                mots.append(courant); courant = String(c)
            } else if c == "_" || c == "-" {
                if !courant.isEmpty { mots.append(courant); courant = "" }
            } else {
                courant.append(c)
            }
        }
        if !courant.isEmpty { mots.append(courant) }
        return mots
    }

    /// Les identifiants d'un texte source — PURE, c'est elle qu'on teste.
    static func extraire(de source: String) -> [String] {
        var trouves: [String] = []
        var courant = ""
        func verser() {
            defer { courant = "" }
            guard courant.count >= 4 else { return }
            guard !bruit.contains(courant.lowercased()) else { return }
            // Un identifiant COMPOSÉ vaut aussi par ses parties.
            let parties = decomposer(courant)
            if parties.count > 1 {
                trouves.append(courant)
                trouves.append(contentsOf: parties.filter { $0.count >= 4 && !bruit.contains($0.lowercased()) })
            } else {
                trouves.append(courant)
            }
        }
        for c in source {
            if c.isLetter || c == "_" || (c.isNumber && !courant.isEmpty) { courant.append(c) }
            else { verser() }
        }
        verser()
        return trouves
    }

    /// Les identifiants les plus fréquents d'un projet, plafonnés.
    static func lire(racine: URL, maxFichiers: Int = 300, maxTermes: Int = 300,
                     maxOctetsParFichier: Int = 200_000) -> [String] {
        let fm = FileManager.default
        guard let iterateur = fm.enumerator(
            at: racine, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var frequences: [String: Int] = [:]
        var lus = 0
        for cas in iterateur {
            guard let url = cas as? URL else { continue }
            if ignores.contains(url.lastPathComponent) {
                iterateur.skipDescendants()
                continue
            }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            guard lus < maxFichiers else { break }
            guard let donnees = try? Data(contentsOf: url, options: .mappedIfSafe),
                  donnees.count <= maxOctetsParFichier,
                  let texte = String(data: donnees, encoding: .utf8) else { continue }
            lus += 1
            for identifiant in extraire(de: texte) {
                frequences[identifiant, default: 0] += 1
            }
        }
        // Les plus fréquents d'abord : ce qu'on prononce est ce qui revient.
        return frequences.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(maxTermes).map(\.key)
    }
}
