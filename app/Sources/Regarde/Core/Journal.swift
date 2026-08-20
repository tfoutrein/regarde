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

    static func section(_ title: String, _ lines: [String]) {
        write("\n" + title + "\n" + String(repeating: "─", count: title.count))
        for l in lines { write("  " + l) }
    }
}
