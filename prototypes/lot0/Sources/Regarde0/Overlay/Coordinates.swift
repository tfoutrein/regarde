import AppKit
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// Conversion entre espaces de coordonnees — specification § 3.3
//
// Trois espaces, et deux d'entre eux ont des origines OPPOSEES :
//
//   CGEvent.location   origine HAUT-gauche de l'ecran principal, global, en points
//   Cocoa / NSScreen   origine BAS-gauche de l'ecran principal, global, en points
//   Buffer ScreenCaptureKit  origine haut-gauche du contentRect de la frame, en PIXELS
//
// Le troisieme n'intervient qu'au lot 3. Les deux premiers suffisent a produire des
// traits deux fois trop loin, ou en miroir vertical, si la conversion est faite au
// jugé. Elle est donc faite ici, une fois, et nulle part ailleurs.
//
// Piege supplementaire : un ecran place a GAUCHE de l'ecran principal a une origine
// x NEGATIVE. Tout code qui suppose des coordonnees positives casse silencieusement
// dans cette configuration — c'est un critere explicite du lot 2.
// ─────────────────────────────────────────────────────────────────────────────

enum Coordinates {

    /// Hauteur de l'espace global Cocoa, c'est-a-dire la hauteur de l'ecran dont
    /// l'origine est (0, 0).
    ///
    /// Ce n'est PAS `NSScreen.main`, qui designe l'ecran portant la fenetre active et
    /// change donc au gre du focus. Utiliser `main` ici produirait une conversion qui
    /// varie selon l'ecran ou se trouve l'utilisateur : un bug parfaitement reproductible
    /// sur deux ecrans, et introuvable sur un seul.
    static var globalFlipHeight: CGFloat {
        // `screens.first` est l'ecran principal au sens Cocoa : celui dont le frame a
        // pour origine (0, 0). On le cherche explicitement plutot que de s'y fier.
        let screens = NSScreen.screens
        if let zero = screens.first(where: { $0.frame.origin == .zero }) {
            return zero.frame.height
        }
        return screens.first?.frame.height ?? 0
    }

    /// `CGEvent.location` (haut-gauche) vers l'espace global Cocoa (bas-gauche).
    static func cocoaGlobal(fromEventLocation p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: globalFlipHeight - p.y)
    }

    /// Espace global Cocoa vers `CGEvent.location`.
    static func eventLocation(fromCocoaGlobal p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: globalFlipHeight - p.y)
    }

    /// `CGEvent.location` vers les coordonnees locales d'une fenetre.
    ///
    /// - Parameter windowFrame: cadre de la fenetre en espace global Cocoa.
    static func windowLocal(fromEventLocation p: CGPoint, windowFrame: CGRect) -> CGPoint {
        let g = cocoaGlobal(fromEventLocation: p)
        return CGPoint(x: g.x - windowFrame.minX, y: g.y - windowFrame.minY)
    }

    /// Cadre d'un ecran dans l'espace `CGEvent.location`.
    ///
    /// Sert a savoir quel panneau doit recevoir un point, sans faire le tour des
    /// conversions pour chacun.
    static func eventSpaceFrame(of screen: NSScreen) -> CGRect {
        let f = screen.frame
        let h = globalFlipHeight
        // L'inversion transforme minY en (h - maxY) : le bord du bas devient le bord du haut.
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height)
    }

    /// Ecran contenant un point exprime en `CGEvent.location`.
    static func screen(containingEventLocation p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { eventSpaceFrame(of: $0).contains(p) }
            // Un point peut tomber dans un interstice entre deux ecrans de tailles
            // differentes : on rabat alors sur le plus proche plutot que de perdre le point.
            ?? NSScreen.screens.min { a, b in
                distanceSquared(p, eventSpaceFrame(of: a)) < distanceSquared(p, eventSpaceFrame(of: b))
            }
    }

    private static func distanceSquared(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    /// Description lisible de la disposition des ecrans, pour le rapport de lancement.
    ///
    /// On l'imprime au demarrage parce que la moitie des anomalies de position
    /// s'expliquent par une disposition qu'on avait en tete de travers.
    static func describeScreens() -> String {
        var lines = ["┌─ Ecrans ─────────────────────────────────────────────────────────┐"]
        for (i, s) in NSScreen.screens.enumerated() {
            let f = s.frame
            let ev = eventSpaceFrame(of: s)
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            lines.append(String(format: "│ %d · display %-4u  %@x  %.0f×%.0f pt",
                                i, id, s.backingScaleFactor as NSNumber, f.width, f.height))
            lines.append(String(format: "│     cocoa  (%.0f, %.0f)   event  (%.0f, %.0f)%@",
                                f.minX, f.minY, ev.minX, ev.minY,
                                f.minX < 0 ? "   ← origine x NEGATIVE" : ""))
        }
        lines.append(String(format: "│ hauteur de retournement : %.0f pt", globalFlipHeight))
        lines.append("└──────────────────────────────────────────────────────────────────┘")
        return lines.joined(separator: "\n")
    }
}
