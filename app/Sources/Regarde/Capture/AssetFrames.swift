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
//   les TOLÉRANCES sont NULLES   des deux côtés, et c'est un amendement au § 5.2,
//                                obtenu par la mesure.
//
//                                La spécification demandait
//                                `before = .positiveInfinity`, en citant un coût
//                                de seek de 31 ms. Mais cette tolérance AUTORISE
//                                le générateur à remonter aussi loin qu'il veut :
//                                il rend donc l'IMAGE CLÉ précédente, qui est la
//                                moins chère à produire. Avec le GOP forcé à une
//                                seconde, l'image rendue peut être fausse d'une
//                                seconde entière — et C11 ne pourrait jamais
//                                passer.
//
//                                Mesuré sur la machine de l'auteur le 23 août :
//                                812,8 ms d'écart entre l'instant demandé et
//                                l'instant obtenu, sur huit marques. Juste sous
//                                l'intervalle d'image clé, ce qui nomme la cause.
//
//                                À zéro des deux côtés, le générateur rend la
//                                frame dont l'intervalle de présentation CONTIENT
//                                l'instant demandé : celle que l'utilisateur avait
//                                sous les yeux. Le décodage coûte alors le trajet
//                                depuis l'image clé précédente — et c'est
//                                précisément ce que le GOP borne (0,5 s depuis
//                                le 23 août). Le GOP sert la PRÉCISION, pas la
//                                paresse.
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
        /// L'image a-t-elle demandé un SECOND passage, tolérance relâchée ?
        var repli: Bool = false
        /// L'écran de cette marque bougeait-il ? C'est ce qui rend `ecartMs`
        /// interprétable : sur un écran immobile, un écart de 650 ms est l'âge de
        /// la dernière image encodée, et son contenu est exact — rien n'avait
        /// changé. Sur un écran animé, le même écart est une image fausse.
        var ecranBougeait: Bool = false
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
                    format: "marque %d · %d frame(s) au plan · %d frame(s)/s · %.3f de surface moyenne",
                    d.numero, plan.count,
                    d.motion.completeFramesLastSecond, d.motion.dirtyRatioLastSecond))
            }
        }
        guard !temps.isEmpty else { return ([], refus) }

        // TRIÉS. `generateCGImagesAsynchronously` traite le tableau dans l'ordre
        // reçu, et les temps sortaient groupés par marque : t−0,8 · t · t+0,4, puis
        // un saut en arrière de 1,2 s pour la marque suivante. Chaque saut en
        // arrière oblige le décodeur à repartir de l'image clé précédente.
        //
        // Avec les tolérances nulles, ce coût n'est plus amorti par le saut à
        // l'image clé : 3 808 ms mesurés sur trente instants le 23 août, contre un
        // budget de 3 s au § 5.5. Un ordre croissant laisse le décodeur avancer.
        temps.sort { $0.timeValue.seconds < $1.timeValue.seconds }

        let asset = AVURLAsset(url: segment.fileURL)
        let generateur = AVAssetImageGenerator(asset: asset)
        generateur.appliesPreferredTrackTransform = true
        // LES TOLÉRANCES, à zéro des deux côtés. Voir l'en-tête : `.positiveInfinity`
        // avant faisait rendre l'image clé précédente, jusqu'à une seconde trop tôt.
        generateur.requestedTimeToleranceBefore = .zero
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
        var (recues, refusees) = collecteur.moisson()

        // LE SECOND PASSAGE, tolérance relâchée — S43 quinquies.
        //
        // La tolérance nulle est juste, mais elle peut ÉCHOUER : sur un écran
        // immobile, l'encodeur n'écrit presque rien, et aucune frame ne couvre
        // l'instant demandé. Le générateur rend alors « Cannot Decode » et la
        // marque retombe sur le filet RAM — une image prise au relâchement, donc
        // une à deux secondes trop tard. C'est exactement ce que le lot 3 corrige,
        // remis par la porte de derrière.
        //
        // Ces temps-là sont donc rejoués avec `before = .positiveInfinity`. Le
        // risque de cette tolérance est le saut à l'image clé, jusqu'à un GOP
        // en arrière — mais il ne se paie QUE là où le premier passage a échoué,
        // c'est-à-dire sur un écran qui ne produit pas de frames. Et sur un écran
        // qui ne change pas, l'image d'il y a une seconde est la bonne.
        //
        // Le résultat est marqué `repli` : le journal le dit, plutôt que de laisser
        // croire à une extraction exacte.
        // Et il ne concerne QUE les marques restées sans image. Le premier
        // passage demande trois instants par marque ; il suffit qu'un seul des
        // trois échoue — celui d'après la marque, hors des bornes du segment —
        // pour que le repli soit déclenché. Sans ce filtre, il rendait alors une
        // image sautée à l'image clé qui ÉCRASAIT l'image exacte déjà obtenue.
        //
        // Mesuré le 23 août 2026 : la marque 2 d'une session de dix portait une
        // image 1,40 s trop tôt, et le bloc EXTRACTION annonçait « depuis le
        // fichier 11 » pour dix marques — une marque remplacée deux fois. Le
        // journal ne pouvait pas le voir : l'âge annoncé, 548 ms, était celui de
        // l'image de repli, pas l'erreur réelle. C'est la RÉGLETTE qui l'a
        // attrapé, en refusant d'être monotone.
        let dejaServies = Set(recues.map(\.markID))
        let aRejouer = collecteur.aRejouer.filter { t in
            guard let d = parTemps[t.seconds.rounded(toPlaces: 4)] else { return false }
            return !dejaServies.contains(d.markID)
        }
        if !aRejouer.isEmpty {
            let secours = AVAssetImageGenerator(asset: asset)
            secours.appliesPreferredTrackTransform = true
            secours.requestedTimeToleranceBefore = .positiveInfinity
            secours.requestedTimeToleranceAfter = .zero
            let second = Collecteur(attendus: aRejouer.count, index: parTemps,
                                    principal: principal,
                                    preRoll: segment.resolutionReduite)
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                secours.generateCGImagesAsynchronously(forTimes: aRejouer.map { NSValue(time: $0) }) {
                    demande, image, obtenu, resultat, erreur in
                    if second.recevoir(demande: demande, image: image, obtenu: obtenu,
                                       resultat: resultat, erreur: erreur) {
                        suite.resume()
                    }
                }
            }
            let (sauvees, echecs) = second.moisson()
            // Les marques sauvées quittent la liste des refus : elles ont bien leur
            // image du fichier, seulement obtenue au second essai.
            let idsSauvees = Set(sauvees.map(\.markID))
            refusees.removeAll { idsSauvees.contains($0.0) }
            recues.append(contentsOf: sauvees.map {
                var r = $0; r.repli = true; return r
            })
            refusees.append(contentsOf: echecs)
            await MainActor.run {
                Journal.event(.capture, "repli de tolérance — \(sauvees.count) image(s) "
                              + "récupérée(s) sur \(aRejouer.count) instant(s) sans frame exacte")
            }
        }

        // Chaque image sait si son écran bougeait : sans ça, l'écart demandé/obtenu
        // n'est pas interprétable.
        let bouge = Dictionary(demandes.map { ($0.markID, $0.motion.screenWasMoving) },
                               uniquingKeysWith: { a, _ in a })
        for i in recues.indices { recues[i].ecranBougeait = bouge[recues[i].markID] ?? false }

        await MainActor.run {
            Journal.event(.capture, "burst — \(collecteur.obtenues) frame(s) obtenues "
                          + "sur \(collecteur.demandees) demandée(s)")
        }
        // Un refus s'ÉTEINT quand la marque a son image. Trois temps sont demandés
        // par marque ; l'un peut échouer — un instant tombé dans un trou de frames
        // perdues — pendant qu'un autre sert la même marque. Garder le refus
        // faisait compter « 10 depuis le fichier + 1 servie par le filet » pour
        // dix marques, et journalisait un « Cannot Decode » sur une marque qui
        // avait son image exacte. Mesuré le 23 août 2026, marque 9 sur dix.
        let servis = Set(recues.map(\.markID))
        return (recues, (refus + refusees).filter { !servis.contains($0.0) })
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
    /// Les temps que le générateur n'a pas su rendre, pour un second passage.
    private var tempsRefuses: [CMTime] = []
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
                tempsRefuses.append(demande)
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

    var aRejouer: [CMTime] {
        verrou.lock(); defer { verrou.unlock() }
        return tempsRefuses
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
