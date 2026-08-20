import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Où atterrissent les artefacts d'une session — spécification § 8.2
//
// `~/Regarde/sessions/<horodatage>/` au lot 2. La détection du projet cible, qui
// déplacera ces fichiers dans le dépôt concerné, arrive au lot 3 : jusque-là un chemin
// fixe vaut mieux qu'une devinette, parce qu'un artefact écrit au mauvais endroit est un
// artefact que personne ne retrouve.
//
// L'horodatage est en heure locale et trié par ordre lexicographique, ce qui rend
// `ls` chronologique sans outil. Les deux-points sont proscrits : ils restent un
// séparateur de chemin pour le Finder, qui les affiche comme des barres obliques.
// ─────────────────────────────────────────────────────────────────────────────

enum SessionPaths {

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Regarde/sessions", isDirectory: true)
    }

    /// Crée le répertoire d'une nouvelle session et le retourne.
    static func makeSessionDirectory(at date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dir = root.appendingPathComponent(formatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("frames"),
                                                withIntermediateDirectories: true)
        return dir
    }

    static func frames(of session: URL) -> URL {
        session.appendingPathComponent("frames", isDirectory: true)
    }
}
