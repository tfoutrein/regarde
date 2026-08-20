import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Répertoire de travail d'une session — ADR-0020, spécification § 10.2
//
// Le fichier vidéo intermédiaire contient TOUT l'écran : un gestionnaire de mots de
// passe ouvert à côté, une messagerie, un autre projet client. Il est le seul artefact
// du produit dont la fuite serait un incident plutôt qu'un bug.
//
// Quatre mesures, dont la première corrige un vrai défaut de la conception initiale :
//
//   1. `NSTemporaryDirectory()` et non `~/Library/Application Support`. Ce dernier est
//      inclus dans les sauvegardes Time Machine par défaut : une session qui plante y
//      laissait une copie permanente sur le disque de sauvegarde, que la purge à 24 h
//      ne touche jamais.
//   2. Répertoire en 0700, fichiers en 0600, création en `O_EXCL`.
//   3. Purge au démarrage de CHAQUE session, pas seulement au lancement — une
//      application qui tourne des jours ne purgerait jamais.
//   4. Suppression dès que les frames sont extraites (lot 3).
// ─────────────────────────────────────────────────────────────────────────────

enum SecureWorkspace {
    private static let log = Logger(subsystem: logSubsystem, category: "workspace")

    /// Racine des répertoires de session, sous `$TMPDIR`.
    ///
    /// `NSTemporaryDirectory()` est propre au conteneur de l'application, hors Time
    /// Machine, et purgé par le système — trois propriétés qu'aucun autre emplacement
    /// ne réunit.
    static var root: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("regarde", isDirectory: true)
    }

    // MARK: - Cycle de vie

    /// Prépare un répertoire pour une nouvelle session, après avoir purgé les précédents.
    ///
    /// La purge est faite ICI plutôt qu'au lancement : c'est le seul endroit qui garantit
    /// qu'aucun enregistrement d'une session passée ne survit à l'ouverture d'une nouvelle.
    @discardableResult
    static func beginSession(id: UUID = UUID()) throws -> URL {
        try purge()

        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try excludeFromBackup(dir)

        log.notice("répertoire de session prêt")
        return dir
    }

    /// Supprime tous les répertoires de session existants.
    @discardableResult
    static func purge() throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            try fm.createDirectory(at: root, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try excludeFromBackup(root)
            return 0
        }

        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for entry in entries {
            do {
                try fm.removeItem(at: entry)
                removed += 1
            } catch {
                // Un échec de purge n'empêche pas la session de démarrer, mais il doit
                // être visible : c'est un fichier contenant potentiellement tout l'écran
                // qui reste sur le disque.
                log.error("purge : \(entry.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }
        if removed > 0 { log.notice("purge : \(removed) élément(s) supprimé(s)") }
        return removed
    }

    /// Crée un fichier en 0600, en échouant si un fichier de ce nom existe déjà.
    ///
    /// `O_EXCL` ferme la course où un autre processus aurait déposé un lien symbolique
    /// à cet emplacement en prévision de l'écriture.
    static func createFile(at url: URL) throws -> FileHandle {
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "création refusée : \(String(cString: strerror(errno)))"
            ])
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// Marque un chemin comme exclu des sauvegardes.
    ///
    /// `$TMPDIR` en est déjà exclu ; c'est une ceinture de plus, sans coût, pour le cas
    /// où le répertoire migrerait un jour ailleurs.
    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    // MARK: - Diagnostic

    /// Vérifie que les garanties tiennent réellement, plutôt que de les supposer.
    static func audit() -> [String] {
        let fm = FileManager.default
        var lines: [String] = ["racine     \(root.path)"]

        guard let attrs = try? fm.attributesOfItem(atPath: root.path) else {
            lines.append("⚠ racine absente — sera créée à la première session")
            return lines
        }

        if let perms = attrs[.posixPermissions] as? NSNumber {
            let octal = String(perms.intValue, radix: 8)
            lines.append("permissions \(octal)\(perms.intValue == 0o700 ? "" : "  ⚠ attendu 700")")
        }

        let entries = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        lines.append("contenu    \(entries.count) élément(s)")

        let excluded = (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]))?
            .isExcludedFromBackup ?? false
        lines.append("sauvegarde \(excluded ? "exclu" : "non marqué — $TMPDIR l'exclut déjà")")

        return lines
    }
}
