import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// Le publieur — S50, spécification § 9.2
//
// UNE porte vers le projet, comme AppendOnlyLog est LA porte vers write(2).
// Tout ce qui atterrit dans `<projet>/.regarde/` passe ici : l'arborescence, le
// `.gitignore`, l'attribution du numéro, le manifeste et ses rendus. Un fichier
// écrit ailleurs est un fichier que `git status` révélera dans un dépôt client —
// le critère du lot le dit : « zéro fichier hors du projet attendu ».
//
// LA RACINE EST UN PARAMÈTRE. C'est ce qui rend tout vérifiable sur un dépôt
// fabriqué dans `$TMPDIR` — pas de projet réel sacrifié aux tests, pas de test
// qui simule au lieu d'écrire.
//
// LE NUMÉRO S'ATTRIBUE EN `publishing`, PAS À t0 (§ 9.2). L'identité de toute
// la vie de la session est l'UUID (celui de SecureWorkspace, S47) ; le numéro
// est un nom de guichet, pris au moment d'écrire, sous verrou `fcntl` sur
// `index.jsonl` : lire le dernier numéro, prendre le suivant, écrire sa ligne —
// une section critique, un seul verrou, et deux PROCESSUS ne peuvent pas
// obtenir le même numéro.
//
// `fcntl` (F_SETLKW) et non `flock`, DÉLIBÉRÉMENT : ces verrous sont par
// processus — deux demandes du même processus sont toutes deux accordées. C'est
// exactement pourquoi l'autotest de S50 exige deux processus réels : un test
// mono-processus passerait au vert sur un verrou qui n'a jamais retenu personne.
//
// `metrics.jsonl` ne passe PAS par ici : ce sont des données d'usage
// personnelles (S46), elles vivent hors projet — voir `Metriques`.
// ─────────────────────────────────────────────────────────────────────────────

enum Publieur {

    enum Erreur: Error, CustomStringConvertible {
        case verrou(errno: Int32)
        case index(String)

        var description: String {
            switch self {
            case .verrou(let e): "verrou d'index impossible — \(String(cString: strerror(e)))"
            case .index(let m): "index illisible — \(m)"
            }
        }
    }

    struct Attribution {
        let numero: Int
        let id: String            // « 0043-20260824-2151-checkout »
        let dossier: URL          // <racine>/.regarde/sessions/<id>/
    }

    // MARK: - L'arborescence

    /// Crée `.regarde/` et son `.gitignore` s'ils manquent. Idempotent.
    ///
    /// Le contenu du `.gitignore` est celui du § 9.2, au caractère : les frames
    /// et le presse-papiers web ne se versionnent pas, `manifest.json` et
    /// `report.md` si — moins de 25 Kio par session, c'est le seuil n°6.
    @discardableResult
    static func preparer(racine: URL) throws -> URL {
        let regarde = racine.appendingPathComponent(".regarde", isDirectory: true)
        try FileManager.default.createDirectory(
            at: regarde.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true)
        let gitignore = regarde.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: gitignore.path) {
            let contenu = """
            sessions/*/frames/
            sessions/*/context/
            sessions/*/paste-web.md
            state.jsonl
            """
            try Data((contenu + "\n").utf8).write(to: gitignore, options: .atomic)
        }
        return regarde
    }

    // MARK: - Le numéro, sous verrou

    /// Attribue le prochain numéro et écrit la ligne d'index, en une section
    /// critique `fcntl`. Ne crée PAS le dossier de session — l'attribution est
    /// un guichet, pas un déménagement.
    static func attribuer(racine: URL, uuid: UUID, date: Date, slug: String?) throws -> Attribution {
        let regarde = try preparer(racine: racine)
        let index = regarde.appendingPathComponent("index.jsonl")

        let fd = open(index.path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw Erreur.verrou(errno: errno) }
        defer { close(fd) }

        // F_SETLKW : on ATTEND le verrou — l'autre processus est en train
        // d'attribuer, son écriture dure des microsecondes, l'attente est le bon
        // comportement. Verrou d'écriture sur tout le fichier.
        var verrou = flock(l_start: 0, l_len: 0, l_pid: 0,
                           l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        while fcntl(fd, F_SETLKW, &verrou) == -1 {
            guard errno == EINTR else { throw Erreur.verrou(errno: errno) }
        }
        defer {
            verrou.l_type = Int16(F_UNLCK)
            _ = fcntl(fd, F_SETLK, &verrou)
        }

        // Sous le verrou : lire tout, prendre le max, écrire la ligne — sur LE
        // MÊME descripteur. Un second open perdrait la garantie que ce qu'on a
        // lu est encore vrai au moment d'écrire.
        let taille = lseek(fd, 0, SEEK_END)
        lseek(fd, 0, SEEK_SET)
        var contenu = Data(count: Int(taille))
        if taille > 0 {
            let lus = contenu.withUnsafeMutableBytes { read(fd, $0.baseAddress, Int(taille)) }
            guard lus == taille else { throw Erreur.index("lecture partielle") }
        }
        var dernier = 0
        for ligne in String(decoding: contenu, as: UTF8.self).split(separator: "\n") {
            guard let data = ligne.data(using: .utf8),
                  let objet = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let n = objet["number"] as? Int else {
                throw Erreur.index("ligne non JSON : \(ligne.prefix(60))")
            }
            dernier = max(dernier, n)
        }

        let numero = dernier + 1
        let id = identifiant(numero: numero, date: date, slug: slug)
        let ligne = #"{"number":\#(numero),"uuid":"\#(uuid.uuidString)","id":"\#(id)","at":"\#(iso(date))"}"# + "\n"
        lseek(fd, 0, SEEK_END)
        let resultat = AppendOnlyLog.ecrireTout(Array(ligne.utf8)) { p, n in write(fd, p, n) }
        if case .echec(let e) = resultat { throw Erreur.verrou(errno: e) }

        return Attribution(numero: numero, id: id,
                           dossier: regarde.appendingPathComponent("sessions/\(id)", isDirectory: true))
    }

    // MARK: - La publication complète

    /// Écrit une session entière : dossier, `manifest.json`, `report.md`,
    /// `paste-web.md` et `frames/`. Le manifeste reçu porte un numéro et un id
    /// PROVISOIRES : ils sont remplacés par l'attribution — c'est la traduction
    /// concrète de « le numéro s'attribue en publishing ».
    @discardableResult
    static func publier(racine: URL, manifeste brouillon: Manifeste.Racine,
                        uuid: UUID, date: Date, slug: String?) throws -> Attribution {
        let attribution = try attribuer(racine: racine, uuid: uuid, date: date, slug: slug)

        var manifeste = brouillon
        manifeste.session.number = attribution.numero
        manifeste.session.id = attribution.id
        manifeste.session.uuid = uuid.uuidString

        let fm = FileManager.default
        try fm.createDirectory(at: attribution.dossier.appendingPathComponent("frames"),
                               withIntermediateDirectories: true)

        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encodeur.encode(manifeste)
            .write(to: attribution.dossier.appendingPathComponent("manifest.json"), options: .atomic)
        try Data(Rendu.rendre(manifeste).utf8)
            .write(to: attribution.dossier.appendingPathComponent("report.md"), options: .atomic)
        try Data(Rendu.rendre(manifeste, options: .init(profil: .chatWeb)).utf8)
            .write(to: attribution.dossier.appendingPathComponent("paste-web.md"), options: .atomic)

        return attribution
    }

    // MARK: - Identité

    /// « 0043-20260824-2151-checkout » — numéro sur 4, date-heure, slug.
    static func identifiant(numero: Int, date: Date, slug: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var id = String(format: "%04d-%04d%02d%02d-%02d%02d",
                        numero, c.year!, c.month!, c.day!, c.hour!, c.minute!)
        if let s = slug.map(Self.slug), !s.isEmpty { id += "-\(s)" }
        return id
    }

    /// La règle de S46 : `[a-z0-9-]`, 24 caractères au plus, jamais un tiret
    /// pendu. Une branche `feat/Checkout Coupon!` devient `feat-checkout-coupon`.
    ///
    /// Les diacritiques se PLIENT avant de filtrer — `écran` devient `ecran`,
    /// pas `cran` : la règle limite l'alphabet, elle n'ampute pas les mots. Le
    /// pliage est fait avec une locale EXPLICITE : celle de la machine rendrait
    /// deux slugs pour une même branche sur deux postes.
    static func slug(_ brut: String) -> String {
        let plie = brut.folding(options: [.diacriticInsensitive],
                                locale: Locale(identifier: "fr_FR"))
        var sortie = ""
        for scalaire in plie.lowercased().unicodeScalars {
            if (scalaire.value >= 97 && scalaire.value <= 122)
                || (scalaire.value >= 48 && scalaire.value <= 57) {
                sortie.unicodeScalars.append(scalaire)
            } else if !sortie.hasSuffix("-") && !sortie.isEmpty {
                sortie += "-"
            }
        }
        while sortie.hasSuffix("-") { sortie.removeLast() }
        return String(sortie.prefix(24)).hasSuffix("-")
            ? String(String(sortie.prefix(24)).dropLast())
            : String(sortie.prefix(24))
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Les métriques du GO/NO-GO — hors projet, décision S46 (trou n°4 du § 9.2)
// ─────────────────────────────────────────────────────────────────────────────

enum Metriques {
    /// `~/Library/Application Support/Regarde/metrics.jsonl` — des données
    /// d'usage PERSONNELLES : jamais dans un projet, jamais versionnées, jamais
    /// servies par MCP. La base est paramétrable pour la même raison que la
    /// racine du publieur : tout se vérifie sur un répertoire fabriqué.
    static func url(base: URL? = nil) throws -> URL {
        let support = try base ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dossier = support.appendingPathComponent("Regarde", isDirectory: true)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent("metrics.jsonl")
    }

    /// Ajoute un événement, horodaté ici même — par LA porte de S47. Chaque
    /// écriture ouvre et referme : les événements sont rares (quelques-uns par
    /// session) et un descripteur ouvert en permanence survivrait mal aux
    /// suspensions. Les échecs sont silencieux par principe (P5) mais comptés
    /// au journal — des métriques qui se perdent sans bruit rendraient le
    /// GO/NO-GO aveugle sans que personne le sache.
    static func enregistrer(_ champs: [String: Any], base: URL? = nil) {
        var enrichis = champs
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        enrichis["at"] = f.string(from: Date())
        do {
            let data = try JSONSerialization.data(withJSONObject: enrichis, options: [.sortedKeys])
            let log = try AppendOnlyLog(url: try url(base: base))
            try log.append(ligne: String(decoding: data, as: UTF8.self))
            log.fermer()
        } catch {
            Task { @MainActor in
                Journal.warn(.system, "métrique perdue — \(error)")
            }
        }
    }
}
