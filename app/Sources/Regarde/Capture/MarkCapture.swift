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

    /// Une marque à graver, et son intention si elle en porte une.
    ///
    /// Une STRUCT et non `[Int: String?]`, et la raison est un bug qui a coûté une
    /// session de test à l'auteur.
    ///
    /// En Swift, `dict[key] = nil` **supprime la clé** : il n'y a aucun moyen de
    /// distinguer « présente, sans intention » de « absente ». Le dictionnaire construit
    /// par `keep[mark.number] = mark.intention?.label` perdait donc silencieusement
    /// toute marque non qualifiée — c'est-à-dire le cas le plus courant du mode éclair —
    /// et `finalize` n'écrivait aucune image pour elle. Le journal disait
    /// « 1 marque(s), 0 image(s) » sans la moindre erreur.
    ///
    /// Le type porte maintenant la distinction, et le bug n'est plus réécrivable.
    struct Keep: Sendable {
        /// Identité de la marque, et non son numéro.
        ///
        /// Depuis qu'une marque annulée rend son numéro, deux marques différentes peuvent
        /// porter le même au cours d'une session : celle qu'on vient d'effacer et celle
        /// qui la remplace. Indexer par numéro ferait graver les deux dans le même
        /// fichier, dernier écrivain gagnant — et l'image publiée serait celle de la
        /// marque annulée.
        let id: UUID
        let number: Int
        let intention: String?
    }

    /// Une marque et son image, prêtes pour le rapport.
    /// Ce qu'une image écrite représente.
    enum Role: String, Sendable {
        /// Le détail d'une marque.
        case crop
        /// Un écran entier, toutes ses marques gravées.
        case overview
    }

    struct Frame: Sendable {
        let role: Role
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
        let id: UUID
        let number: Int
        let displayID: CGDirectDisplayID
        let shape: MarkShape
        let image: CGImage
        let frame: Engraver.Frame
    }

    private var pending: [Pending] = []

    /// Une vue d'ensemble par écran : l'écran entier, réduit au palier standard.
    ///
    /// Les recadrages montrent chacun leur détail, mais ils ne disent pas où les marques
    /// se situent les unes par rapport aux autres — ce que l'agent doit savoir pour
    /// comprendre « le bouton sous le titre » ou « la colonne de droite ». La vue
    /// d'ensemble répond à cette question, et à elle seule.
    ///
    /// Retenue RÉDUITE, et non en résolution native : garder une capture entière par
    /// écran coûterait 31 Mo là où le palier standard en demande six. La réduction est la
    /// même que celle qu'on lui appliquerait de toute façon à l'écriture.
    ///
    /// C'est la DERNIÈRE capture de l'écran qui est gardée : l'état le plus récent où une
    /// marque y a été posée, donc le plus proche de ce que l'utilisateur avait sous les
    /// yeux en terminant.
    private struct Overview {
        let image: CGImage
        let frame: Engraver.Frame
    }
    private var overviews: [CGDirectDisplayID: Overview] = [:]

    func reset() {
        pending.removeAll()
        overviews.removeAll()
    }

    /// Jette le recadrage d'une marque annulée.
    ///
    /// Appelé au `⌥⌘Z`. Sans lui, le recadrage resterait en attente jusqu'à la
    /// publication, où il serait certes écarté par le filtre — mais il occuperait la
    /// mémoire d'une image pour rien, et la capture pourrait encore être en vol au moment
    /// de l'annulation.
    func discard(id: UUID) {
        pending.removeAll { $0.id == id }
        discarded.insert(id)
    }

    /// Marques annulées, pour refuser une capture arrivée après coup.
    private var discarded: Set<UUID> = []
    var pendingCount: Int { pending.count }

    /// Attend que les captures des marques attendues soient arrivées.
    ///
    /// La capture est lancée depuis l'acteur principal par une tâche détachée : entre la
    /// pose de la marque et son entrée ici, il s'écoule le temps d'un aller-retour
    /// d'ordonnancement plus celui de ScreenCaptureKit. Publier sans attendre laisserait
    /// la dernière marque — celle qu'on vient de tracer, donc celle qui compte — hors du
    /// dossier, sans erreur ni trace.
    ///
    /// Le plafond existe pour qu'une capture perdue ne bloque pas la publication des
    /// autres : mieux vaut un dossier incomplet qu'un dossier qui n'arrive jamais.
    private func waitForCaptures(of expected: Set<UUID>) async {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let present = Set(pending.map(\.id))
            if expected.isSubset(of: present) { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
        let absent = expected.subtracting(Set(pending.map(\.id)))
        if !absent.isEmpty {
            let missing = pending.filter { absent.contains($0.id) }.map(\.number).sorted()
            log.error("captures manquantes après 3 s : \(absent.count, privacy: .public)")
            let list = missing.isEmpty ? "\(absent.count) marque(s)"
                                       : missing.map(String.init).joined(separator: ", ")
            await MainActor.run {
                Journal.warn(.capture, "absente pour \(list)")
            }
        }
    }

    /// Budget de tuiles du palier standard — § 9.2.
    static let standardBudget: Double = 1568

    /// Capture et recadre une marque, sans rien écrire. La gravure viendra à la
    /// fermeture de session, quand l'intention est connue et la marque confirmée.
    func capture(mark: Mark) async throws {
        let shot = try await ScreenCapture.shared.capture(displayID: mark.displayID)
        let capture = shot.image
        let captureSize = CGSize(width: capture.width, height: capture.height)

        // `focusBox` et non `boundingBox` : pour une flèche, le sujet est sa POINTE, pas
        // le rectangle qui contient le trait. Centrer sur la boîte englobante mettait le
        // milieu du trait au centre de l'image et laissait l'élément désigné sur un bord,
        // souvent coupé.
        // La vue d'ensemble, réduite une fois pour toutes.
        let overviewTarget = Cropper.tileTarget(width: capture.width, height: capture.height,
                                                budget: Self.standardBudget)
        let overviewImage = Cropper.scale(
            capture, toLongSide: max(overviewTarget.width, overviewTarget.height))
        let overviewScaleX = CGFloat(overviewImage.width) / captureSize.width
        let overviewScaleY = CGFloat(overviewImage.height) / captureSize.height
        overviews[mark.displayID] = Overview(
            image: overviewImage,
            frame: Engraver.Frame(captureSize: captureSize,
                                  sourceRect: CGRect(origin: .zero, size: captureSize),
                                  scaleX: overviewScaleX, scaleY: overviewScaleY,
                                  pointScale: shot.pointScale))

        let cropped = Cropper.crop(capture, around: mark.shape.focusBox)

        // Le recadreur a déjà tout fait pour un recadrage, facteur compris. L'image
        // entière suit un autre palier : son côté long n'a pas à tenir dans 896, c'est le
        // budget de tuiles qui la borne.
        var image = cropped.image
        var scaleX = cropped.scaleX, scaleY = cropped.scaleY
        if cropped.kind == .full {
            let target = Cropper.tileTarget(width: image.width, height: image.height,
                                            budget: Self.standardBudget)
            let reduced = Cropper.scale(image, toLongSide: max(target.width, target.height))
            scaleX = CGFloat(reduced.width) / CGFloat(image.width)
            scaleY = CGFloat(reduced.height) / CGFloat(image.height)
            image = reduced
        }

        // Une capture peut atterrir ICI après que l'utilisateur a annulé sa marque : la
        // tâche part au relâchement, ScreenCaptureKit prend quelques dizaines de
        // millisecondes, et ⌥⌘Z est plus rapide que ça.
        guard !discarded.contains(mark.id) else {
            log.notice("capture de la marque \(mark.number) jetée — annulée entre-temps")
            return
        }

        pending.append(Pending(
            id: mark.id, number: mark.number, displayID: mark.displayID,
            shape: mark.shape, image: image,
            frame: Engraver.Frame(captureSize: captureSize,
                                  sourceRect: cropped.sourceRect,
                                  scaleX: scaleX, scaleY: scaleY,
                                  pointScale: shot.pointScale)))
        log.notice("marque \(mark.number) capturée — \(cropped.kind.rawValue) \(image.width)×\(image.height)")
    }

    /// Grave et écrit les marques encore présentes dans le modèle.
    ///
    /// Le filtre sur `keep` est ce qui fait qu'une marque annulée par ⌘Z ne laisse aucun
    /// fichier : son recadrage a été capturé, il est simplement jeté sans avoir jamais
    /// touché le disque.
    func finalize(keeping keep: [Keep], into directory: URL) async throws -> [Frame] {
        await waitForCaptures(of: Set(keep.map(\.id)))
        let byID = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })

        var written: [Frame] = []
        for item in pending {
            guard let entry = byID[item.id] else { continue }
            let intention = entry.intention
            let engraved = Engraver.engrave(
                item.image,
                items: [Engraver.Item(number: item.number, shape: item.shape,
                                      intention: intention)],
                frame: item.frame)

            let url = directory.appendingPathComponent(
                String(format: "marque-%02d.png", entry.number))
            try ScreenCapture.writePNG(engraved, to: url)

            let box = item.frame.rect(item.shape.boundingBox)
            let out = item.frame.outputSize
            written.append(Frame(
                role: .crop,
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
        written += writeOverviews(keeping: keep, into: directory)
        pending.removeAll()
        overviews.removeAll()
        return written
    }

    /// Écrit une vue d'ensemble par écran concerné, toutes ses marques gravées.
    ///
    /// Les marques sont prises dans le MODÈLE conservé au moment de la publication, pas
    /// dans le pot de recadrages : une marque annulée n'y figure pas, et l'ensemble doit
    /// montrer exactement ce que les recadrages montrent, ni plus ni moins.
    private func writeOverviews(keeping keep: [Keep], into directory: URL) -> [Frame] {
        let byID = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })

        // Les marques retenues, groupées par écran, dans l'ordre de leur numéro.
        var byDisplay: [CGDirectDisplayID: [Pending]] = [:]
        for item in pending where byID[item.id] != nil {
            byDisplay[item.displayID, default: []].append(item)
        }

        var written: [Frame] = []
        // Un seul écran concerné : le fichier s'appelle « ensemble.png », sans suffixe à
        // déchiffrer. Plusieurs : ils sont numérotés dans l'ordre où ils ont été annotés.
        let displays = byDisplay.keys.sorted {
            (byDisplay[$0]?.first?.number ?? 0) < (byDisplay[$1]?.first?.number ?? 0)
        }

        for (index, displayID) in displays.enumerated() {
            guard let overview = overviews[displayID],
                  let items = byDisplay[displayID], !items.isEmpty else { continue }

            let engraved = Engraver.engrave(
                overview.image,
                items: items.sorted { $0.number < $1.number }.map {
                    Engraver.Item(number: $0.number, shape: $0.shape,
                                  intention: byID[$0.id]?.intention ?? nil)
                },
                frame: overview.frame)

            let name = displays.count == 1 ? "ensemble.png"
                                           : String(format: "ensemble-%d.png", index + 1)
            let url = directory.appendingPathComponent(name)
            do {
                try ScreenCapture.writePNG(engraved, to: url)
            } catch {
                log.error("vue d'ensemble non écrite : \(String(describing: error), privacy: .public)")
                continue
            }
            written.append(Frame(
                role: .overview,
                number: items.map(\.number).min() ?? 0,
                kind: .full,
                url: url,
                pixelSize: CGSize(width: engraved.width, height: engraved.height),
                normalizedInFrame: NormRect(bounding: [NormPoint(x: 0, y: 0),
                                                       NormPoint(x: 1, y: 1)])))
            log.notice("vue d'ensemble → \(name, privacy: .public) — \(items.count) marque(s)")
        }
        return written
    }
}
