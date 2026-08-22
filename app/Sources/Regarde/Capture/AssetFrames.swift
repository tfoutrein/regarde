import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// L'extraction — S39, ADR-0008, spécification § 5.5
//
// C'est ici que B1 se gagne ou se perd pour de bon. Tout ce qui précède —
// l'horloge recalée, `firstSamplePTS` noté, `assetTime()` qui borne — n'existe que
// pour rendre cette fonction juste.
//
// DEUX RÈGLES, et la seconde est celle qu'on oublie :
//
//   UN SEUL appel par segment    `generateCGImagesAsynchronously(forTimes:)` prend
//                                un TABLEAU de temps. Appelé une fois par marque,
//                                il rouvre l'asset, reconstruit son index et
//                                repart de l'image clé à chaque fois : le budget
//                                de 3 s pour le traitement final part en
//                                réouvertures. Un appel, tous les temps, par
//                                segment.
//
//   les TOLÉRANCES ne sont pas   `before = .positiveInfinity` autorise à remonter
//   symétriques                  aussi loin qu'il faut ; `after = .zero` interdit
//                                d'avancer. Le générateur rend donc TOUJOURS la
//                                frame à l'instant demandé ou AVANT — jamais
//                                après.
//
//                                C'est la sémantique voulue, et elle est le
//                                pendant exact de l'appariement du § 5.3 :
//                                l'utilisateur désigne ce qu'il VOIT, donc la
//                                dernière image affichée. Laisser les tolérances
//                                par défaut rendrait « l'image la plus proche »,
//                                qui est parfois celle d'après — et l'infobulle
//                                s'y est déjà refermée. Ce serait B1 à l'échelle
//                                d'une frame, plus discret et tout aussi faux.
// ─────────────────────────────────────────────────────────────────────────────

enum AssetFrames {

    private static let log = Logger(subsystem: logSubsystem, category: "extraction")

    /// Ce qu'une demande d'extraction porte.
    struct Demande: Sendable {
        let markID: UUID
        let numero: Int
        /// Instant voulu, sur la timeline de session.
        let t: SessionTime
        let motion: MotionSample
    }

    /// Ce qu'une extraction rend.
    struct Resultat: @unchecked Sendable {
        let markID: UUID
        let numero: Int
        let image: CGImage
        /// Instant RÉELLEMENT rendu par le générateur, sur la timeline d'asset.
        let assetTime: CMTime
        /// Écart entre le voulu et l'obtenu, en millisecondes. Journalisé par
        /// marque : c'est la mesure directe de ce que B1 aurait coûté.
        let ecartMs: Double
        let source: ImageSource
    }

    /// Pourquoi une marque n'a pas eu son image du fichier.
    enum Refus: CustomStringConvertible {
        case segmentVide
        case horsBornes(t: Double)
        case generateurEnErreur(String)
        case aucuneImage

        var description: String {
            switch self {
            case .segmentVide: "segment vide — l'écran n'a produit aucun échantillon"
            case .horsBornes(let t): String(format: "instant %.3fs hors des bornes du segment", t)
            case .generateurEnErreur(let e): "générateur en erreur — \(e)"
            case .aucuneImage: "aucune image rendue"
            }
        }
    }

    /// Extrait, en UN SEUL appel, toutes les images demandées à un segment.
    ///
    /// Rend les résultats et les refus séparément : un refus n'est pas une panne,
    /// c'est une marque qui devra se contenter du filet RAM — et le savoir permet
    /// de le DIRE dans le rapport plutôt que de laisser croire à une extraction.
    static func extraire(_ demandes: [Demande], depuis segment: CaptureSegment,
                         clock: SessionClock) async -> (
        images: [Resultat], refus: [(UUID, Refus)]) {

        guard !segment.vide else {
            return ([], demandes.map { ($0.markID, .segmentVide) })
        }

        // Les temps sont calculés d'abord, et les hors-bornes écartés AVANT
        // d'appeler le générateur : lui demander un temps qu'on sait invalide
        // reviendrait à lui laisser inventer une réponse.
        var temps: [NSValue] = []
        var parTemps: [Double: Demande] = [:]
        var refus: [(UUID, Refus)] = []
        // Le temps PRINCIPAL de chaque marque, pour départager le burst ensuite.
        var principal: [UUID: Double] = [:]

        for d in demandes {
            // LE PLAN DE BURST — § 5.4.
            //
            // Sur écran figé, une image. Sur écran animé, trois : t−0,8, t, t+0,4.
            // Le double critère est ce qui compte : `completeFramesLastSecond`
            // seul laisserait passer le curseur clignotant — fréquence élevée,
            // surface dérisoire — et `dirtyRatioLastSecond` seul laisserait passer
            // le redraw plein écran unique — surface énorme, fréquence 1. Un burst
            // déclenché sur l'un OU l'autre triplerait le coût pour rien.
            let plan = segment.framePlan(pour: d.t, motion: d.motion, clock: clock)
            guard !plan.isEmpty else {
                refus.append((d.markID, .horsBornes(t: d.t.seconds)))
                continue
            }
            // Le temps de la marque elle-même reste le principal ; les deux autres
            // sont des candidats. Une borne violée disparaît du plan sans bruit —
            // c'est `assetTime()` qui l'a écartée — et le compte demandé/obtenu le
            // dit à la ligne suivante du journal.
            let vise = segment.assetTime(for: d.t, clock: clock, clockID: segment.clockID)
            for at in plan {
                temps.append(NSValue(time: at))
                parTemps[at.seconds.rounded(toPlaces: 4)] = d
            }
            if let vise { principal[d.markID] = vise.seconds.rounded(toPlaces: 4) }

            await MainActor.run {
                Journal.event(.capture, String(
                    format: "marque %d · %d frame(s) au plan · %d frame(s)/s · %.3f de surface",
                    d.numero, plan.count,
                    d.motion.completeFramesLastSecond, d.motion.dirtyRatioLastSecond))
            }
        }
        guard !temps.isEmpty else { return ([], refus) }

        let asset = AVURLAsset(url: segment.fileURL)
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        // LES TOLÉRANCES. Voir l'en-tête : jamais après, aussi loin avant qu'il
        // faut. C'est le pendant de l'appariement « au PTS inférieur le plus
        // proche » du § 5.3, et les deux disent la même chose — on rend ce que
        // l'utilisateur VOYAIT.
        generateur.requestedTimeToleranceBefore = .positiveInfinity
        generateur.requestedTimeToleranceAfter = .zero

        // Le rappel du générateur est appelé depuis plusieurs threads. Un
        // accumulateur sous verrou, plutôt que des variables capturées : Swift 6
        // refuse les secondes, et il a raison — les rappels se chevauchent.
        let collecteur = Collecteur(attendus: temps.count, index: parTemps,
                                    principal: principal,
                                    preRoll: segment.resolutionReduite)
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            generateur.generateCGImagesAsynchronously(forTimes: temps) {
                demande, image, obtenu, resultat, erreur in
                if collecteur.recevoir(demande: demande, image: image, obtenu: obtenu,
                                       resultat: resultat, erreur: erreur) {
                    suite.resume()
                }
            }
        }
        let (recues, refusees) = collecteur.moisson()
        await MainActor.run {
            Journal.event(.capture, "burst — \(collecteur.obtenues) frame(s) obtenues "
                          + "sur \(collecteur.demandees) demandée(s)")
        }
        return (recues, refus + refusees)
    }

    /// Supprime le fichier encodé.
    ///
    /// À la PUBLICATION, et pas avant : tant que les images ne sont pas écrites, le
    /// `.mov` est la seule source. Et pas plus tard non plus — c'est de la vidéo de
    /// l'écran de l'utilisateur, et l'ADR-0020 en fait un intermédiaire dont la vie
    /// s'arrête avec le besoin qui l'a créé.
    static func supprimer(_ segments: [CaptureSegment]) -> Int {
        var n = 0
        for seg in segments {
            let manifeste = seg.fileURL.deletingPathExtension().appendingPathExtension("json")
            if (try? FileManager.default.removeItem(at: seg.fileURL)) != nil { n += 1 }
            try? FileManager.default.removeItem(at: manifeste)
        }
        return n
    }
}

/// Accumulateur des rappels du générateur, sous verrou.
private final class Collecteur: @unchecked Sendable {
    private let verrou = NSLock()
    private var restants: Int
    private let index: [Double: AssetFrames.Demande]
    private let preRoll: Bool
    private var images: [AssetFrames.Resultat] = []
    private var refus: [(UUID, AssetFrames.Refus)] = []
    /// Frames effectivement rendues, toutes marques et tout le burst confondus.
    /// Comparé au nombre demandé, il dit combien de bornes ont été violées.
    private(set) var obtenues = 0
    let demandees: Int

    private let principal: [UUID: Double]
    /// Écart au temps principal de la meilleure image retenue, par marque.
    private var meilleur: [UUID: Double] = [:]

    init(attendus: Int, index: [Double: AssetFrames.Demande],
         principal: [UUID: Double], preRoll: Bool) {
        self.restants = attendus
        self.demandees = attendus
        self.index = index
        self.principal = principal
        self.preRoll = preRoll
    }

    /// Rend `true` quand c'était le dernier rappel attendu.
    func recevoir(demande: CMTime, image: CGImage?, obtenu: CMTime,
                  resultat: AVAssetImageGenerator.Result, erreur: Error?) -> Bool {
        verrou.lock()
        defer { verrou.unlock() }
        restants -= 1
        if let d = index[demande.seconds.rounded(toPlaces: 4)] {
            if resultat == .succeeded, let image {
                // Une seule image par marque survit : celle dont le temps DEMANDÉ
                // est le plus proche du temps principal. Les deux autres du burst
                // ont servi à obtenir le contexte ; le rapport du lot 4 décidera
                // s'il les publie.
                let cible = principal[d.markID] ?? demande.seconds
                let distance = abs(demande.seconds - cible)
                if meilleur[d.markID].map({ $0 <= distance }) != true {
                    meilleur[d.markID] = distance
                    images.removeAll { $0.markID == d.markID }
                    images.append(AssetFrames.Resultat(
                        markID: d.markID, numero: d.numero, image: image,
                        assetTime: obtenu,
                        ecartMs: (obtenu.seconds - demande.seconds) * 1000,
                        source: preRoll ? .preRoll : .segment))
                }
                obtenues += 1
            } else {
                refus.append((d.markID, erreur.map { .generateurEnErreur($0.localizedDescription) }
                                        ?? .aucuneImage))
            }
        }
        return restants == 0
    }

    func moisson() -> ([AssetFrames.Resultat], [(UUID, AssetFrames.Refus)]) {
        verrou.lock(); defer { verrou.unlock() }
        return (images, refus)
    }
}

private extension Double {
    /// Arrondi stable pour servir de clé : les temps traversent `CMTime` puis
    /// `Double`, et une comparaison exacte manquerait la correspondance d'un ulp.
    func rounded(toPlaces n: Int) -> Double {
        let f = pow(10.0, Double(n))
        return (self * f).rounded() / f
    }
}
