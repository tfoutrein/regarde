import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// La porte unique vers write(2) — S47, ADR-0014, spécification § 3.7
//
// Tout ce que le produit écrit en append-only — `index.jsonl`, `state.jsonl`,
// `metrics.jsonl` — passe ICI. Une seule porte, parce que les pièges de write(2)
// sont assez fins pour qu'on ne veuille les traiter qu'une fois :
//
//   L'ATOMICITÉ N'EST PAS CELLE QU'ON CROIT. `PIPE_BUF` qualifie les tubes, pas
//   les fichiers réguliers. Sur un fichier ouvert en `O_APPEND`, c'est le verrou
//   de vnode qui rend un write(2) UNIQUE non entrelacé — sans limite des
//   512 octets, qui n'existe pas ici. La conclusion « pas de verrou nécessaire »
//   tiendrait… si un write(2) restait unique.
//
//   L'ÉCRITURE COURTE le casse. write(2) a le droit de rendre moins d'octets
//   qu'on lui en donne — pression mémoire, signal, limite de fichier. Il faut
//   alors BOUCLER, et entre deux tours de boucle, le vnode est rendu : un autre
//   processus peut s'y glisser. La boucle crée précisément l'entrelacement que
//   l'atomicité du write unique évitait.
//
//   `EINTR` n'est pas une erreur. Un signal pendant l'écriture rend -1/EINTR
//   sans avoir rien écrit : on recommence, sans compter cela comme un échec.
//
//   Les DOSSIERS SYNCHRONISÉS (Dropbox, iCloud) interceptent les fichiers par
//   des mécanismes où `O_APPEND` ne garantit plus rien du tout.
//
// La réponse aux trois derniers est la même : un `flock` CONSULTATIF autour de
// chaque ligne. Consultatif — il ne protège que contre ceux qui le prennent
// aussi, c'est-à-dire les autres instances de cette porte, et c'est exactement
// le périmètre : personne d'autre n'écrit ces fichiers. Il coûte quelques
// microsecondes par ligne sur le chemin de publication, où la ligne la plus
// fréquente s'écrit une fois par session. On le prend TOUJOURS, plutôt que de
// deviner si le dossier est synchronisé : un verrou inutile ne coûte rien, une
// détection de Dropbox ratée coûte une ligne déchirée dans un index.
//
// Le cœur — la boucle d'écriture — est une fonction PURE sur une fonction
// d'écriture injectée : l'autotest lui fait subir des écritures courtes et des
// EINTR fabriqués, et retirer la boucle fait rougir un test au lieu de corrompre
// un index six mois plus tard. La leçon de S43 : le producteur et le consommateur
// doivent être reliés par un test, sinon chacun est correct et l'ensemble est faux.
// ─────────────────────────────────────────────────────────────────────────────

final class AppendOnlyLog: @unchecked Sendable {

    enum Erreur: Error, CustomStringConvertible {
        case ouverture(chemin: String, errno: Int32)
        case ecriture(errno: Int32)
        case fermee

        var description: String {
            switch self {
            case .ouverture(let c, let e):
                "ouverture impossible — \(c) : \(String(cString: strerror(e)))"
            case .ecriture(let e):
                "écriture en erreur — \(String(cString: strerror(e)))"
            case .fermee:
                "porte déjà fermée"
            }
        }
    }

    private let fd: Int32
    /// Sérialise les appels d'un MÊME processus : le flock protège entre
    /// processus, pas entre threads d'un même processus — il est attaché à la
    /// description de fichier ouverte, que tous nos threads partagent.
    private let verrou = OSAllocatedUnfairLock(initialState: false)  // true = fermée
    let url: URL

    /// Ouvre — ou crée en 0600 — le fichier en append.
    ///
    /// `O_APPEND` et non un seek en fin : c'est le mode qui fait replacer le
    /// curseur en fin DANS le même verrou de vnode que l'écriture, la seule
    /// combinaison où deux processus n'écrasent pas mutuellement leurs fins de
    /// fichier.
    init(url: URL, permissions: mode_t = 0o600) throws {
        self.url = url
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, permissions)
        guard fd >= 0 else { throw Erreur.ouverture(chemin: url.path, errno: errno) }
        self.fd = fd
    }

    deinit { if !verrou.withLock({ $0 }) { close(fd) } }

    /// Ajoute UNE ligne, entière ou pas du tout, `\n` compris.
    ///
    /// Le `\n` est ajouté s'il manque — une « ligne » sans fin de ligne n'en est
    /// pas une, et l'oubli chez un appelant fusionnerait deux entrées d'index.
    func append(ligne: String) throws {
        var texte = ligne
        if !texte.hasSuffix("\n") { texte += "\n" }
        let octets = Array(texte.utf8)

        try verrou.withLock { fermee in
            guard !fermee else { throw Erreur.fermee }

            // Le flock ENGLOBE toute la boucle : si write(2) rend court, la
            // reprise se fait toujours sous le même verrou, et la ligne reste
            // d'un seul tenant même là où O_APPEND ne promet plus rien.
            while flock(fd, LOCK_EX) == -1 {
                guard errno == EINTR else { throw Erreur.ecriture(errno: errno) }
            }
            defer { flock(fd, LOCK_UN) }

            let resultat = Self.ecrireTout(octets) { pointeur, longueur in
                write(fd, pointeur, longueur)
            }
            if case .echec(let e) = resultat { throw Erreur.ecriture(errno: e) }
        }
    }

    /// Ferme la porte. Idempotent.
    func fermer() {
        verrou.withLock { fermee in
            guard !fermee else { return }
            fermee = true
            close(fd)
        }
    }

    // MARK: - Le cœur, testable sans fichier

    enum Resultat: Equatable {
        case succes(appels: Int)
        case echec(errno: Int32)
    }

    /// Écrit TOUT le tampon à travers `ecrire`, en bouclant sur les écritures
    /// courtes et en reprenant sur `EINTR`.
    ///
    /// `ecrire` a le contrat de write(2) : rend le nombre d'octets écrits, ou -1
    /// avec `errno` posé. La fonction rend le nombre d'appels réussis — c'est ce
    /// qui permet à l'autotest de PROUVER que la boucle a servi, plutôt que de
    /// constater une longueur finale qu'une écriture unique aurait aussi produite.
    static func ecrireTout(_ octets: [UInt8],
                           via ecrire: (UnsafeRawPointer, Int) -> Int) -> Resultat {
        var appels = 0
        var position = 0
        return octets.withUnsafeBytes { tampon in
            let base = tampon.baseAddress!
            while position < octets.count {
                let n = ecrire(base + position, octets.count - position)
                if n > 0 {
                    position += n
                    appels += 1
                } else if n == 0 {
                    // write(2) ne rend 0 que pour une demande de 0 octet — qu'on
                    // ne fait jamais. Le traiter comme un progrès nul infini
                    // serait une boucle éternelle ; c'est une erreur nommée.
                    return .echec(errno: EIO)
                } else if errno == EINTR {
                    continue
                } else {
                    return .echec(errno: errno)
                }
            }
            return .succes(appels: appels)
        }
    }
}
