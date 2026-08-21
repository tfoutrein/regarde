import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Journal sur disque
//
// Repris du lot 0, où il a été indispensable : `os_log` ne remonte rien pour ce bundle
// — vérifié à plusieurs reprises avec `log show` — et une application lancée par `open`
// n'a pas de sortie standard observable. Sans trace sur disque, son état réel n'est
// consultable par aucun moyen.
//
// Or c'est précisément en lancement normal que l'application porte sa vraie identité TCC,
// donc le seul mode où ses préflights disent la vérité. Le lot 0 a perdu du temps à
// diagnostiquer depuis un terminal, où le binaire hérite des autorisations du terminal
// parent et mesure la mauvaise identité.
//
// Le fichier est remis à zéro à chaque lancement : on veut l'état de CE démarrage, pas
// un historique dans lequel il faut chercher.
//
// ── Format ───────────────────────────────────────────────────────────────────
//
//   15:09:02  cible     figée sur Arc — (-971, -1440) 3440×1440
//   15:09:05  marque    1 · flèche · display 3
//   15:09:20  focus     Finder — les touches lui reviennent
//   15:09:31  ⚠ capture absente pour la marque 4
//
// Trois colonnes : l'heure, la catégorie, le fait. Le journal a d'abord grandi par
// accrétion, chaque site d'appel inventant son préfixe — « cible : », « marque N — »,
// « éclair — » — et les sessions s'y enchaînaient sans démarcation. On ne s'y retrouvait
// plus, ce qui est le seul défaut qu'un journal ne peut pas se permettre.
//
// L'heure compte autant que le reste : c'est elle qui permet de rapprocher une ligne d'un
// geste dont on se souvient.
// ─────────────────────────────────────────────────────────────────────────────

enum Journal {
    static let directory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Regarde", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var fileURL: URL { directory.appendingPathComponent("journal.txt") }

    private static let log = Logger(subsystem: logSubsystem, category: "journal")
    private static let queue = DispatchQueue(label: "dev.tfoutrein.regarde.journal")

    /// Nature d'un fait journalisé. Le libellé sert de colonne.
    enum Kind {
        case system, session, target, mark, tool, focus, key, capture

        var label: String {
            switch self {
            case .system: "système"
            case .session: "session"
            case .target: "cible"
            case .mark: "marque"
            case .tool: "outil"
            case .focus: "focus"
            case .key: "touche"
            case .capture: "capture"
            }
        }
    }

    /// Largeur de la colonne de catégorie. « capture » et « système » font 7 signes.
    private static let column = 9

    private static var stamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    /// Un fait ordinaire.
    static func event(_ kind: Kind, _ text: String) {
        let label = kind.label.padding(toLength: column, withPad: " ", startingAt: 0)
        write("\(stamp)  \(label)\(text)")
    }

    /// Un fait qui demande une décision, ou qui explique un comportement inattendu.
    ///
    /// Le marqueur remplace la colonne au lieu de s'y ajouter : un avertissement doit se
    /// repérer en parcourant la marge, pas en lisant les lignes.
    static func warn(_ kind: Kind, _ text: String) {
        write("\(stamp)  ⚠ \(kind.label) — \(text)")
    }

    /// Une démarcation. Sépare ce qui précède de ce qui suit.
    static func rule(_ title: String) {
        let bar = String(repeating: "─", count: max(4, 62 - title.count))
        write("\(stamp)  ── \(title) \(bar)")
    }

    /// Une liste sous une démarcation, une ligne par élément.
    static func list(_ title: String, _ lines: [String]) {
        rule(title)
        for line in lines { write("          " + line) }
    }

    /// Un bloc de valeurs alignées, sous une démarcation.
    static func block(_ title: String, _ pairs: [(String, String)]) {
        rule(title)
        let width = pairs.map(\.0.count).max() ?? 0
        for (key, value) in pairs {
            write("          " + key.padding(toLength: width + 3, withPad: " ", startingAt: 0)
                  + value)
        }
    }

    static func reset() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            let entete = """
            Regarde — journal de démarrage
            \(ISO8601DateFormatter().string(from: Date()))
            \(ProcessInfo.processInfo.operatingSystemVersionString)

            """
            try? entete.data(using: .utf8)?.write(to: fileURL)
        }
    }

    /// Écrit sur disque ET sur la sortie d'erreur, pour couvrir les deux modes de
    /// lancement sans avoir à choisir lequel on diagnostique.
    static func write(_ text: String) {
        let block = text.hasSuffix("\n") ? text : text + "\n"
        FileHandle.standardError.write(Data(block.utf8))
        log.info("\(text, privacy: .public)")

        queue.async {
            guard let data = block.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    /// Un bloc titré. Même rendu que `list` : le journal n'a qu'un seul style.
    ///
    /// Les blocs de démarrage — clavier, raccourcis, diagnostic — avaient le leur, sans
    /// horodatage et avec un soulignement à la largeur du titre. Deux mises en page dans
    /// un même fichier obligent l'œil à s'adapter à chaque bloc.
    static func section(_ title: String, _ lines: [String]) {
        list(title.uppercased(), lines)
    }
}
