import AVFoundation
import CoreMedia
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// L'encodage d'un segment — S35, ADR-0003, spécification § 5.5
//
// C'est ici que `firstSamplePTS` prend sa valeur, et c'est tout l'enjeu de B1.
// `startSession(atSourceTime:)` décide quel PTS devient le temps 0 du fichier ;
// le noter est la seule chose qui permettra plus tard de demander la BONNE frame.
// Sans lui, `AVAssetImageGenerator` rend systématiquement une image décalée de
// 0,3 à 3 s — invisible sur écran statique, systématique sur écran animé.
//
// TROIS RÈGLES, chacune contre un défaut nommé :
//
//   GOP forcé à 1 s          sans quoi le seek dans le fichier coûte le temps de
//                            remonter à l'image clé précédente, qui peut être à
//                            dix secondes. Avec, il coûte 31 ms, sous le seuil de
//                            perception (§ 5.2).
//
//   finalisation PAR SEGMENT un writer ouvert pour un écran débranché aussitôt
//                            n'a AUCUN échantillon, et `finishWriting()` échoue
//                            sur `AVError.noSourceTrack`. Dans une séquence `try`
//                            linéaire, la session entière serait perdue — y
//                            compris les marques d'un autre écran, qui sont
//                            complètes. Chaque segment se ferme seul, et son échec
//                            reste le sien.
//
//   manifeste À CÔTÉ du .mov le journal est remis à zéro à chaque lancement ; un
//                            banc en deux phases perdrait sa première. Les PTS
//                            doivent survivre au fichier, donc être écrits à côté
//                            de lui.
// ─────────────────────────────────────────────────────────────────────────────

final class SegmentWriter: @unchecked Sendable {

    private let log = Logger(subsystem: logSubsystem, category: "writer")

    let segment: CaptureSegmentID
    let displayID: CGDirectDisplayID
    let fileURL: URL

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var demarre = false
    private var premier: CMTime?
    private var dernier: CMTime?
    private var echantillons = 0
    private let debut: SessionTime

    /// Vrai tant que rien n'a été écrit. Un écran strictement figé reste ici :
    /// ScreenCaptureKit ne livre que sur changement.
    var vide: Bool { premier == nil }
    var compte: Int { echantillons }

    init(displayID: CGDirectDisplayID, segment: CaptureSegmentID,
         taille: CGSize, dossier: URL, debut: SessionTime) throws {
        self.displayID = displayID
        self.segment = segment
        self.debut = debut
        self.fileURL = dossier.appendingPathComponent("display-\(displayID)-\(segment).mov")

        writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)

        let reglages: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(taille.width),
            AVVideoHeightKey: Int(taille.height),
            AVVideoCompressionPropertiesKey: [
                // Une image clé toutes les DEMI-SECONDES — resserré depuis 1,0 s
                // le 23 août 2026, par la mesure.
                //
                // Depuis que les tolérances d'extraction sont nulles, le décodeur
                // remonte à l'image clé précédente pour CHAQUE image demandée :
                // le GOP borne directement ce trajet. À 1 s, l'extraction de
                // 30 images a coûté 3 659 ms, contre un budget de 3 s (§ 5.5).
                // À 0,5 s le trajet moyen tombe de ~7 à ~4 frames. Le prix est
                // deux fois plus d'images clés dans le fichier — le débit reste
                // loin du budget disque du § 4.4, qui a dix fois la marge.
                AVVideoMaxKeyFrameIntervalDurationKey: 0.5,
                AVVideoAverageBitRateKey: 6_200_000,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: reglages)
        // Le flux arrive en temps réel : sans ce drapeau, le writer optimise pour
        // le débit au prix de la latence, et l'encodage prend du retard sur la
        // capture jusqu'à faire déborder la pool de tampons.
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(domain: "regarde.writer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "entrée vidéo refusée"])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "regarde.writer", code: 2,
                                          userInfo: [NSLocalizedDescriptionKey: "startWriting refusé"])
        }
    }

    /// Écrit une frame. Appelé sur `encodeQueue`, seule propriétaire des tampons.
    func ecrire(_ sample: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)

        if !demarre {
            // LE geste qui décide de tout : le PTS du premier échantillon devient
            // le temps 0 du fichier. On le NOTE, parce que c'est lui qu'il faudra
            // soustraire à chaque demande d'image.
            writer.startSession(atSourceTime: pts)
            premier = pts
            demarre = true
        }
        guard input.isReadyForMoreMediaData else {
            // Une frame sautée n'est pas une erreur : elle veut dire que
            // l'encodeur a pris du retard. La compter permet de le voir.
            sautees += 1
            return
        }
        if input.append(sample) {
            echantillons += 1
            dernier = pts
        } else {
            sautees += 1
        }
    }

    private(set) var sautees = 0

    /// Ferme le segment et rend son descripteur.
    ///
    /// Ne LANCE jamais : l'échec d'un segment est une donnée du segment, pas une
    /// exception qui remonte. C'est exactement ce que le § 5.5 demande.
    func finaliser(raison: StopReason, fin: SessionTime) async -> CaptureSegment {
        var seg = CaptureSegment(
            id: segment, displayID: displayID, fileURL: fileURL,
            pixelSize: .zero, pointPixelScale: 0,
            start: debut)
        seg.end = fin
        seg.stopReason = raison
        seg.clockID = SessionClock.shared.horlogeDeFluxID

        input.markAsFinished()

        // Un segment VIDE n'est pas finalisé : `finishWriting()` échouerait sur
        // `AVError.noSourceTrack`, et le fichier de zéro octet resterait sur
        // disque. On le supprime et on le dit — un écran figé est un cas normal,
        // pas une panne.
        guard !vide else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: fileURL)
            log.notice("segment vide sur display \(self.displayID) — aucun échantillon, fichier retiré")
            return seg
        }

        await writer.finishWriting()
        if writer.status == .failed {
            let motif = writer.error?.localizedDescription ?? "?"
            log.error("finalisation échouée sur display \(self.displayID) — \(motif, privacy: .public)")
            return seg
        }
        seg.firstSamplePTS = premier.map(CMTimeCodable.init)
        seg.lastSamplePTS = dernier.map(CMTimeCodable.init)
        return seg
    }

    /// Écrit le manifeste À CÔTÉ du `.mov`.
    ///
    /// Le journal est remis à zéro à chaque lancement : un banc en deux phases
    /// perdrait sa première. Les PTS doivent survivre au fichier.
    static func ecrireManifeste(_ seg: CaptureSegment, echantillons: Int, sautees: Int) {
        let url = seg.fileURL.deletingPathExtension().appendingPathExtension("json")
        struct Manifeste: Codable {
            let segment: String
            let displayID: UInt32
            let fichier: String
            let firstSamplePTSSeconds: Double?
            let lastSamplePTSSeconds: Double?
            let dureeSeconds: Double?
            let debutSession: Double
            let finSession: Double?
            let stopReason: String?
            let clockID: String?
            let echantillons: Int
            let sautees: Int
            let octets: Int
        }
        let taille = ((try? FileManager.default.attributesOfItem(atPath: seg.fileURL.path))?[.size] as? Int) ?? 0
        let m = Manifeste(
            segment: seg.id.description, displayID: seg.displayID,
            fichier: seg.fileURL.lastPathComponent,
            firstSamplePTSSeconds: seg.firstSamplePTS?.cm.seconds,
            lastSamplePTSSeconds: seg.lastSamplePTS?.cm.seconds,
            dureeSeconds: (seg.firstSamplePTS?.cm).flatMap { f in
                (seg.lastSamplePTS?.cm).map { CMTimeSubtract($0, f).seconds } },
            debutSession: seg.start.seconds, finSession: seg.end?.seconds,
            stopReason: seg.stopReason?.rawValue, clockID: seg.clockID,
            echantillons: echantillons, sautees: sautees, octets: taille)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(m).write(to: url, options: .atomic)
    }
}
