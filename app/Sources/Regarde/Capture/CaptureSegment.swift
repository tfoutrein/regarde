import CoreGraphics
import CoreMedia
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le segment de capture, et le temps de l'asset — S32, ADR-0008, spécification § 3.2
//
// « C'est le défaut le plus grave de la conception initiale et la première chose
// à implémenter correctement. » (§ 3.2)
//
// `AVAssetWriter.startSession(atSourceTime:)` définit quel PTS devient le temps 0
// du fichier. Demander à `AVAssetImageGenerator` la frame à `SessionTime` produit
// un décalage CONSTANT égal à `PTS_première_frame − t0`, soit 0,3 à 3 s selon le
// délai de démarrage du flux et le temps que met l'écran à changer — ScreenCapture-
// Kit ne livre que sur changement.
//
// **Ce décalage est invisible sur écran statique et systématique sur écran animé**,
// c'est-à-dire exactement dans le cas d'usage qui justifie le produit. C'est le
// bug B1, et `assetTime()` est la seule chose qui se dresse entre lui et le
// rapport.
//
// Rien ici ne touche l'écran ni ScreenCaptureKit : ce sont des types et de
// l'arithmétique, vérifiables sur des cas fabriqués à la main. C'est délibéré —
// un modèle temporel dont la vérification exigerait un flux vivant ne serait
// vérifié qu'une fois le flux écrit, c'est-à-dire trop tard.
// ─────────────────────────────────────────────────────────────────────────────

/// Identité d'un segment. Portée par chaque marque.
///
/// Sans elle, après un `-3821` et une réouverture de segment aux dimensions
/// différentes, les pixels des marques antérieures ne sont plus interprétables :
/// on ne saurait plus à quelle géométrie les rapporter (§ 3.3).
struct CaptureSegmentID: Hashable, Codable, Sendable, CustomStringConvertible {
    let raw: UUID
    init(_ raw: UUID = UUID()) { self.raw = raw }
    var description: String { String(raw.uuidString.prefix(8)) }
}

/// Pourquoi un segment s'est arrêté.
///
/// Renseigné sur CHAQUE chemin d'arrêt. Un segment dont on ignore pourquoi il
/// s'est fermé est un segment dont on ne sait pas si son absence de frames est
/// normale — écran figé — ou pathologique.
enum StopReason: String, Codable, Sendable {
    /// Fin de session demandée par l'utilisateur.
    case finDeSession
    /// L'écran a été débranché, ou la disposition a changé (§ 5.5).
    case deconnexion
    /// Veille, verrouillage, changement d'utilisateur (ADR-0020).
    case suspension
    /// Le flux a rendu une erreur.
    case erreurFlux
    /// Plus de place, ou `$TMPDIR` inaccessible.
    case disquePlein
    /// Bascule du pré-roll vers la pleine résolution (ADR-0004).
    case basculePreRoll
}

/// D'où vient l'image d'une marque.
///
/// Publié par marque parce que les trois n'ont pas la même valeur de preuve :
/// une image extraite du fichier encodé porte l'instant désigné, une image du
/// filet RAM porte l'instant de la capture ponctuelle, et une image de pré-roll
/// est à résolution réduite. Le rapport doit pouvoir le dire.
enum ImageSource: String, Codable, Sendable {
    /// Extraite du segment de session, à pleine résolution.
    case segment
    /// Extraite d'un segment de pré-roll, donc à résolution RÉDUITE (ADR-0004).
    case preRoll
    /// Filet du § 5.1 : `SCScreenshotManager` au moment de la marque.
    case filetRAM
    /// Aucune image n'a pu être produite.
    case aucune
}

/// La frame retenue pour une marque, décrite là où elle sert.
///
/// **Le `contentRect` est celui de LA FRAME, pas du filtre** (ADR-0009, § 3.3).
/// ScreenCaptureKit publie ces attachements par frame précisément parce que le
/// contenu peut être boîté dans le tampon : l'arrondi `& ~1` des dimensions casse
/// le ratio, et `scalesToFit = false` centre plutôt qu'il n'étire. Ignorer cela
/// produit des recadrages décalés d'une marge constante et des bandes noires sur
/// les bords, diagnostiqués à tort comme un bug d'échelle Retina.
///
/// Le MODÈLE ne bascule pas pour autant : une marque naît dans le repère de son
/// écran (voir `MarkStore.beginStroke`), et la conversion vers le repère de la
/// frame se fait ici, à la couture, du côté des pixels.
struct FrameRef: Codable, Sendable, Equatable {
    let segmentID: CaptureSegmentID
    /// Rectangle utile DANS le tampon, **en PIXELS du tampon**.
    ///
    /// ScreenCaptureKit le publie en POINTS : sur un écran @2×, une frame qui
    /// remplit un tampon de 3456×2234 annonce un `contentRect` de 1728×1117. Le
    /// comparer tel quel au tampon fait déclarer boîtée toute frame parfaitement
    /// normale, et écrase les marques dans le quart haut-gauche de l'image.
    ///
    /// La conversion se fait donc à la CONSTRUCTION, une fois, ici — et non à
    /// chaque usage, où l'oubli d'une multiplication serait invisible. C'est très
    /// exactement le défaut que le § 3.3 annonce comme « diagnostiqué à tort comme
    /// un bug d'échelle Retina ».
    let contentRect: CGRect
    /// Dimensions du tampon, qui peuvent excéder `contentRect`.
    let bufferSize: CGSize
    /// Facteur d'échelle effectif de cette frame.
    let scaleFactor: Double
    /// Pixels natifs par point.
    let contentScale: Double
    /// Vrai quand la frame vient d'un segment à résolution réduite (pré-roll).
    let resolutionReduite: Bool

    /// Construit depuis les attachements d'une frame, en convertissant les unités.
    ///
    /// `scaleFactor` est l'échelle de l'ÉCRAN — 2 sur Retina — et c'est elle qui
    /// convertit les points en pixels, et elle aussi qui donne l'épaisseur de trait
    /// à la gravure. `contentScale` vaut 1 quand la capture n'est pas réduite : la
    /// prendre pour l'échelle de l'écran fait graver des traits deux fois trop fins
    /// sur un Retina, sans que rien ne le signale.
    static func depuisFrame(segmentID: CaptureSegmentID, contentRectEnPoints: CGRect,
                            bufferSize: CGSize, scaleFactor: Double, contentScale: Double,
                            resolutionReduite: Bool, pts: CMTime) -> FrameRef {
        let f = scaleFactor > 0 ? scaleFactor : 1
        let enPixels = CGRect(x: contentRectEnPoints.minX * f, y: contentRectEnPoints.minY * f,
                              width: contentRectEnPoints.width * f,
                              height: contentRectEnPoints.height * f)
        return FrameRef(segmentID: segmentID, contentRect: enPixels, bufferSize: bufferSize,
                        scaleFactor: scaleFactor, contentScale: contentScale,
                        resolutionReduite: resolutionReduite, pts: CMTimeCodable(pts))
    }
    /// PTS de la frame, sur l'horloge du flux.
    let pts: CMTimeCodable

    /// La frame est-elle boîtée dans son tampon ?
    var boitee: Bool {
        contentRect.width < bufferSize.width - 0.5 || contentRect.height < bufferSize.height - 0.5
    }
}

/// Métriques de mouvement de la seconde écoulée — § 5.4.
///
/// Le DOUBLE critère est ce qui compte : `completeFramesLastSecond` seul laisserait
/// passer le curseur clignotant — fréquence élevée, surface dérisoire — et
/// `dirtyRatioLastSecond` seul laisserait passer le redraw plein écran unique —
/// surface énorme, fréquence 1. Un burst déclenché sur l'un ou l'autre triplerait
/// le coût pour un bénéfice nul.
struct MotionSample: Codable, Sendable, Equatable {
    var completeFramesLastSecond: Int = 0
    var dirtyRatioLastSecond: Double = 0

    static let seuilFrames = 6
    static let seuilDirty = 0.02

    /// L'écran bougeait-il assez pour qu'un burst ait un sens ?
    var screenWasMoving: Bool {
        completeFramesLastSecond >= Self.seuilFrames && dirtyRatioLastSecond >= Self.seuilDirty
    }
}

/// `CMTime` sérialisable, encodé en couple valeur/échelle.
///
/// L'encoder en secondes flottantes perdrait la précision au tick que l'échelle
/// existe pour garantir — et c'est précisément sur des fractions de tick que se
/// joue l'appariement.
struct CMTimeCodable: Codable, Sendable, Equatable, CustomStringConvertible {
    let value: CMTimeValue
    let timescale: CMTimeScale

    init(_ t: CMTime) { value = t.value; timescale = t.timescale }
    var cm: CMTime { CMTime(value: value, timescale: timescale) }
    var description: String { String(format: "%.4fs", cm.seconds) }
}

/// Un segment de capture : un fichier, un écran, une fenêtre de temps.
struct CaptureSegment: Codable, Sendable, Identifiable {
    let id: CaptureSegmentID
    let displayID: CGDirectDisplayID
    let fileURL: URL
    /// Dimensions configurées du tampon.
    let pixelSize: CGSize
    var pointPixelScale: Double
    /// Le segment est-il à résolution réduite (pré-roll) ?
    var resolutionReduite: Bool = false

    /// PTS passé à `startSession(atSourceTime:)`. **Nil tant qu'aucun échantillon
    /// n'a été écrit** — et c'est un cas légitime : un écran strictement figé n'en
    /// produit aucun, puisque ScreenCaptureKit ne livre que sur changement.
    var firstSamplePTS: CMTimeCodable?
    var lastSamplePTS: CMTimeCodable?

    let start: SessionTime
    var end: SessionTime?
    var stopReason: StopReason?

    /// Identité de l'horloge du flux qui a produit ces PTS.
    ///
    /// Deux flux ont deux `synchronizationClock` distinctes, et leurs PTS ne sont
    /// PAS comparables. Sans cette identité, appliquer à un segment le temps
    /// converti sur l'horloge d'un autre produirait un décalage silencieux — du
    /// même ordre que B1, et diagnostiqué comme lui.
    var clockID: String?

    /// Le segment porte-t-il des échantillons ?
    var vide: Bool { firstSamplePTS == nil }

    /// Temps à demander à `AVAssetImageGenerator`, borné sur la durée RÉELLE de
    /// l'asset.
    ///
    /// Rend `nil` — jamais une valeur approchée — quand l'instant demandé tombe
    /// hors du segment. Un temps hors bornes ne produit pas une frame, il produit
    /// une trace : c'est ce qui laisse le banc distinguer « la marque précède le
    /// premier échantillon » de « la frame est décalée ».
    func assetTime(for t: SessionTime, clock: SessionClock, clockID horloge: String? = nil) -> CMTime? {
        guard let first = firstSamplePTS?.cm, let last = lastSamplePTS?.cm else { return nil }
        // Refus NOMMÉ : un PTS converti sur une autre horloge de flux n'a pas de
        // sens ici, même s'il est numériquement dans les bornes.
        if let horloge, let mienne = clockID, horloge != mienne { return nil }

        let target = CMTimeSubtract(clock.pts(for: t), first)
        let duree = CMTimeSubtract(last, first)
        if target < .zero || target > duree { return nil }
        return target
    }

    /// Le plan de burst du § 5.4, clampé sur la durée réelle du segment.
    ///
    /// Un burst systématique triplerait le coût pour un bénéfice nul sur un écran
    /// statique — le cas majoritaire. Les bornes violées ne sont pas silencieuses :
    /// elles disparaissent du plan, et le compte des retenues contre les demandées
    /// dit combien.
    func framePlan(pour t: SessionTime, motion: MotionSample, clock: SessionClock) -> [CMTime] {
        let voulus: [SessionTime]
        if motion.completeFramesLastSecond == 0 || !motion.screenWasMoving {
            voulus = [t]                                    // écran figé, ou curseur seul
        } else {
            voulus = [SessionTime(seconds: t.seconds - 0.8), t,
                      SessionTime(seconds: t.seconds + 0.4)]
        }
        return voulus.compactMap { assetTime(for: $0, clock: clock, clockID: clockID) }
    }
}
