import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Export des mesures — alimente RESULTATS.md
//
// « Un critere non mesure est un critere echoue » (§ 4.6). Ce fichier existe pour
// que remplir le tableau des douze criteres ne demande pas de recopier des nombres
// a la main depuis un journal.
// ─────────────────────────────────────────────────────────────────────────────

enum RunReport {

    /// Repertoire des sorties. Sous `~/Regarde-lot0/`, pas dans le depot : ces
    /// fichiers sont des mesures d'une machine et d'un instant, pas du code.
    static let outputDirectory: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Regarde-lot0", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func json() async -> String {
        let latency = LatencyHistogram.shared.json()
        let bench = await SnapshotBench.shared.shotsJSON()
        let tap = EventTap.shared

        let screens = await MainActor.run {
            NSScreen.screens.map { s -> String in
                let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                    .uint32Value ?? 0
                return """
                    { "displayID": \(id), "scale": \(s.backingScaleFactor), \
                "frame": [\(Int(s.frame.minX)), \(Int(s.frame.minY)), \
                \(Int(s.frame.width)), \(Int(s.frame.height))] }
                """
            }.joined(separator: ",\n")
        }

        let strokes = await MainActor.run { OverlayController.shared.totalStrokes }
        let panels = await MainActor.run { OverlayController.shared.panelCount }

        let text = """
        {
          "outil": "regarde-lot0",
          "genereLe": "\(ISO8601DateFormatter().string(from: Date()))",
          "os": "\(ProcessInfo.processInfo.operatingSystemVersionString)",
          "tap": {
            "installe": \(tap.isInstalled),
            "actif": \(tap.isEnabled),
            "evenementsVus": \(tap.eventsSeen),
            "reArmements": \(tap.reArms),
            "pireCallbackMs": \(String(format: "%.4f", tap.worstCallbackMs)),
            "evenementsPerdus": \(InkRing.shared.droppedCount),
            "horodatagesEnRepli": \(SessionClock.shared.fallbackCount)
          },
          "porte": {
            "capturés": \(OptionGate.shared.captured),
            "laissesPasser": \(OptionGate.shared.passed)
          },
          "rendu": { "traits": \(strokes), "panneaux": \(panels) },
          "ecrans": [
        \(screens)
          ],
          "c7Latence": \(latency),
          "c11Captures": \(bench)
        }
        """

        let url = outputDirectory.appendingPathComponent("mesures.json")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return text + "\n\nEcrit dans \(url.path)"
    }

    /// Resume imprime au lancement : le contexte dans lequel toutes les mesures
    /// qui suivent ont ete prises.
    static func startupBanner() -> String {
        """

        ╭──────────────────────────────────────────────────────────────────╮
        │  Regarde — prototype du lot 0                                    │
        │  Valide le geste, et rien d'autre. Voir plan § 4.                │
        ╰──────────────────────────────────────────────────────────────────╯

        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Sorties : \(outputDirectory.path)

        Maintiens ⌥⌘ et glisse pour tracer. Relache pour rendre la souris.
        Échap annule le trait en cours · ⌥⌘Z supprime le dernier.

        Le menu ◎ de la barre de menus porte l'etat du tap et les rapports.
        """
    }
}
