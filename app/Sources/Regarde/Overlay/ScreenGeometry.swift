import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Conversion entre espaces de coordonnées — spécification § 3.3
//
// LE piège du lot 2, et le plan est explicite : cette fonction s'écrit AVANT tout code
// de dessin, avec sa table de cas. Le décalage ×2 et l'origine négative ne se voient
// pas sur une configuration mono-écran Retina — c'est-à-dire sur la machine de
// développement, en permanence. Le défaut apparaîtrait au lot 3, mêlé aux bugs de
// temps, et coûterait trois fois plus cher à démêler.
//
// Trois espaces, dont deux ont des origines OPPOSÉES :
//
//   ┌─ CGEvent.location ────────── origine HAUT-gauche de l'écran principal, en points
//   │  (0,0) ────────► x          y croît vers le BAS
//   │    │
//   │    ▼ y
//
//   ┌─ Cocoa / NSScreen ────────── origine BAS-gauche de l'écran principal, en points
//   │    ▲ y                      y croît vers le HAUT
//   │    │
//   │  (0,0) ────────► x
//
//   ┌─ Buffer ScreenCaptureKit ─── origine haut-gauche du contentRect de LA FRAME,
//      en PIXELS, à l'échelle de l'écran capturé
//
// Ce type est une STRUCTURE PURE, sans dépendance à AppKit : c'est ce qui le rend
// testable sur des configurations qu'on n'a pas sous la main — un écran non-Retina
// placé à gauche, une échelle mixte, un écran plus haut que le principal.
// ─────────────────────────────────────────────────────────────────────────────

/// Pourquoi un écran est écarté de la capture — spécification § 3.3.
///
/// Deux cas, et le § 3.3 les veut « refusés proprement, non silencieusement ».
/// La nuance est tout : un écran silencieusement absent donne un ⌥⌘-glisser qui
/// trace normalement, un numéro qui s'incrémente, et un dossier où l'image manque
/// sans que rien n'ait prévenu. L'utilisateur découvre la panne en relisant son
/// rapport, quand la scène a disparu.
enum RefusEcran: String, Sendable, Codable, CustomStringConvertible {
    /// Rotation de 90 ou 270° : largeur et hauteur sont inversées entre
    /// `CGDisplayBounds` et le tampon de capture. Toute conversion de coordonnées
    /// y serait fausse — non pas décalée, mais transposée.
    case rotationPortrait
    /// Cet écran recopie un autre. `SCShareableContent` remonte deux `SCDisplay`
    /// pour la MÊME surface : sans ce filtre, la marque atterrit sur le mauvais
    /// `displayID`, et la capture vient d'un écran que l'utilisateur ne regardait
    /// pas.
    case recopieVideo

    var description: String {
        switch self {
        case .rotationPortrait: "écran en rotation — largeur et hauteur inversées"
        case .recopieVideo: "écran en recopie vidéo — il duplique un autre écran"
        }
    }

    /// Ce qu'on dit à l'utilisateur au moment où il tente d'y tracer.
    var conseil: String {
        switch self {
        case .rotationPortrait: "remets-le en paysage dans Réglages > Moniteurs"
        case .recopieVideo: "annote l'écran source, ou désactive la recopie"
        }
    }
}

/// Un écran, réduit à ce dont la conversion a besoin.
///
/// Volontairement découplé de `NSScreen`, pour deux raisons : `NSScreen` n'est pas
/// `Sendable` (leçon du lot 0), et surtout on ne peut pas fabriquer un `NSScreen`
/// fictif pour tester une configuration absente de la machine.
struct ScreenInfo: Equatable, Sendable {
    let displayID: UInt32
    /// Cadre en espace Cocoa : origine bas-gauche de l'écran principal.
    let cocoaFrame: CGRect
    /// 1,0 sur un écran ordinaire, 2,0 sur un Retina. Propriété PAR ÉCRAN.
    let scale: CGFloat
    /// Pourquoi cet écran est écarté, s'il l'est. `nil` = capturable.
    ///
    /// Portée comme une DONNÉE et calculée à la construction : c'est ce qui garde
    /// la structure pure, donc testable sur des dispositions absentes de la
    /// machine — et un écran en rotation portrait n'est pas quelque chose qu'on
    /// met en place pour lancer un test.
    let refus: RefusEcran?

    var capturable: Bool { refus == nil }

    init(displayID: UInt32, cocoaFrame: CGRect, scale: CGFloat, refus: RefusEcran? = nil) {
        self.displayID = displayID
        self.cocoaFrame = cocoaFrame
        self.scale = scale
        self.refus = refus
    }

    /// Décide du refus à partir de ce que Core Graphics rapporte.
    ///
    /// Fonction PURE sur trois entrées, donc vérifiable sans brancher d'écran ni
    /// faire tourner un moniteur.
    ///
    /// Sur la recopie, la règle demande une précision qui n'est pas évidente :
    /// on écarte l'écran qui RECOPIE un autre (`recopieDe != 0`), jamais la source.
    /// Écarter tout membre du jeu de recopie écarterait les deux, et la session
    /// n'aurait plus aucun écran — un refus juste appliqué une fois de trop.
    static func refus(rotation: Double, dansJeuDeRecopie: Bool, recopieDe: UInt32) -> RefusEcran? {
        if dansJeuDeRecopie && recopieDe != 0 { return .recopieVideo }
        let angle = ((rotation.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        // 90 et 270 inversent les dimensions ; 180 ne les inverse pas, et la
        // conversion y reste juste. On ne refuse que ce qui casse vraiment.
        if abs(angle - 90) < 1 || abs(angle - 270) < 1 { return .rotationPortrait }
        return nil
    }
}

/// Disposition complète des écrans, et toutes les conversions qui en dépendent.
struct ScreenGeometry: Sendable {
    let screens: [ScreenInfo]

    init(screens: [ScreenInfo]) {
        self.screens = screens
    }

    /// Les écrans sur lesquels on peut réellement capturer.
    var capturables: [ScreenInfo] { screens.filter(\.capturable) }
    /// Ceux qui sont écartés, avec leur raison. Jamais vidé en silence.
    var refuses: [ScreenInfo] { screens.filter { !$0.capturable } }

    /// Hauteur de l'espace global Cocoa : celle de l'écran dont l'origine est (0, 0).
    ///
    /// Ce n'est PAS « l'écran principal » au sens de `NSScreen.main`, qui désigne celui
    /// portant la fenêtre active et change donc au gré du focus. Utiliser `main` ici
    /// produirait une conversion qui varie selon l'écran où se trouve l'utilisateur :
    /// un défaut parfaitement reproductible sur deux écrans, introuvable sur un seul.
    var flipHeight: CGFloat {
        if let origin = screens.first(where: { $0.cocoaFrame.origin == .zero }) {
            return origin.cocoaFrame.height
        }
        return screens.first?.cocoaFrame.height ?? 0
    }

    // MARK: - Espace des événements ↔ espace Cocoa

    /// `CGEvent.location` (haut-gauche) → espace global Cocoa (bas-gauche).
    func cocoaGlobal(fromEvent p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: flipHeight - p.y)
    }

    /// Espace global Cocoa → `CGEvent.location`.
    ///
    /// L'inversion est son propre inverse : la même formule dans les deux sens.
    func eventLocation(fromCocoa p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: flipHeight - p.y)
    }

    /// Cadre d'un écran dans l'espace `CGEvent.location`.
    ///
    /// L'inversion transforme `maxY` en `flipHeight - maxY` : le bord du HAUT en Cocoa
    /// devient le bord du haut en espace événement, ce qui donne une origine y NÉGATIVE
    /// pour tout écran situé au-dessus de l'écran principal.
    func eventFrame(of screen: ScreenInfo) -> CGRect {
        CGRect(x: screen.cocoaFrame.minX,
               y: flipHeight - screen.cocoaFrame.maxY,
               width: screen.cocoaFrame.width,
               height: screen.cocoaFrame.height)
    }

    // MARK: - Écran portant un point

    /// Écran contenant un point exprimé en `CGEvent.location`.
    ///
    /// Retombe sur l'écran le plus proche plutôt que `nil` : deux écrans de tailles
    /// différentes laissent des interstices où le curseur ne peut pas aller, mais où un
    /// événement synthétique peut atterrir. Perdre le point serait pire que l'attribuer
    /// à l'écran voisin.
    func screen(containingEvent p: CGPoint) -> ScreenInfo? {
        if let hit = screens.first(where: { eventFrame(of: $0).contains(p) }) { return hit }
        return screens.min { a, b in
            distanceSquared(p, eventFrame(of: a)) < distanceSquared(p, eventFrame(of: b))
        }
    }

    private func distanceSquared(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    // MARK: - Espace des événements → coordonnées locales d'une fenêtre

    /// `CGEvent.location` → coordonnées locales d'une fenêtre couvrant `screen`.
    ///
    /// Le panneau couvre exactement son écran, donc son cadre est `screen.cocoaFrame`.
    /// La soustraction se fait en espace Cocoa, après inversion : c'est le seul ordre
    /// qui donne le bon résultat sur un écran à origine négative.
    ///
    /// Résultat en POINTS, pas en pixels : les couches Core Animation travaillent en
    /// points, et c'est `contentsScale` qui gère la densité. Convertir en pixels ici
    /// produirait le décalage ×2 classique.
    func windowLocal(fromEvent p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        let cocoa = cocoaGlobal(fromEvent: p)
        return CGPoint(x: cocoa.x - screen.cocoaFrame.minX,
                       y: cocoa.y - screen.cocoaFrame.minY)
    }

    // MARK: - Espace des événements → pixels d'une capture

    /// `CGEvent.location` → pixel dans une capture plein écran de `screen`.
    ///
    /// La capture a son origine en HAUT à gauche de l'écran, et son échelle est celle
    /// de CET écran — jamais une échelle globale. C'est là que se loge le décalage ×2 :
    /// appliquer l'échelle de l'écran principal à une capture d'un écran non-Retina
    /// double toutes les coordonnées.
    func pixel(fromEvent p: CGPoint, on screen: ScreenInfo) -> CGPoint {
        let frame = eventFrame(of: screen)
        return CGPoint(x: (p.x - frame.minX) * screen.scale,
                       y: (p.y - frame.minY) * screen.scale)
    }

    /// Rectangle en espace événement → rectangle en pixels d'une capture de `screen`.
    func pixelRect(fromEvent r: CGRect, on screen: ScreenInfo) -> CGRect {
        let origin = pixel(fromEvent: r.origin, on: screen)
        return CGRect(x: origin.x, y: origin.y,
                      width: r.width * screen.scale,
                      height: r.height * screen.scale)
    }

    /// Taille en pixels d'une capture plein écran de `screen`.
    func pixelSize(of screen: ScreenInfo) -> CGSize {
        CGSize(width: screen.cocoaFrame.width * screen.scale,
               height: screen.cocoaFrame.height * screen.scale)
    }

    // MARK: - Diagnostic

    func describe() -> [String] {
        var lines: [String] = [String(format: "hauteur de retournement : %.0f pt", flipHeight)]
        for s in screens {
            let ev = eventFrame(of: s)
            let px = pixelSize(of: s)
            lines.append(String(format: "display %u — %.0f×%.0f pt @%.0f×",
                                s.displayID, s.cocoaFrame.width, s.cocoaFrame.height, s.scale))
            lines.append(String(format: "    cocoa (%.0f, %.0f)   event (%.0f, %.0f)   capture %.0f×%.0f px%@",
                                s.cocoaFrame.minX, s.cocoaFrame.minY, ev.minX, ev.minY,
                                px.width, px.height,
                                s.cocoaFrame.minX < 0 || ev.minY < 0 ? "   ← origine négative" : ""))
        }
        if Set(screens.map(\.scale)).count > 1 {
            lines.append("échelles mixtes — ne jamais supposer un facteur global")
        }
        return lines
    }
}
