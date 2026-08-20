import AppKit
import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Vérification de bout en bout de la capture — `--capture-demo`
//
// Pose quatre marques directement dans le modèle, puis déroule la chaîne réelle :
// capture ScreenCaptureKit, recadrage, gravure, écriture. Le chemin tap → porte → ring
// est court-circuité, et seulement lui — il est couvert par `--selftest` et par les
// scénarios d'injection.
//
// Cette voie existe parce que l'injection d'événements dépend d'une autorisation
// d'accessibilité accordée au processus PARENT, qui peut tomber d'une exécution à
// l'autre. Faire dépendre la vérification de la capture d'une permission sans rapport
// avec elle, c'est se retrouver incapable de prouver que la gravure fonctionne le jour
// où le terminal perd un droit.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
enum CaptureDemo {

    /// Marques posées en proportions de l'écran, une par outil.
    private static let layout: [(MarkTool, NormRect, Intention?)] = [
        (.arrow, NormRect(bounding: [NormPoint(x: 0.20, y: 0.62), NormPoint(x: 0.32, y: 0.72)]), .error),
        (.rect, NormRect(bounding: [NormPoint(x: 0.42, y: 0.55), NormPoint(x: 0.58, y: 0.68)]), .misaligned),
        (.point, NormRect(bounding: [NormPoint(x: 0.70, y: 0.60), NormPoint(x: 0.70, y: 0.60)]), .slow),
        (.highlight, NormRect(bounding: [NormPoint(x: 0.25, y: 0.35), NormPoint(x: 0.55, y: 0.40)]), .textToFix),
    ]

    static func run() {
        Journal.write("── démonstration de capture ──")

        guard let screen = NSScreen.main else {
            Journal.write("aucun écran")
            exit(1)
        }
        let displayID = OverlayPanel.displayID(of: screen)

        var marks: [Mark] = []
        for (index, entry) in layout.enumerated() {
            let (tool, box, intention) = entry
            let shape: MarkShape = switch tool {
            case .arrow: .arrow(from: NormPoint(x: box.x, y: box.y + box.h),
                                to: NormPoint(x: box.x + box.w, y: box.y))
            case .rect: .rect(box)
            case .point: .point(NormPoint(x: box.x, y: box.y))
            case .highlight: .highlight(box)
            }
            marks.append(Mark(number: index + 1, displayID: displayID,
                              shape: shape, tool: tool, intention: intention))
        }

        Task {
            do {
                let directory = try SessionPaths.makeSessionDirectory()
                await MarkCapture.shared.reset()

                for mark in marks {
                    try await MarkCapture.shared.capture(mark: mark)
                }

                var keep: [Int: String?] = [:]
                for mark in marks { keep[mark.number] = mark.intention?.label }

                let frames = try await MarkCapture.shared.finalize(
                    keeping: keep, into: SessionPaths.frames(of: directory))

                Journal.section("Images écrites", frames.map { f in
                    String(format: "%@ — %@ %.0f×%.0f",
                           f.url.lastPathComponent, f.kind.rawValue,
                           f.pixelSize.width, f.pixelSize.height)
                })
                print(directory.path)
                exit(frames.count == marks.count ? 0 : 1)
            } catch {
                Journal.write("⚠ démonstration : \(error)")
                exit(2)
            }
        }
    }
}
