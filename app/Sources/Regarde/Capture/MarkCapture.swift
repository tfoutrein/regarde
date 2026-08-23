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
        // ── Ce que S37 y dépose, et pourquoi ce n'est pas dans `Keep` ────────
        //
        // `Keep` ne porte que ce dont la PUBLICATION a besoin : identité, numéro,
        // intention. Le temps, le mouvement et le segment sont des faits de
        // CAPTURE : ils sont connus ici, à la prise, et perdus si on ne les
        // retient pas — au moment de publier, l'écran a bougé depuis longtemps.
        //
        // Le plan de burst (S40) et l'extraction (S39) les liront ici.
        let t: SessionTime
        let motion: MotionSample
        let segmentID: CaptureSegmentID?
        var source: ImageSource
        /// Descripteur de la frame retenue, quand elle vient du flux.
        let ref: FrameRef?
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
    /// Les marques attendues sont passées ENTIÈRES, et non réduites à leurs identités.
    ///
    /// Le numéro d'une capture manquante ne peut pas venir du pot : une capture absente
    /// n'y est, par définition, pas. L'ancienne version le cherchait pourtant là —
    /// `pending.filter { absent.contains($0.id) }` — sur un ensemble construit par
    /// soustraction du pot, donc disjoint de lui : le filtre était vide à tous les coups
    /// et le journal se rabattait en permanence sur son message de repli. Il annonçait
    /// « absente pour 2 marque(s) » sans jamais dire lesquelles, c'est-à-dire sans dire
    /// la seule chose qu'on lui demande.
    private func waitForCaptures(of expected: [Keep]) async {
        let awaited = Set(expected.map(\.id))
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let present = Set(pending.map(\.id))
            if awaited.isSubset(of: present) { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
        let present = Set(pending.map(\.id))
        let absent = expected.filter { !present.contains($0.id) }
        guard !absent.isEmpty else { return }

        let list = absent.map(\.number).sorted().map(String.init).joined(separator: ", ")
        log.error("captures manquantes après 3 s — marques \(list, privacy: .public)")
        await MainActor.run {
            Journal.warn(.capture, "capture absente — marque(s) \(list)")
        }
    }

    /// Budget de tuiles du palier standard — § 9.2.
    static let standardBudget: Double = 1568

    /// Capture et recadre une marque, sans rien écrire. La gravure viendra à la
    /// fermeture de session, quand l'intention est connue et la marque confirmée.
    func capture(mark: Mark, motion: MotionSample = MotionSample()) async throws {
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

        // En `if` explicite : le membre droit de `??` est une autoclosure, où
        // `await` n'est pas permis — quel que soit l'endroit où on l'écrit.
        let segment: CaptureSegmentID?
        if let deja = mark.segmentID {
            segment = deja
        } else {
            segment = await CaptureEngine.shared.segmentID(pour: mark.displayID)
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
                                  pointScale: shot.pointScale),
            // Le segment vient du MOTEUR, pas de la marque : la marque naît au
            // `mouseDown`, avant qu'on sache quel flux la portera, et personne
            // n'était en position de le lui dire ensuite.
            t: mark.t, motion: motion, segmentID: segment,
            // Le chemin de S24 est le FILET du § 5.1 : une image existe quoi qu'il
            // arrive ensuite. L'extraction depuis le fichier encodé la remplace
            // quand elle réussit — et quand elle échoue, ceci reste.
            source: .filetRAM, ref: nil))
        log.notice("marque \(mark.number) capturée — \(cropped.kind.rawValue) \(image.width)×\(image.height)")

        // Le banc C11 date l'ARRIVÉE de l'image. La différence avec `mark.t`, pris
        // au `mouseDown`, est la latence propre du chemin ponctuel — celle que le
        // lot 0 a mesurée à 49,1 ms de médiane et 120,9 ms au pire, et qui est la
        // raison pour laquelle cette chaîne ne peut pas rendre un verdict C11.
        await MainActor.run {
            guard C11Bench.shared.actif else { return }
            C11Bench.shared.noterArrivee(numero: mark.number, t: mark.t, origine: mark.timeOrigin)
        }
    }

    /// Remplace, quand c'est possible, l'image du filet par celle du FICHIER.
    ///
    /// C'est le geste que tout le lot 3 prépare. Le filet du § 5.1 capture au
    /// moment du relâchement ; le fichier, lui, porte l'instant que l'utilisateur
    /// DÉSIGNAIT — celui du `mouseDown`, une à deux secondes plus tôt, quand
    /// l'infobulle était encore ouverte.
    ///
    /// UN SEUL appel de générateur par segment : appelé par marque, il rouvrirait
    /// l'asset et reconstruirait son index à chaque fois, et le budget de 3 s du
    /// traitement final partirait en réouvertures.
    ///
    /// Un échec n'est PAS une panne : la marque garde son image de filet, et sa
    /// provenance le dit. C'est la différence entre un rapport qui se trompe et un
    /// rapport qui se sait moins précis.
    private func remplacerParLExtraction(segments: [CaptureSegment], keep: Set<UUID>) async {
        // Le retour silencieux est ce qui a rendu le défaut d'ordonnancement
        // invisible. Sans segment, cette fonction n'imprimait RIEN : pas de bloc
        // EXTRACTION, pas d'avertissement, et le dossier sortait avec des images de
        // filet qui ont l'air normales. Toute la raison d'être du lot 3 pouvait ne
        // pas s'exécuter sans laisser une ligne.
        //
        // Un segment absent est légitime — mode éclair, écran figé — mais il n'est
        // jamais SANS INTÉRÊT : c'est la différence entre « l'image vient du
        // fichier » et « l'image vient de la capture au relâchement ».
        guard !pending.isEmpty else { return }
        guard !segments.isEmpty else {
            // Le compte est lu ICI, dans l'acteur, et passé par valeur : `pending`
            // lui appartient et ne traverse pas vers l'acteur principal.
            let combien = pending.count
            await MainActor.run {
                Journal.warn(.capture, "aucun segment de capture — les \(combien) "
                             + "marque(s) gardent l'image du filet, prise au relâchement")
            }
            return
        }
        let debut = Date()

        var remplacees = 0, refusees = 0
        var ecarts: [Double] = []

        // L'appariement se fait sur l'ÉCRAN, et non sur l'identité du segment.
        //
        // Un segment appartient à un écran et à une session : dans le chemin
        // nominal, les deux clés désignent la même chose. Mais l'identité peut
        // manquer — c'est arrivé, et l'appariement rendait alors zéro marque sans
        // que rien ne l'explique. L'écran, lui, est connu depuis le `mouseDown` et
        // ne peut pas manquer.
        //
        // Le `segmentID` reste porté par la marque, parce que le § 3.3 en a besoin
        // pour interpréter ses pixels après une réouverture de segment ; il n'est
        // simplement plus la clé dont dépend le fonctionnement.
        let orphelines = pending.filter { keep.contains($0.id) && $0.segmentID == nil }
        if !orphelines.isEmpty {
            let nums = orphelines.map(\.number).sorted().map(String.init).joined(separator: ", ")
            await MainActor.run {
                Journal.warn(.capture, "marque(s) sans segment : \(nums) — appariées sur leur écran")
            }
        }

        for segment in segments {
            let demandes = pending
                .filter { keep.contains($0.id) && $0.displayID == segment.displayID }
                .map { AssetFrames.Demande(markID: $0.id, numero: $0.number,
                                           t: $0.t, motion: $0.motion) }
            guard !demandes.isEmpty else { continue }

            let (images, refus) = await AssetFrames.extraire(demandes, depuis: segment,
                                                             clock: SessionClock.shared)
            for r in images {
                guard let i = pending.firstIndex(where: { $0.id == r.markID }) else { continue }
                let ancien = pending[i]
                // Le recadrage est REFAIT sur l'image extraite : celle du filet a
                // été prélevée dans une autre capture, et réutiliser son découpage
                // reviendrait à découper au bon endroit dans la mauvaise image.
                let taille = CGSize(width: r.image.width, height: r.image.height)
                let recadre = Cropper.crop(r.image, around: ancien.shape.focusBox)
                pending[i] = Pending(
                    id: ancien.id, number: ancien.number, displayID: ancien.displayID,
                    shape: ancien.shape, image: recadre.image,
                    frame: Engraver.Frame(captureSize: taille,
                                          sourceRect: recadre.sourceRect,
                                          scaleX: recadre.scaleX, scaleY: recadre.scaleY,
                                          pointScale: ancien.frame.pointScale),
                    t: ancien.t, motion: ancien.motion, segmentID: ancien.segmentID,
                    source: r.source, ref: ancien.ref)
                ecarts.append(r.ecartMs)
                remplacees += 1
            }
            for (id, motif) in refus {
                refusees += 1
                let numero = pending.first { $0.id == id }?.number ?? 0
                await MainActor.run {
                    Journal.warn(.capture, "marque \(numero) servie par le filet — \(motif)")
                }
            }
        }

        let ms = Date().timeIntervalSince(debut) * 1000
        let pireEcart = ecarts.map(abs).max() ?? 0
        await MainActor.run {
            Journal.block("EXTRACTION", [
                ("depuis le fichier", "\(remplacees)"),
                ("servies par le filet", "\(refusees)"),
                // L'écart entre l'instant demandé et l'instant obtenu est la mesure
                // DIRECTE de ce que B1 aurait coûté. Il doit rester sous un
                // intervalle d'encodage, soit 66,7 ms à 15 fps.
                ("pire écart demandé/obtenu", String(format: "%.1f ms", pireEcart)),
                ("durée", String(format: "%.0f ms", ms)),
            ])
        }
    }

    /// Grave et écrit les marques encore présentes dans le modèle.
    ///
    /// Le filtre sur `keep` est ce qui fait qu'une marque annulée par ⌘Z ne laisse aucun
    /// fichier : son recadrage a été capturé, il est simplement jeté sans avoir jamais
    /// touché le disque.
    func finalize(keeping keep: [Keep], into directory: URL,
                  segments: [CaptureSegment] = []) async throws -> [Frame] {
        await waitForCaptures(of: keep)
        let byID = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        await remplacerParLExtraction(segments: segments, keep: Set(keep.map(\.id)))

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
