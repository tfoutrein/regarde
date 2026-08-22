import CoreGraphics
import Foundation
import ScreenCaptureKit
import os

// ─────────────────────────────────────────────────────────────────────────────
// Le moteur de capture — S34
//
// Un flux PAR ÉCRAN, et un acteur qui les tient. La raison pour laquelle ce n'est
// pas un simple tableau dans le coordinateur est au § 5.5 : chaque flux se
// finalise INDÉPENDAMMENT, avec capture d'erreur par segment. Un writer ouvert
// pour un écran débranché immédiatement n'a aucun échantillon et échoue sur
// `AVError.noSourceTrack` ; dans une séquence `try` linéaire, la session entière
// serait perdue, y compris les marques d'un autre écran qui, elles, sont
// complètes.
//
// Les écrans ÉCARTÉS (S33) n'ont pas de flux. Ce n'est pas une omission : ouvrir
// un flux sur un écran en recopie vidéo produirait des images d'une surface que
// l'utilisateur ne regardait pas.
// ─────────────────────────────────────────────────────────────────────────────

actor CaptureEngine {
    static let shared = CaptureEngine()

    private let log = Logger(subsystem: logSubsystem, category: "moteur")
    private var flux: [CGDirectDisplayID: DisplayStream] = [:]
    private var debut: Date?

    var actif: Bool { !flux.isEmpty }
    var displaysActifs: [CGDirectDisplayID] { flux.keys.sorted() }

    /// Ouvre un flux par écran capturable. Rend le motif d'échec, ou `nil`.
    ///
    /// **Échoue si AUCUN écran ne démarre**, pas si l'un d'eux échoue. Un poste à
    /// deux écrans dont l'externe refuse la capture doit pouvoir enregistrer
    /// l'interne : refuser la session entière punirait l'utilisateur pour un écran
    /// dont il ne se servait peut-être pas.
    func demarrer(geometry: ScreenGeometry) async -> String? {
        await arreter(raison: .basculePreRoll)

        let cibles = geometry.capturables.map { CGDirectDisplayID($0.displayID) }
        guard !cibles.isEmpty else { return "aucun écran capturable" }

        var echecs: [String] = []
        for id in cibles {
            let s = DisplayStream(displayID: id)
            do {
                try await s.demarrer()
                flux[id] = s
            } catch {
                echecs.append("display \(id) : \(error)")
            }
        }
        guard !flux.isEmpty else {
            return echecs.joined(separator: " · ")
        }
        // Un écran manquant sur plusieurs se dit, sans faire échouer la session.
        if !echecs.isEmpty {
            let liste = echecs.joined(separator: " · ")
            await MainActor.run { Journal.warn(.capture, "écran(s) sans flux — \(liste)") }
        }
        debut = Date()
        return nil
    }

    func arreter(raison: StopReason) async {
        guard !flux.isEmpty else { return }
        let duree = debut.map { Date().timeIntervalSince($0) } ?? 0
        // Chaque flux se ferme INDÉPENDAMMENT : l'échec de l'un ne doit jamais
        // emporter les autres (§ 5.5).
        for (_, s) in flux {
            await s.arreter(raison: raison)
            let lignes = s.bilan(duree: duree)
            await MainActor.run { Journal.block("FLUX", lignes) }
        }
        flux.removeAll()
        debut = nil
        SessionClock.shared.oublierHorlogeDeFlux()
    }

    /// Arrête le flux d'un seul écran — débranchement à chaud (§ 5.5, S36).
    func arreterEcran(_ id: CGDirectDisplayID, raison: StopReason) async {
        guard let s = flux.removeValue(forKey: id) else { return }
        let duree = debut.map { Date().timeIntervalSince($0) } ?? 0
        await s.arreter(raison: raison)
        let lignes = s.bilan(duree: duree)
        await MainActor.run { Journal.block("FLUX", lignes) }
    }

    /// Reconstruit les filtres de tous les flux.
    ///
    /// Le canal de reconfiguration : l'ouverture d'une application de la liste
    /// noire en cours de session doit l'exclure des images à partir de cet
    /// instant. Sans lui, l'exclusion ne vaudrait que pour ce qui tournait déjà au
    /// démarrage — et un gestionnaire de mots de passe s'ouvre précisément
    /// pendant qu'on teste.
    func rafraichirFiltres() async {
        for (_, s) in flux { await s.rafraichirFiltre() }
    }

    /// Les statistiques par écran, pour le journal et le banc.
    func bilans() -> [(CGDirectDisplayID, StreamStats)] {
        flux.map { ($0.key, $0.value.stats) }.sorted { $0.0 < $1.0 }
    }
}
