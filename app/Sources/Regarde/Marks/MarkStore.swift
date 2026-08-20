import AppKit
import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// État des marques et du tracé en cours — S19
//
// Un tracé appartient à l'écran où il a COMMENCÉ, et y reste jusqu'au relâchement.
//
// Le lot 0 diffusait chaque point à tous les panneaux et laissait le WindowServer
// clipper. C'était correct pour de l'encre anonyme ; ça ne l'est plus dès qu'une marque
// doit savoir de quel écran elle vient — la capture du lot 2 (S24) et l'appariement du
// lot 3 en dépendent tous les deux.
//
// Router au `mouseDown` plutôt qu'à chaque point préserve la propriété qui comptait dans
// la diffusion : un trait qui traverse la frontière entre deux écrans reste un seul
// trait, simplement clippé à l'affichage.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class MarkStore {
    static let shared = MarkStore()

    /// Marques posées, dans l'ordre de création.
    private(set) var marks: [Mark] = []

    /// Outil actif. Changement au clavier en S20.
    var tool: MarkTool = .arrow

    /// Prochain numéro. Ne décroît JAMAIS, même après suppression (ADR-0013).
    private var nextNumber = 1

    // MARK: - Tracé en cours

    private struct LiveStroke {
        let displayID: CGDirectDisplayID
        let panelSize: CGSize
        let start: NormPoint
        var current: NormPoint
        let tool: MarkTool
    }

    private var live: LiveStroke?

    var hasLiveStroke: Bool { live != nil }
    var liveDisplayID: CGDirectDisplayID? { live?.displayID }

    // MARK: - Cycle d'un geste

    /// Début d'un tracé. Fixe l'écran porteur pour toute sa durée.
    func beginStroke(at eventPoint: CGPoint, geometry: ScreenGeometry) {
        guard let screen = geometry.screen(containingEvent: eventPoint) else { return }
        let size = screen.cocoaFrame.size
        let localPoint = geometry.windowLocal(fromEvent: eventPoint, on: screen)
        let norm = NormPoint(local: localPoint, in: size)

        live = LiveStroke(displayID: screen.displayID, panelSize: size,
                          start: norm, current: norm, tool: tool)
    }

    /// Prolongement du tracé. Les points restent rapportés à l'écran de départ, même
    /// quand le curseur passe sur un autre : la marque appartient à son écran d'origine.
    func extendStroke(to eventPoint: CGPoint, geometry: ScreenGeometry) {
        guard var stroke = live,
              let screen = geometry.screens.first(where: { $0.displayID == stroke.displayID })
        else { return }
        let localPoint = geometry.windowLocal(fromEvent: eventPoint, on: screen)
        stroke.current = NormPoint(local: localPoint, in: stroke.panelSize)
        live = stroke
    }

    /// Fin du tracé. Retourne la marque créée, ou `nil` si le geste était trop court.
    @discardableResult
    func endStroke() -> Mark? {
        defer { live = nil }
        guard let stroke = live else { return nil }
        guard let shape = MarkGeometry.shape(for: stroke.tool, from: stroke.start,
                                             to: stroke.current, in: stroke.panelSize)
        else { return nil }

        let mark = Mark(number: nextNumber, displayID: stroke.displayID,
                        shape: shape, tool: stroke.tool)
        nextNumber += 1
        marks.append(mark)
        return mark
    }

    /// Abandonne le tracé en cours sans rien poser. `Échap` et le clic droit y mènent.
    ///
    /// Le numéro n'est PAS consommé : l'utilisateur n'a pas encore pu le prononcer,
    /// c'est le seul cas où le réutiliser est légitime (ADR-0013).
    func cancelStroke() {
        live = nil
    }

    // MARK: - Édition

    /// Supprime la dernière marque. Le numéro n'est PAS rendu : il laisse un trou,
    /// parce que l'utilisateur a pu le prononcer à voix haute.
    @discardableResult
    func undoLast() -> Mark? {
        guard !marks.isEmpty else { return nil }
        return marks.removeLast()
    }

    func clear() {
        marks.removeAll()
        live = nil
        // `nextNumber` n'est pas remis à zéro : les numéros d'une session sont uniques.
    }

    // MARK: - Rendu

    /// Chemin des marques posées sur un écran, dans un cadre de taille donnée.
    func committedPath(for displayID: CGDirectDisplayID, size: CGSize,
                       lineWidth: CGFloat) -> CGPath? {
        let onScreen = marks.filter { $0.displayID == displayID }
        guard !onScreen.isEmpty else { return nil }
        let path = CGMutablePath()
        for mark in onScreen {
            path.addPath(MarkGeometry.path(for: mark.shape, in: size, lineWidth: lineWidth))
        }
        return path
    }

    /// Chemin du tracé en cours, s'il appartient à cet écran.
    func livePath(for displayID: CGDirectDisplayID, size: CGSize,
                  lineWidth: CGFloat) -> CGPath? {
        guard let stroke = live, stroke.displayID == displayID else { return nil }
        guard let shape = MarkGeometry.shape(for: stroke.tool, from: stroke.start,
                                             to: stroke.current, in: size)
        else { return nil }
        return MarkGeometry.path(for: shape, in: size, lineWidth: lineWidth)
    }

    // MARK: - Diagnostic

    var count: Int { marks.count }

    func describe() -> [String] {
        guard !marks.isEmpty else { return ["aucune marque"] }
        return marks.map { m in
            let b = m.shape.boundingBox
            return String(format: "%d · %@ sur display %u — bbox (%.3f, %.3f) %.3f×%.3f",
                          m.number, m.tool.label, m.displayID, b.x, b.y, b.w, b.h)
        }
    }
}
