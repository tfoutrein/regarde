import CoreGraphics
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Du geste au PNG — enchaînement S24 → S25 → S26
//
// La capture a lieu à la POSE de la marque, pas en fin de session. C'est le seul instant
// où l'écran montre ce que l'utilisateur désigne : une infobulle se referme, une
// animation se termine, un menu disparaît. Capturer à la fin donnerait six images d'un
// même écran au repos, où plus aucune des six marques n'aurait de sens.
//
// L'ordre des trois étapes est contraint :
//
//   1. capturer à la résolution native — un recadrage prélevé dans une image demi-
//      résolution serait flou là où le détail compte
//   2. recadrer, puis réduire si le palier l'exige
//   3. graver EN DERNIER — graver avant de réduire diviserait l'épaisseur du trait par
//      le même facteur, et un trait de 3 px devenu 1,5 px disparaît à la compression
//
// L'ensemble tourne dans un acteur : deux marques posées coup sur coup ne doivent pas
// lancer deux captures concurrentes, qui se disputeraient la même ressource système pour
// un résultat identique en moins bon.
//
// La gravure est DIFFÉRÉE à la fin de session, alors que la capture, elle, ne peut pas
// l'être. Deux raisons, et la seconde est la plus forte :
//
//   l'intention arrive après le relâchement — ⌥⌘ + chiffre se frappe une fois la marque
//   posée. Graver dans la foulée écrirait un badge nu, puis il faudrait réécrire le
//   fichier au premier chiffre frappé.
//
//   ⌘Z supprime la dernière marque. Un PNG déjà écrit devrait alors être effacé, et un
//   fichier qu'on efface est un fichier qui peut survivre à un plantage — donc une image
//   d'une marque annulée dans le rapport.
//
// Ce qui est retenu entre les deux est le RECADRAGE, pas la capture entière : environ
// 2 Mo par marque au lieu de 31.
// ─────────────────────────────────────────────────────────────────────────────

actor MarkCapture {
    static let shared = MarkCapture()

    private let log = Logger(subsystem: logSubsystem, category: "markcapture")

    /// Une marque et son image, prêtes pour le rapport.
    struct Frame: Sendable {
        let number: Int
        let kind: Cropper.Kind
        let url: URL
        let pixelSize: CGSize
        /// Boîte de la marque dans l'image écrite, normalisée. C'est ce que le rapport
        /// donnera à l'agent pour situer la marque sans recharger la capture entière.
        let normalizedInFrame: NormRect
    }

    /// Un recadrage en attente de gravure.
    private struct Pending {
        let number: Int
        let shape: MarkShape
        let image: CGImage
        let frame: Engraver.Frame
    }

    private var pending: [Pending] = []

    func reset() { pending.removeAll() }
    var pendingCount: Int { pending.count }

    /// Budget de tuiles du palier standard — § 9.2.
    static let standardBudget: Double = 1568

    /// Capture et recadre une marque, sans rien écrire. La gravure viendra à la
    /// fermeture de session, quand l'intention est connue et la marque confirmée.
    func capture(mark: Mark) async throws {
        let capture = try await ScreenCapture.shared.capture(displayID: mark.displayID)
        let captureSize = CGSize(width: capture.width, height: capture.height)

        let cropped = Cropper.crop(capture, around: mark.shape.boundingBox)

        // Mise à la forme finale : côté long ramené sous 896 px par réduction — jamais
        // par rognage, qui couperait la marque — puis dimensions alignées sur la tuile.
        //
        // L'image entière suit un autre palier : son côté long n'a pas à tenir dans 896,
        // c'est le budget de tuiles qui la borne.
        var image = cropped.image
        if cropped.kind == .full {
            let target = Cropper.tileTarget(width: image.width, height: image.height,
                                            budget: Self.standardBudget)
            image = Cropper.scale(image, toLongSide: max(target.width, target.height))
        } else {
            image = Cropper.fitToTiles(image)
        }
        let scale = CGFloat(image.width) / CGFloat(cropped.image.width)

        pending.append(Pending(
            number: mark.number, shape: mark.shape, image: image,
            frame: Engraver.Frame(captureSize: captureSize,
                                  sourceRect: cropped.sourceRect, scale: scale)))
        log.notice("marque \(mark.number) capturée — \(cropped.kind.rawValue) \(image.width)×\(image.height)")
    }

    /// Grave et écrit les marques encore présentes dans le modèle.
    ///
    /// Le filtre sur `keep` est ce qui fait qu'une marque annulée par ⌘Z ne laisse aucun
    /// fichier : son recadrage a été capturé, il est simplement jeté sans avoir jamais
    /// touché le disque.
    func finalize(keeping keep: [Int: String?], into directory: URL) throws -> [Frame] {
        var written: [Frame] = []
        for item in pending {
            guard let intention = keep[item.number] else { continue }
            let engraved = Engraver.engrave(
                item.image,
                items: [Engraver.Item(number: item.number, shape: item.shape,
                                      intention: intention)],
                frame: item.frame)

            let url = directory.appendingPathComponent(
                String(format: "marque-%02d.png", item.number))
            try ScreenCapture.writePNG(engraved, to: url)

            let box = item.frame.rect(item.shape.boundingBox)
            let out = item.frame.outputSize
            written.append(Frame(
                number: item.number,
                kind: item.frame.sourceRect.size == item.frame.captureSize ? .full : .crop,
                url: url,
                pixelSize: CGSize(width: engraved.width, height: engraved.height),
                normalizedInFrame: NormRect(bounding: [
                    NormPoint(x: Double(box.minX / max(out.width, 1)),
                              y: Double(box.minY / max(out.height, 1))),
                    NormPoint(x: Double(box.maxX / max(out.width, 1)),
                              y: Double(box.maxY / max(out.height, 1)))])))
            log.notice("marque \(item.number) gravée → \(url.lastPathComponent, privacy: .public)")
        }
        pending.removeAll()
        return written
    }
}
