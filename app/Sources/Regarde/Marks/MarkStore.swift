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
        /// Numéro réservé dès la pression, pas au relâchement (ADR-0013).
        let number: Int
        /// Le geste est-il sorti du cadre de son écran ?
        var clipped: Bool = false
        /// Instant de la PRESSION, retenu ici parce qu'il se perd sinon : entre le
        /// `mouseDown` et le `mouseUp` qui construit la marque, il s'écoule tout le
        /// geste, et `now()` au relâchement daterait la marque d'après ce qu'elle
        /// désigne.
        let stamped: StampedTime
        /// Numéro de la demande d'instantané déposée à la pression (S37).
        let snapshot: UInt64
    }

    private var live: LiveStroke?

    var hasLiveStroke: Bool { live != nil }
    var liveDisplayID: CGDirectDisplayID? { live?.displayID }
    /// Numéro du tracé en cours, à afficher pendant le geste.
    var liveNumber: Int? { live?.number }

    // MARK: - Cycle d'un geste

    /// Début d'un tracé. Fixe l'écran porteur pour toute sa durée.
    ///
    /// **Invariant : une marque naît dans le repère de son ÉCRAN, jamais dans celui d'une
    /// frame.** `NormPoint` est normalisé ici contre `screen.cocoaFrame.size`, et c'est
    /// ce même cadre que le calque relit à chaque redessin — donc c'est lui, et lui seul,
    /// que l'utilisateur a sous les yeux en désignant quelque chose.
    ///
    /// La tentation, quand arrive la capture continue, est de normaliser plutôt sur le
    /// `contentRect` de la frame retenue, puisque c'est ce que demande l'ADR-0009 pour
    /// les pixels. Ce serait faux ici, pour deux raisons : la frame retenue n'existe
    /// qu'APRÈS l'appariement, c'est-à-dire longtemps après ce `mouseDown` ; et le calque
    /// se retrouverait décalé de la marge de boîtage même qu'on prétend supprimer.
    ///
    /// La conversion vers le repère de la frame appartient à `FrameRef` et à
    /// `Engraver.Frame` : une couture unique, du côté des pixels, pas du côté du modèle.
    func beginStroke(at eventPoint: CGPoint, geometry: ScreenGeometry,
                     hostTicks: UInt64 = 0, snapshot: UInt64 = 0) {
        guard let screen = geometry.screen(containingEvent: eventPoint) else { return }

        // Un écran écarté refuse le geste, et le DIT.
        //
        // Laisser tracer serait pire que refuser : le trait apparaîtrait, le numéro
        // s'incrémenterait, l'utilisateur croirait sa marque posée — et le dossier
        // sortirait sans son image. Le § 3.3 demande un refus PROPRE, pas une
        // absence.
        //
        // Le cas vivant ici est la ROTATION : l'écran pivoté garde son espace de
        // coordonnées, un geste peut y tomber. La recopie vidéo, elle, ne passe
        // jamais par ce chemin — macOS retire l'écran copieur de NSScreen, il n'a
        // pas d'espace propre, et « tracer dessus » est tracer sur la source.
        if let refus = screen.refus {
            Journal.warn(.mark, "geste refusé sur l'écran \(screen.displayID) — \(refus)")
            HUDWindow.shared.announce("Écran non annotable",
                                      detail: "\(refus) — \(refus.conseil)", duration: 4)
            return
        }

        // Horodaté ICI, au plus près de la pression. `stamp` rend toujours un instant
        // utilisable : jamais on ne perd une marque à cause d'un timestamp aberrant,
        // c'est l'origine qui dit s'il est fiable.
        let stamped = SessionClock.shared.stamp(hostTicks: hostTicks)
        let size = screen.cocoaFrame.size
        let localPoint = geometry.windowLocal(fromEvent: eventPoint, on: screen)
        let norm = NormPoint(local: localPoint, in: size)

        // Le numéro est réservé ICI, à la pression — pas au relâchement.
        //
        // L'utilisateur prononce les numéros à voix haute pendant qu'il trace : « comme
        // sur la marque 2 ». Attribuer au relâchement rendrait le badge invisible
        // pendant le geste, donc le numéro imprononçable au moment où il en a besoin.
        live = LiveStroke(displayID: screen.displayID, panelSize: size,
                          start: norm, current: norm, tool: tool, number: nextNumber,
                          stamped: stamped, snapshot: snapshot)
        nextNumber += 1
    }

    /// Prolongement du tracé. Les points restent rapportés à l'écran de départ, même
    /// quand le curseur passe sur un autre : la marque appartient à son écran d'origine.
    func extendStroke(to eventPoint: CGPoint, geometry: ScreenGeometry) {
        guard var stroke = live,
              let screen = geometry.screens.first(where: { $0.displayID == stroke.displayID })
        else { return }
        let localPoint = geometry.windowLocal(fromEvent: eventPoint, on: screen)

        // Un geste peut sortir de l'écran où il a commencé — le poursuivre sur l'écran
        // voisin est même un cas prévu. Le point est alors ramené au bord, parce que la
        // marque ne peut décrire que ce qui est visible et capturable, mais on le
        // RETIENT : une marque tronquée sans un mot laisserait croire que la flèche
        // désigne le bord de l'écran alors qu'elle visait au-delà.
        if localPoint.x < 0 || localPoint.y < 0
            || localPoint.x > stroke.panelSize.width || localPoint.y > stroke.panelSize.height {
            stroke.clipped = true
        }
        stroke.current = NormPoint(local: localPoint, in: stroke.panelSize)
        live = stroke
    }

    /// Fin du tracé. Retourne la marque créée, ou `nil` si le geste était trop court.
    @discardableResult
    func endStroke() -> Mark? {
        guard let stroke = live else { live = nil; return nil }
        guard let shape = MarkGeometry.shape(for: stroke.tool, from: stroke.start,
                                             to: stroke.current, in: stroke.panelSize)
        else {
            // Geste trop court : rien n'est posé, et le numéro repart au pot.
            //
            // Mais le DIRE : trois gestes avalés sans un mot ont coûté un
            // diagnostic entier en recette du lot 4 (§ 3.3 — « refusé
            // proprement, non silencieusement »). Un geste hors écran arrive
            // borné au même point : trop court, lui aussi.
            Journal.warn(.mark, "geste trop court — aucune marque posée "
                         + "(\(stroke.tool.label), écran \(stroke.displayID))")
            releaseNumberIfLast()
            live = nil
            return nil
        }
        defer { live = nil }

        if stroke.clipped {
            Journal.warn(.mark, "\(stroke.number) · le geste est sorti de l'écran "
                         + "\(stroke.displayID), la marque s'arrête au bord")
        }
        let mark = Mark(number: stroke.number, displayID: stroke.displayID,
                        shape: shape, tool: stroke.tool,
                        target: TargetWindow.shared.target?.name,
                        t: stroke.stamped.time, timeOrigin: stroke.stamped.origin,
                        snapshot: stroke.snapshot)
        marks.append(mark)
        return mark
    }

    /// Abandonne le tracé en cours sans rien poser. `Échap` et le clic droit y mènent.
    ///
    /// Le numéro n'est PAS consommé : l'utilisateur n'a pas encore pu le prononcer,
    /// c'est le seul cas où le réutiliser est légitime (ADR-0013).
    func cancelStroke() {
        releaseNumberIfLast()
        live = nil
    }

    /// Rend le numéro réservé, s'il est encore le dernier attribué.
    ///
    /// Seul cas légitime de réutilisation : le tracé a été abandonné avant que
    /// l'utilisateur ait pu prononcer son numéro. La garde `== nextNumber - 1` évite de
    /// rendre un numéro qu'une marque suivante aurait déjà dépassé.
    private func releaseNumberIfLast() {
        guard let stroke = live, stroke.number == nextNumber - 1 else { return }
        nextNumber -= 1
    }

    // MARK: - La marque rétroactive (S65, § 5.1)

    /// Pose une marque datée de `secondes` avant maintenant, au point donné.
    ///
    /// Un POINT, pas un cadre : la rétroactive désigne un INSTANT — le toast
    /// qui vient de disparaître — et l'utilisateur n'a rien pu entourer, la
    /// chose n'est plus à l'écran. Sa forme est celle de l'outil point, à la
    /// position du curseur ; son image sera extraite du fichier encodé à T−N
    /// (§ 5.1), pas de l'anneau, qui ne couvre que 0,27 s.
    @discardableResult
    func poserRetroactive(secondes: Int, at eventPoint: CGPoint,
                          geometry: ScreenGeometry) -> Mark? {
        guard let screen = geometry.screen(containingEvent: eventPoint),
              screen.capturable else { return nil }
        let size = screen.cocoaFrame.size
        let local = geometry.windowLocal(fromEvent: eventPoint, on: screen)
        let norm = NormPoint(local: local, in: size)
        let maintenant = SessionClock.shared.now()
        let quand = SessionTime(seconds: max(0, maintenant.seconds - Double(secondes)))
        let mark = Mark(number: nextNumber, displayID: screen.displayID,
                        shape: .point(norm), tool: .point,
                        target: TargetWindow.shared.target?.name,
                        t: quand, timeOrigin: .hardware,
                        isRetroactive: true, snapshot: 0)
        nextNumber += 1
        marks.append(mark)
        return mark
    }

    // MARK: - Intentions (S23)

    /// Résultat d'une frappe de chiffre, pour que le HUD dise ce qui s'est passé.
    enum IntentionOutcome {
        case applied(mark: Int, intention: Intention)
        case noMark
        case muted(Int64)
    }

    /// Applique une intention à la marque qualifiable.
    ///
    /// La cible est la DERNIÈRE marque posée. L'ADR-0021 la définit comme « la marque
    /// attachée à la fenêtre de parole courante » ; la fenêtre de parole arrive au lot 5,
    /// et jusque-là la dernière marque en est l'approximation exacte — il n'existe pas
    /// encore de fenêtre pouvant contenir autre chose.
    @discardableResult
    func apply(_ intention: Intention) -> IntentionOutcome {
        guard let index = marks.indices.last else { return .noMark }
        marks[index].intention = intention
        return .applied(mark: marks[index].number, intention: intention)
    }

    // MARK: - Édition

    /// Supprime la dernière marque, et lui reprend son numéro.
    ///
    /// Le numéro EST rendu, contrairement à la première version de l'ADR-0013.
    ///
    /// L'argument qui a tranché vient de l'usage : `Échap` et `⌥⌘Z` font la même chose du
    /// point de vue de l'utilisateur — annuler une marque qu'on vient de faire — et
    /// `Échap` rendait déjà le numéro. Deux gestes équivalents avec deux résultats
    /// différents, c'est une incohérence, pas une décision.
    ///
    /// L'objection d'origine était qu'un numéro prononcé à voix haute ne doit pas changer
    /// de sens. Elle ne tient pas ici : `⌥⌘Z` ne supprime que la DERNIÈRE marque, celle
    /// qu'on vient de tracer, et si on l'annule c'est précisément qu'on renonce à ce
    /// qu'on venait d'en dire. Un trou dans la numérotation, lui, reste inexplicable pour
    /// qui relit le rapport.
    @discardableResult
    func undoLast() -> Mark? {
        guard let mark = marks.popLast() else { return nil }
        if mark.number == nextNumber - 1 { nextNumber -= 1 }

        // Le recadrage déjà capturé part avec elle. Sans cela il attendrait la
        // publication sous un numéro qu'une autre marque porte désormais.
        Task { await MarkCapture.shared.discard(id: mark.id) }
        return mark
    }

    func clear() {
        marks.removeAll()
        live = nil
        // `nextNumber` n'est pas remis à zéro : les numéros d'une session sont uniques.
    }

    /// Remise à neuf pour une NOUVELLE session. C'est le seul endroit où la numérotation
    /// repart de 1 — l'unicité promise par l'ADR-0013 vaut à l'intérieur d'une session,
    /// pas d'une session à l'autre, sans quoi les numéros grandiraient sans fin.
    func reset(keepingTool: Bool = false) {
        clear()
        nextNumber = 1
        // L'outil survit à une publication éclair, pas à une nouvelle session.
        //
        // Le mode éclair publie tout seul 0,8 s après le relâchement de ⌥⌘ : remettre la
        // flèche à ce moment-là ferait perdre le surlignage que l'utilisateur venait de
        // choisir, sans un mot au HUD ni au journal. Il tracerait sa marque suivante avec
        // le mauvais outil sans savoir pourquoi.
        //
        // Une session explicite, elle, est un nouveau départ annoncé : y repartir de la
        // flèche est prévisible.
        if !keepingTool { tool = .arrow }

        // Le pot de captures n'est PAS vidé ici, et ce silence est délibéré.
        //
        // Il l'a été, une nuit, pour empêcher une session abandonnée de laisser des items
        // périmés. Le remède a cassé le cas normal : la publication vide le modèle avant
        // de lancer la gravure, les deux tâches couraient vers le même acteur, et le pot
        // se vidait avant que `finalize` n'y arrive. Symptôme relevé par l'auteur dès la
        // première marque — « 1 marque(s), 0 image(s) », trois fois de suite.
        //
        // Le nettoyage du pot appartient aux moments où l'on RENONCE à publier :
        // l'ouverture d'une session, une suspension. Jamais au vidage du modèle, qui
        // précède justement une publication.
    }

    // MARK: - Rendu

    /// Chemins des marques posées sur un écran, groupés par mode de peinture.
    ///
    /// Le groupement se fait ici plutôt que dans la vue : fusionner les formes d'un même
    /// mode en un seul `CGPath` laisse trois couches à recomposer quel que soit le nombre
    /// de marques, là où une couche par marque ferait grossir l'arbre à chaque geste.
    func committedPaths(for displayID: CGDirectDisplayID, size: CGSize,
                        lineWidth: CGFloat) -> [MarkRendering: CGPath] {
        var byRendering: [MarkRendering: CGMutablePath] = [:]
        for mark in marks where mark.displayID == displayID {
            let path = byRendering[mark.shape.rendering] ?? CGMutablePath()
            path.addPath(MarkGeometry.path(for: mark.shape, in: size, lineWidth: lineWidth))
            byRendering[mark.shape.rendering] = path
        }
        return byRendering
    }

    /// Chemin du tracé en cours, s'il appartient à cet écran.
    func livePaths(for displayID: CGDirectDisplayID, size: CGSize,
                   lineWidth: CGFloat) -> [MarkRendering: CGPath] {
        guard let stroke = live, stroke.displayID == displayID else { return [:] }
        guard let shape = MarkGeometry.shape(for: stroke.tool, from: stroke.start,
                                             to: stroke.current, in: size)
        else { return [:] }
        return [shape.rendering: MarkGeometry.path(for: shape, in: size, lineWidth: lineWidth)]
    }

    /// Numéros à afficher sur un écran, tracé en cours compris.
    func badges(for displayID: CGDirectDisplayID, size: CGSize) -> [BadgeSpec] {
        var specs = marks.filter { $0.displayID == displayID }.map { mark -> BadgeSpec in
            let a = MarkGeometry.badgeAnchor(for: mark.shape, in: size)
            return BadgeSpec(number: mark.number, anchor: a.point, anchorX: a.anchorX,
                             intention: mark.intention?.glyph)
        }
        // Le tracé en cours porte déjà son numéro : c'est pendant le geste que
        // l'utilisateur le prononce, pas après.
        if let stroke = live, stroke.displayID == displayID,
           let shape = MarkGeometry.shape(for: stroke.tool, from: stroke.start,
                                          to: stroke.current, in: size) {
            let a = MarkGeometry.badgeAnchor(for: shape, in: size)
            specs.append(BadgeSpec(number: stroke.number, anchor: a.point,
                                   anchorX: a.anchorX, intention: nil))
        }
        return specs
    }

    // MARK: - Diagnostic

    var count: Int { marks.count }

    /// Applications concernées par les marques en cours, dans l'ordre d'apparition.
    var targets: [String] {
        var seen: [String] = []
        for name in marks.compactMap(\.target) where !seen.contains(name) { seen.append(name) }
        return seen
    }

    func describe() -> [String] {
        guard !marks.isEmpty else { return ["aucune marque"] }
        return marks.map { m in
            let b = m.shape.boundingBox
            // L'origine n'est nommée que lorsqu'elle est un REPLI : la mentionner à
            // chaque ligne noierait le cas qui compte dans le cas courant.
            let repli = m.timeOrigin == .fallbackNow ? " ⚠ repli" : ""
            return String(format: "%d · %@ · %@%@ sur %@ (display %u) — bbox (%.3f, %.3f) %.3f×%.3f",
                          m.number, m.tool.label, m.t.description, repli,
                          m.target ?? "?", m.displayID, b.x, b.y, b.w, b.h)
        }
    }
}
