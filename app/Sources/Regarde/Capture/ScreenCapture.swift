import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
import ScreenCaptureKit
import os

// ─────────────────────────────────────────────────────────────────────────────
// Capture d'un écran — S24, spécification § 4.3
//
// `SCScreenshotManager.captureImage` et non un flux : le lot 2 n'a besoin que d'images
// ponctuelles, et un `SCStream` coûterait un cycle de vie complet — démarrage, frames
// rejetées, arrêt — pour un seul cliché.
//
// Deux réglages ne sont pas négociables :
//
//   excludingApplications  nous y figurons toujours. Sans cela, le calque et ses tracés
//                          se retrouveraient DANS les pixels capturés, et l'agent
//                          recevrait chaque numéro en double : une fois incrusté, une
//                          fois gravé. C'est le risque R12.
//   showsCursor = false    le curseur est composité exactement là où l'utilisateur
//                          trace, donc au centre de chaque recadrage : il masquerait
//                          précisément l'élément annoté. Le point de marque est dessiné
//                          à la gravure, où il est à sa place.
//
// La capture se fait à la résolution NATIVE, pas à celle de l'affichage. Un recadrage
// prélevé dans une image demi-résolution puis agrandi pour l'agent serait flou là où le
// détail compte — et le détail est tout ce qu'une marque désigne.
// ─────────────────────────────────────────────────────────────────────────────

actor ScreenCapture {
    static let shared = ScreenCapture()

    private let log = Logger(subsystem: logSubsystem, category: "capture")

    enum Failure: Error, CustomStringConvertible {
        case noDisplay(CGDirectDisplayID)
        case captureFailed(String)

        var description: String {
            switch self {
            case .noDisplay(let id):
                "l'écran \(id) n'est pas partageable — autorisation d'enregistrement, "
                    + "ou disposition changée depuis la pose de la marque"
            case .captureFailed(let why): "capture impossible : \(why)"
            }
        }
    }

    /// Une capture et l'échelle de l'écran d'où elle vient.
    struct Shot {
        let image: CGImage
        /// Pixels natifs par point. 2 sur un écran Retina, 1 sur un externe ordinaire.
        ///
        /// Nécessaire à la gravure : l'épaisseur d'un trait est décidée en POINTS à
        /// l'écran, et sans cette échelle le graveur ne peut pas la reproduire.
        let pointScale: CGFloat
    }

    /// Capture un écran entier, à sa résolution native.
    func capture(displayID: CGDirectDisplayID) async throws -> Shot {
        // Contenu FRAIS et non le cache du contact TCC : une fenêtre ouverte depuis le
        // dernier rafraîchissement ne serait pas dans la liste, donc pas exclue —
        // exactement le cas d'une notification qui apparaît pendant la session.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)

        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else {
            // L'erreur nomme ce qui EST partageable. Une liste vide veut dire que
            // l'autorisation d'enregistrement manque ; une liste non vide sans l'écran
            // demandé veut dire que la disposition a changé depuis la pose de la marque.
            let available = content.displays.map { "\($0.displayID)" }.joined(separator: ", ")
            // Dans le journal disque et pas seulement dans `os_log` : le lot 1 a montré
            // qu'`os_log` ne rend rien pour ce bundle, et un diagnostic qu'on ne peut
            // pas lire ne diagnostique rien.
            await MainActor.run {
                Journal.warn(.capture, "écran \(displayID) absent — partageables : "
                             + (available.isEmpty ? "AUCUN" : available))
            }
            throw Failure.noDisplay(displayID)
        }

        // Seuls les identifiants traversent : `SCRunningApplication` n'est pas
        // `Sendable`, et le filtre se refait ici sur le contenu local.
        let blocked = await MainActor.run { CaptureExclusions.shared.excludedBundleIDs }
        let excluded = content.applications.filter { blocked.contains($0.bundleIdentifier) }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: excluded,
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        // `filter.contentRect` est en POINTS et `pointPixelScale` donne le facteur : les
        // multiplier redonne la résolution native. Coder ×2 en dur casserait sur un
        // écran externe non-Retina, où le facteur vaut 1.
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsDisplay = true

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            log.notice("capture \(image.width)×\(image.height) sur display \(displayID)")
            return Shot(image: image, pointScale: CGFloat(filter.pointPixelScale))
        } catch {
            throw Failure.captureFailed(error.localizedDescription)
        }
    }

    /// Écrit une image en PNG.
    @discardableResult
    nonisolated static func writePNG(_ image: CGImage, to url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure.captureFailed("destination PNG impossible : \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw Failure.captureFailed("écriture PNG impossible : \(url.path)")
        }
        return url
    }
}
