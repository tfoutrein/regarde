import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import os

// ─────────────────────────────────────────────────────────────────────────────
// Un flux de capture par écran — S34, spécification § 5.2, ADR-0003
//
// C'est le premier code du lot 3 qu'aucun autotest ne peut couvrir : il faut un
// écran, une autorisation d'enregistrement, et du contenu qui bouge. Ce qui le
// remplace, c'est un JOURNAL qui dit assez pour qu'une panne se voie sans
// débogueur — d'où le nombre de choses comptées ici.
//
// TROIS PIÈGES, tous nommés par la spécification :
//
//   width/height ABSENTS       la capture sort en 1920×1080 SILENCIEUSEMENT.
//                              Perte de résolution sans erreur, sans avertissement,
//                              et le texte d'un IDE devient illisible dans le
//                              rapport. On les pose, et on VÉRIFIE ensuite que le
//                              tampon reçu a bien ces dimensions — parce que les
//                              poser ne garantit pas qu'ils soient honorés.
//
//   contentRect de la FRAME    et non du filtre (§ 3.3, ADR-0009). Le contenu peut
//                              être boîté dans le tampon ; l'arrondi `& ~1` casse
//                              le ratio et `scalesToFit = false` centre plutôt
//                              qu'il n'étire. On journalise le contentRect de
//                              chaque frame avec un compteur de VARIATIONS : une
//                              variation en cours de segment est un événement, pas
//                              du bruit.
//
//   le filtre est FIGÉ         `SCContentFilter` est construit une fois. Une
//                              application de la liste noire ouverte en cours de
//                              session ne serait pas exclue — exactement le cas
//                              d'un gestionnaire de mots de passe. Le filtre se
//                              reconstruit, et la reconstruction se journalise.
//
// Ce fichier NE contient PAS de writer : l'encodage arrive en S35. Ici, on ouvre,
// on reçoit, on compte, et on ferme proprement.
// ─────────────────────────────────────────────────────────────────────────────

/// Ce qu'un flux rapporte de lui-même, en continu.
struct StreamStats: Sendable {
    var framesComplete = 0
    var framesAutres = 0
    /// Dimensions réelles du premier `CVPixelBuffer` reçu.
    var bufferSize: CGSize?
    /// Dimensions DEMANDÉES à la configuration.
    var demande: CGSize = .zero
    /// Dernier `contentRect` observé, et le nombre de fois qu'il a changé.
    var contentRect: CGRect?
    var variationsContentRect = 0
    /// Surface salie : la plus forte observée, et la somme, pour la moyenne.
    ///
    /// Au bilan parce que la question « l'écran bougeait-il ? » se pose APRÈS la
    /// session, sur le journal, et qu'un « écran figé » qui livre 208 frames
    /// complètes sur 211 doit pouvoir être contredit par un chiffre.
    ///
    /// La valeur BRUTE, avant bornage. Un ratio supérieur à 1 est impossible et
    /// signale l'un de deux défauts : des rectangles sales qui se recouvrent et
    /// qu'on additionne au lieu d'en faire l'union, ou une confusion points/pixels
    /// comme celle de S38 — qui, sur un écran 2×, multiplierait la mesure par
    /// quatre. Le voir écrit est le seul moyen de trancher entre les deux.
    var salieMax: Double = 0
    var salieSomme: Double = 0
    /// Distribution des surfaces salies par frame : nulle, dérisoire (< 2 %),
    /// partielle (< 25 %), large (< 90 %), quasi totale.
    ///
    /// La moyenne seule ne distingue pas « toutes les frames à 0,98 » de « la
    /// moitié à 2,0 » — bornée, la seconde afficherait la même moyenne. Et c'est
    /// la première qui s'est produite le 23 août : 0,986 de moyenne sur un écran
    /// dont la seule animation était une vignette de 1,3 % — quelque chose
    /// déclarait l'écran ENTIER changé à chaque frame, et la moyenne ne pouvait
    /// pas dire si c'était chaque frame ou une frame sur deux.
    var salieHisto = [Int](repeating: 0, count: 5)
    /// Les `dirtyRects` bruts de la dernière frame : combien, et lesquels.
    /// C'est la seule ligne qui montre ce que ScreenCaptureKit DÉCLARE, plutôt
    /// qu'un ratio qui l'agrège.
    var derniersRects = ""
    var scaleFactor: Double = 0
    var contentScale: Double = 0
    var premierPTS: CMTime?
    var dernierPTS: CMTime?

    /// La capture est-elle sortie en 1920×1080 alors qu'on demandait autre chose ?
    ///
    /// Le piège porte un nom parce qu'il est silencieux : sans ce contrôle, on ne
    /// le découvre qu'en ouvrant une image et en trouvant le texte illisible.
    var suspicionDeReplique1080: Bool {
        guard let b = bufferSize else { return false }
        return b == CGSize(width: 1920, height: 1080) && demande != b
    }

    var dimensionsHonorees: Bool {
        guard let b = bufferSize else { return false }
        return abs(b.width - demande.width) < 2 && abs(b.height - demande.height) < 2
    }

    /// Enregistre une frame complète.
    ///
    /// La décision « le `contentRect` a-t-il changé ? » vit ICI plutôt que dans le
    /// rappel du flux, et pour une raison que ce projet a apprise deux fois : un
    /// compteur qu'on ne sait pas faire bouger ne dit rien, et son zéro rassure à
    /// tort. Le filtre des captures manquantes était vide par construction ; le
    /// diagnostic de barre de menus se taisait quand il avait le plus à dire. Cette
    /// décision-ci est donc dans une fonction pure, exercée par l'autotest.
    ///
    /// Ce qu'elle surveille : le `contentRect` appartient à la FRAME et peut
    /// changer en cours de flux — résolution, bascule d'espace, échelle. Toute la
    /// géométrie des marques en dépend, et une marque posée avant le changement ne
    /// se rapporte plus au même repère qu'une marque posée après. Rien d'autre ne
    /// le signalerait.
    mutating func noterFrame(rect: CGRect, tampon: CGSize?, scale: Double,
                             echelleContenu: Double, pts: CMTime, salie: Double,
                             rects: String = "") {
        framesComplete += 1
        salieMax = max(salieMax, salie)
        salieSomme += salie
        switch salie {
        case 0: salieHisto[0] += 1
        case ..<0.02: salieHisto[1] += 1
        case ..<0.25: salieHisto[2] += 1
        case ..<0.90: salieHisto[3] += 1
        default: salieHisto[4] += 1
        }
        if !rects.isEmpty { derniersRects = rects }
        if bufferSize == nil { bufferSize = tampon }
        if let precedent = contentRect, precedent != rect { variationsContentRect += 1 }
        contentRect = rect
        scaleFactor = scale
        contentScale = echelleContenu
        if premierPTS == nil { premierPTS = pts }
        dernierPTS = pts
    }
}

/// Un flux de capture attaché à un écran.
final class DisplayStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    let displayID: CGDirectDisplayID
    let segmentID = CaptureSegmentID()

    private let log = Logger(subsystem: logSubsystem, category: "flux")
    private var stream: SCStream?
    private var display: SCDisplay?

    /// Seule propriétaire des frames — la règle absolue de B2.
    ///
    /// Le thread du tap ne touche JAMAIS un `CVPixelBuffer` : il pousse un triplet
    /// dans un ring lock-free, et l'appariement se fait ici. Un `EXC_BAD_ACCESS`
    /// intermittent dans `CVPixelBufferRelease`, dont la fréquence dépend de
    /// l'activité de l'écran, coûte des soirées à diagnostiquer parce qu'il n'est
    /// pas reproductible à la demande.
    let encodeQueue: DispatchQueue

    // `OSAllocatedUnfairLock` et non `NSLock` : `lock()` est indisponible depuis un
    // contexte asynchrone en Swift 6, et `withLock` porte de toute façon mieux
    // l'invariant — on ne peut pas oublier de déverrouiller sur un chemin d'erreur.
    private let verrou = OSAllocatedUnfairLock(initialState: StreamStats())
    var stats: StreamStats { verrou.withLock { $0 } }

    /// Appelé sur `encodeQueue` pour chaque frame complète.
    var onFrame: ((CMSampleBuffer, CGRect, Double) -> Void)?

    /// Le writer, créé à la PREMIÈRE frame et pas avant.
    ///
    /// Avant, on ne connaît pas les dimensions réelles du tampon — seulement
    /// celles qu'on a demandées, et le § 5.2 dit précisément qu'elles peuvent ne
    /// pas être honorées. Créer le writer sur une taille supposée produirait un
    /// fichier dont chaque frame serait rejetée, sans erreur au moment où on
    /// pourrait encore corriger.
    private var writer: SegmentWriter?
    private var dossier: URL?
    /// L'anneau de frames. Vit sur `encodeQueue`, et nulle part ailleurs.
    private(set) lazy var anneau = FrameRing(queue: encodeQueue, segmentID: segmentID)
    /// Motif d'échec d'écriture, s'il y en a eu un. Traité comme une fin de session.
    private(set) var echecEcriture: String?
    /// Appelé quand le flux s'arrête de lui-même.
    var onArret: ((StopReason, String) -> Void)?

    init(displayID: CGDirectDisplayID, dossier: URL? = nil) {
        self.displayID = displayID
        self.dossier = dossier
        self.encodeQueue = DispatchQueue(label: "regarde.encode.\(displayID)", qos: .userInitiated)
        super.init()
    }

    // MARK: - Configuration

    /// La configuration du § 5.2, à la lettre.
    static func configuration(pour filtre: SCContentFilter) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        // `& ~1` : les encodeurs vidéo veulent des dimensions paires. L'arrondi se
        // fait ICI et se retrouve dans le `contentRect` des frames — c'est
        // exactement pourquoi la géométrie se rapporte à la frame et non au filtre.
        cfg.width = Int(filtre.contentRect.width * CGFloat(filtre.pointPixelScale)) & ~1
        cfg.height = Int(filtre.contentRect.height * CGFloat(filtre.pointPixelScale)) & ~1
        cfg.captureResolution = .best
        cfg.scalesToFit = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        // 6 et non 8 : marge contre l'épuisement de la pool. Une pool épuisée ne
        // rend pas d'erreur, elle cesse de livrer.
        cfg.queueDepth = 6
        // Le curseur est composité exactement là où l'utilisateur trace, donc au
        // centre de chaque recadrage : il masquerait l'élément annoté.
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.ignoreShadowsDisplay = true
        return cfg
    }

    /// Construit le filtre à partir du contenu FRAIS.
    ///
    /// Frais et non caché : une fenêtre ouverte depuis le dernier rafraîchissement
    /// ne serait pas dans la liste, donc pas exclue. C'est le cas d'une
    /// notification qui apparaît pendant la session, et celui d'un gestionnaire de
    /// mots de passe qu'on ouvre pour se connecter à ce qu'on teste.
    static func filtre(pour display: SCDisplay, contenu: SCShareableContent) async -> SCContentFilter {
        let bloques = await MainActor.run { CaptureExclusions.shared.excludedBundleIDs }
        let exclues = contenu.applications.filter { bloques.contains($0.bundleIdentifier) }
        return SCContentFilter(display: display, excludingApplications: exclues, exceptingWindows: [])
    }

    // MARK: - Cycle de vie

    enum Echec: Error, CustomStringConvertible {
        case ecranAbsent(CGDirectDisplayID, partageables: String)
        case demarrageImpossible(String)

        var description: String {
            switch self {
            case .ecranAbsent(let id, let dispo):
                "l'écran \(id) n'est pas partageable — partageables : "
                    + (dispo.isEmpty ? "AUCUN" : dispo)
            case .demarrageImpossible(let why): "démarrage du flux impossible : \(why)"
            }
        }
    }

    func demarrer() async throws {
        let contenu = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = contenu.displays.first(where: { $0.displayID == displayID }) else {
            throw Echec.ecranAbsent(displayID,
                                    partageables: contenu.displays.map { "\($0.displayID)" }
                                        .joined(separator: ", "))
        }
        self.display = display

        let filtre = await Self.filtre(pour: display, contenu: contenu)
        let cfg = Self.configuration(pour: filtre)
        // Les dimensions sont extraites AVANT le verrou : `SCStreamConfiguration`
        // n'est pas `Sendable`, et la capturer dans la fermeture ferait traverser
        // une frontière d'isolation à un objet qui ne s'y prête pas.
        let demandees = CGSize(width: cfg.width, height: cfg.height)
        verrou.withLock { $0.demande = demandees }

        let flux = SCStream(filter: filtre, configuration: cfg, delegate: self)
        try flux.addStreamOutput(self, type: .screen, sampleHandlerQueue: encodeQueue)
        do {
            try await flux.startCapture()
        } catch {
            throw Echec.demarrageImpossible(error.localizedDescription)
        }
        stream = flux

        // L'horloge du flux est adoptée MAINTENANT, et pas avant : elle vaut nil
        // tant que `startCapture()` n'a pas rendu la main (§ 3.1, correction 2).
        // Une marque posée pendant `arming` n'a donc aucune horloge, ce qui est
        // exactement ce qu'on veut qu'elle constate.
        if let sync = flux.synchronizationClock {
            SessionClock.shared.adopterHorlogeDeFlux(sync, id: "flux-\(displayID)")
        }

        await MainActor.run {
            Journal.event(.capture, "flux ouvert sur display \(self.displayID) — "
                          + "\(cfg.width)×\(cfg.height) demandés à 15 fps")
        }
    }

    /// Ferme le flux, finalise son segment, et rend le descripteur.
    ///
    /// La finalisation est ICI et non dans le moteur, pour que l'échec de CE
    /// segment reste le sien : un écran débranché aussitôt n'a aucun échantillon,
    /// et son `finishWriting()` échouerait — dans une séquence linéaire, il
    /// emporterait les marques d'un autre écran, qui sont complètes (§ 5.5).
    @discardableResult
    func arreter(raison: StopReason) async -> CaptureSegment? {
        guard let flux = stream else { return nil }
        stream = nil
        try? await flux.stopCapture()

        var segment: CaptureSegment?
        if let w = writer {
            let seg = await w.finaliser(raison: raison, fin: SessionClock.shared.now())
            SegmentWriter.ecrireManifeste(seg, echantillons: w.compte, sautees: w.sautees)
            segment = seg
            writer = nil
        }

        let s = stats
        let vide = segment?.vide ?? true
        await MainActor.run {
            Journal.event(.capture, "flux fermé sur display \(self.displayID) — "
                          + "\(s.framesComplete) frame(s) complètes, \(raison.rawValue)"
                          + (vide ? " — SEGMENT VIDE, aucun échantillon" : ""))
        }
        return segment
    }

    /// Reconstruit le filtre sans interrompre le flux.
    ///
    /// La liste noire peut changer en cours de session — une application s'ouvre.
    /// Sans cette reconstruction, elle resterait capturée jusqu'à la fin, et
    /// l'exclusion ne vaudrait que pour ce qui tournait déjà au démarrage.
    func rafraichirFiltre() async {
        guard let flux = stream, let display else { return }
        guard let contenu = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else { return }
        let nouveau = await Self.filtre(pour: display, contenu: contenu)
        do {
            try await flux.updateContentFilter(nouveau)
            await MainActor.run {
                Journal.event(.capture, "filtre reconstruit sur display \(self.displayID)")
            }
        } catch {
            await MainActor.run {
                Journal.warn(.capture, "filtre non reconstruit sur display \(self.displayID) — \(error)")
            }
        }
    }

    // MARK: - Réception

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Le statut est lu AVANT tout : ScreenCaptureKit livre aussi des frames
        // `idle`, `blank` et `suspended`, qui ne portent pas de pixels utiles. Les
        // compter avec les autres gonflerait le compte et masquerait un écran qui
        // ne livre plus rien.
        guard let attachements = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let info = attachements.first,
              let brut = info[.status] as? Int,
              let statut = SCFrameStatus(rawValue: brut) else { return }

        guard statut == .complete else {
            verrou.withLock { $0.framesAutres += 1 }
            return
        }

        let rect = (info[.contentRect] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero

        // Lu AVANT la surface salie : c'est lui qui convertit les points du
        // `contentRect` vers les pixels des `dirtyRects`.
        let scale = info[.scaleFactor] as? Double ?? 1

        // La part de l'écran qui a CHANGÉ depuis la frame précédente. C'est la
        // moitié de la double garde de l'anneau, et l'un des deux critères du plan
        // de burst : sans elle, le curseur clignotant — fréquence élevée, surface
        // dérisoire — déclencherait un burst à chaque marque.
        //
        // EN PIXELS, et c'est la correction de S43 quinquies. `contentRect` arrive
        // en POINTS — c'est établi depuis S38 — mais `dirtyRects` arrive en
        // PIXELS. Diviser l'un par l'autre gonflait la mesure du CARRÉ du facteur
        // d'échelle : ×4 sur un écran 2×.
        //
        // La preuve est dans le journal du 23 août : `max 4.000` sur l'écran 2× et
        // `max 1.000` sur l'écran 1×, à la frame près. Un recouvrement de
        // rectangles aurait donné des valeurs quelconques, pas exactement le carré
        // de l'échelle sur l'un et exactement 1 sur l'autre.
        //
        // Ce que ça coûtait : sur un écran Retina AU REPOS, le critère de surface
        // était franchi en permanence et le burst se déclenchait pour rien. Seul le
        // critère de fréquence retenait encore quelque chose — le double critère du
        // § 5.4 marchait sur une jambe.
        // Le calcul lui-même vit dans `SurfaceSalie`, hors du gestionnaire de
        // frame. C'est la deuxième fois qu'une confusion points/pixels passe ici —
        // S38 pour la géométrie, S43 pour la surface — et les deux fois parce que
        // le calcul était noyé dans une fonction qu'aucun test ne peut appeler.
        //
        // La somme, et non l'union : deux rectangles sales qui se recouvrent sont
        // comptés deux fois. C'est l'approximation par excès assumée — faire
        // l'union exacte coûterait un balayage par frame pour un critère qui n'a
        // qu'un seuil à franchir. Mais elle impose de BORNER : un ratio de surface
        // ne peut pas dépasser 1, et le laisser filer ferait franchir le seuil du
        // burst à un écran presque immobile dont le compositeur bavarde.
        let salie = SurfaceSalie.ratio(
            dirtyRects: ((info[.dirtyRects] as? [[String: Any]]) ?? [])
                .compactMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) },
            contentRectEnPoints: rect, scaleFactor: scale)
        let dirtyBrut = salie.brut
        let dirty = salie.borne
        let contentScale = info[.contentScale] as? Double ?? 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)

        let taille = CMSampleBufferGetImageBuffer(sample).map {
            CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
        }
        // Le résumé des rects bruts — borné à trois, ils se ressemblent tous quand
        // ça déborde, et c'est justement ce qu'on veut voir.
        let rectsBruts = ((info[.dirtyRects] as? [[String: Any]]) ?? [])
            .compactMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let resume = "\(rectsBruts.count) rect(s) — "
            + rectsBruts.prefix(3).map {
                String(format: "(%.0f, %.0f) %.0f×%.0f", $0.minX, $0.minY, $0.width, $0.height)
            }.joined(separator: " · ")
        verrou.withLock { $0.noterFrame(rect: rect, tampon: taille, scale: scale,
                                        echelleContenu: contentScale, pts: pts,
                                        salie: dirtyBrut, rects: resume) }

        // Le writer naît ici, à la première frame, quand la taille est CONNUE.
        if writer == nil, let dossier, let taille = taille, echecEcriture == nil {
            do {
                writer = try SegmentWriter(displayID: displayID, segment: segmentID,
                                           taille: taille, dossier: dossier,
                                           debut: SessionClock.shared.now())
            } catch {
                // Un `$TMPDIR` inaccessible ou saturé n'est pas rattrapable en
                // cours de route : on le retient, on cesse d'essayer, et le
                // coordinateur en fait une fin de session.
                echecEcriture = error.localizedDescription
                onArret?(.disquePlein, error.localizedDescription)
            }
        }
        writer?.ecrire(sample)

        // L'anneau est nourri ICI, sur `encodeQueue` — la seule file qui possède
        // les tampons. Le thread du tap, lui, s'est contenté de déposer un numéro.
        // `rect` vient des attachements, donc en POINTS : la conversion est dans
        // `depuisFrame`, en un seul endroit.
        let ref = FrameRef.depuisFrame(
            segmentID: segmentID, contentRectEnPoints: rect,
            bufferSize: taille ?? .zero, scaleFactor: scale,
            contentScale: contentScale, resolutionReduite: false, pts: pts)
        anneau.accueillir(sample, ref: ref, dirtyRatio: dirty)

        onFrame?(sample, rect, scale)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log.error("flux arrêté sur display \(self.displayID) — \(error.localizedDescription, privacy: .public)")
        onArret?(.erreurFlux, error.localizedDescription)
    }

    // MARK: - Diagnostic

    /// Le bloc que le journal imprime en fin de flux.
    ///
    /// Il porte les trois pièges du § 5.2, parce qu'un flux qui a mal tourné doit
    /// se lire sans débogueur.
    func bilan(duree: Double) -> [(String, String)] {
        let s = stats
        let theorique = Int(duree * 15)
        var lignes: [(String, String)] = [
            ("display", "\(displayID)"),
            ("frames complètes", "\(s.framesComplete) sur ~\(theorique) théoriques à 15 fps"),
            ("autres statuts", "\(s.framesAutres)"),
            ("demandé", String(format: "%.0f×%.0f", s.demande.width, s.demande.height)),
            ("tampon réel", s.bufferSize.map { String(format: "%.0f×%.0f", $0.width, $0.height) }
                            ?? "aucune frame reçue"),
        ]
        if s.suspicionDeReplique1080 {
            lignes.append(("⚠", "tampon en 1920×1080 alors qu'on demandait autre chose — "
                              + "width/height ignorés, résolution perdue en silence"))
        } else if s.bufferSize != nil && !s.dimensionsHonorees {
            lignes.append(("⚠", "le tampon ne fait pas les dimensions demandées"))
        }
        if let r = s.contentRect {
            lignes.append(("contentRect", String(format: "(%.0f, %.0f) %.0f×%.0f · scale %.2f · contentScale %.2f",
                                                 r.origin.x, r.origin.y, r.width, r.height,
                                                 s.scaleFactor, s.contentScale)))
            lignes.append(("variations", "\(s.variationsContentRect)"))
            if s.framesComplete > 0 {
                let moy = s.salieSomme / Double(s.framesComplete)
                var texte = String(format: "moy. %.3f · max %.3f", moy, s.salieMax)
                if s.salieMax > 1.0 {
                    texte += "  ← IMPOSSIBLE : recouvrement ou unités"
                }
                lignes.append(("surface salie", texte))
                let h = s.salieHisto
                lignes.append(("salie par frame", String(
                    format: "nulle %d · <2 %%  %d · <25 %%  %d · <90 %%  %d · ≥90 %%  %d",
                    h[0], h[1], h[2], h[3], h[4])))
                if !s.derniersRects.isEmpty {
                    lignes.append(("dernière frame", s.derniersRects))
                }
            }
        }
        return lignes
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// La part de l'écran qui a changé — S43 quinquies
//
// Extraite du gestionnaire de frame pour être TESTABLE. Deux défauts d'unités
// sont passés par cet endroit du code, et les deux fois parce que le calcul
// vivait dans une fonction qu'aucun test ne peut appeler : elle prend un
// `CMSampleBuffer` et des attachements de ScreenCaptureKit.
// ─────────────────────────────────────────────────────────────────────────────

enum SurfaceSalie {

    /// Rend la part salie, bornée et brute.
    ///
    /// - `contentRectEnPoints` vient des attachements, donc en POINTS.
    /// - `dirtyRects` vient des mêmes attachements, mais en PIXELS.
    ///
    /// Les diviser l'un par l'autre sans convertir gonfle la mesure du CARRÉ du
    /// facteur d'échelle. Mesuré le 23 août 2026 : `max 4.000` sur un écran 2×
    /// contre `max 1.000` sur un écran 1×, dans la même session.
    ///
    /// Le BRUT est rendu à côté du borné parce qu'une valeur au-dessus de 1 est
    /// impossible pour un ratio de surface, et que c'est le seul signal qui
    /// distingue une erreur d'unités d'un simple recouvrement de rectangles.
    static func ratio(dirtyRects: [CGRect], contentRectEnPoints rect: CGRect,
                      scaleFactor scale: Double) -> (borne: Double, brut: Double) {
        let s = CGFloat(scale)
        let surfaceEnPixels = max(rect.width * s * rect.height * s, 1)
        // La somme, et non l'union : deux rectangles qui se recouvrent comptent
        // deux fois. Approximation par excès assumée — l'union exacte coûterait un
        // balayage par frame pour un critère qui n'a qu'un seuil à franchir — mais
        // c'est elle qui impose de borner.
        let brut = dirtyRects.reduce(0.0) { $0 + Double($1.width * $1.height) }
            / Double(surfaceEnPixels)
        return (min(brut, 1.0), brut)
    }
}
