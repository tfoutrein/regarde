import AppKit
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// La fenêtre cible — S22, spécification § 6.2 et § 8.1, ADR-0006
//
// Sans elle, ⌥⌘ arme PARTOUT. Un ⌥⌘-clic dans l'éditeur pour relire le code pendant la
// session poserait une marque sur l'éditeur — une marque qui n'a aucun sens dans le
// rapport, et qui a volé son clic à l'IDE au passage.
//
// Deux régimes, parce que le produit a deux modes.
//
//   SUIVI    hors session. La cible est l'application au premier plan, quelle qu'elle
//            soit, réévaluée en continu. C'est ce qui rend le mode éclair possible
//            (§ 2.1) : ⌥⌘ arme immédiatement sur ce que l'utilisateur regarde, sans
//            qu'il ait rien ouvert. Sans ce régime, le mode éclair devrait résoudre la
//            cible à la pression du modificateur, et un `mouseDown` arrivé dans
//            l'intervalle tomberait sur un rectangle pas encore publié.
//
//   FIGÉ     en session explicite. La cible ne bouge plus, même si l'utilisateur passe
//            dans son éditeur : une session porte sur UNE application, et ses six
//            marques doivent parler de la même.
//
// Regarde ne s'active jamais (ADR-0004, panneaux non activables, raccourcis Carbon),
// donc `frontmostApplication` désigne toujours l'application testée et non la nôtre —
// c'est ce qui rend la résolution fiable sans demander à l'utilisateur de désigner quoi
// que ce soit.
//
// Le cadre, lui, est SUIVI : une fenêtre qu'on déplace ou qu'on redimensionne pendant la
// session reste la cible. Le suivi se fait par sondage hors du chemin critique ; le tap
// ne lit qu'un rectangle atomique.
//
// `CGWindowListCopyWindowInfo` plutôt que ScreenCaptureKit pour ce suivi : la géométrie
// y est disponible sans permission ni `await`, et le sondage tourne toutes les 250 ms.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class TargetWindow {
    static let shared = TargetWindow()

    struct Target {
        let pid: pid_t
        let bundleID: String?
        let name: String
        /// Cadre en espace ÉVÉNEMENT (origine en haut à gauche), comme
        /// `CGEvent.location` — pas en coordonnées Cocoa. Les deux se ressemblent assez
        /// pour qu'une confusion passe les tests sur un écran unique et se voie
        /// seulement sur un second écran placé au-dessus.
        var frame: CGRect
    }

    private(set) var target: Target?
    private var poll: Timer?

    /// Vrai quand la cible est figée par une session ouverte.
    private(set) var isPinned = false

    /// Cadence de sondage. En session, une fenêtre qu'on déplace doit être rattrapée
    /// vite ; hors session, personne ne trace, et sonder quatre fois par seconde en
    /// permanence coûterait sans rien apporter.
    private var interval: TimeInterval { isPinned ? 0.25 : 0.6 }

    /// Démarre le suivi continu. Appelé une fois au lancement.
    ///
    /// Le mode éclair en dépend entièrement : il n'a pas de moment d'ouverture où fixer
    /// une cible, donc elle doit être prête en permanence.
    func follow() {
        isPinned = false
        observeActivation()
        refreshTarget()
        startPolling()
    }

    /// Fixe la cible sur l'application au premier plan. Appelé à l'ouverture de session.
    /// `announcing: false` laisse l'appelant journaliser lui-même.
    ///
    /// L'ouverture d'une session veut sa démarcation AVANT la ligne de cible, et le nom
    /// de la cible n'est connu qu'ici : c'est donc à l'appelant d'ordonner les deux.
    @discardableResult
    func acquire(announcing: Bool = true) -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            Journal.warn(.target, "aucune application au premier plan")
            return nil
        }

        let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        guard let frame = Self.frontWindowFrame(pid: app.processIdentifier) else {
            // Une application sans fenêtre listable — agent de menus, application en
            // cours de lancement. Refuser est plus honnête que d'armer partout : le
            // rapport dirait « cible X » alors que les marques viendraient d'ailleurs.
            Journal.warn(.target, "\(name) n'a aucune fenêtre exploitable")
            return nil
        }

        let t = Target(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                       name: name, frame: frame)
        target = t
        isPinned = true
        publish(frame)
        OptionGate.shared.setTargetFrontmost(true)
        observeActivation()
        if announcing {
            Journal.event(.target, String(format: "figée sur %@ — (%.0f, %.0f) %.0f×%.0f",
                                          name, frame.minX, frame.minY,
                                          frame.width, frame.height))
        }
        announce(name)
        startPolling()
        return t
    }

    /// Réévalue la cible d'après l'application au premier plan. Suivi seulement.
    private func refreshTarget() {
        guard !isPinned else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let frame = Self.frontWindowFrame(pid: app.processIdentifier)
        else {
            // Rien d'annotable : la porte ne doit armer nulle part. Un rectangle vide est
            // plus honnête qu'un rectangle infini, qui laisserait poser une marque sur un
            // bureau dont le rapport ne pourrait rien dire.
            target = nil
            announce(nil)
            OptionGate.shared.setTargetRect(.null)
            OptionGate.shared.setTargetFrontmost(false)
            return
        }

        let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        if target?.pid != app.processIdentifier {
            Journal.event(.target, "suivie — \(name)")
            announce(name)
        }
        target = Target(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                        name: name, frame: frame)
        publish(frame)
        OptionGate.shared.setTargetFrontmost(true)
    }

    /// Libère la cible figée et reprend le suivi.
    ///
    /// Reprendre le suivi et non revenir à `.infinite` : hors session, le mode éclair
    /// reste actif, et ⌥⌘ doit continuer d'armer sur la fenêtre regardée — mais
    /// seulement sur elle.
    func release() {
        isPinned = false
        Journal.event(.target, "dégelée, retour au suivi")
        refreshTarget()
        startPolling()
    }

    /// Fait connaître la cible au HUD.
    private func announce(_ name: String?) {
        NotificationCenter.default.post(name: .sessionTargetChanged, object: name)
    }

    // MARK: - Application active

    private var activationObserver: NSObjectProtocol?

    /// Suit l'application active pour savoir si les touches de contrôle nous reviennent.
    ///
    /// La lecture se fait ICI, sur le thread principal, et se résume à un booléen
    /// atomique côté tap : `NSWorkspace` est du AppKit, interdit dans le callback (§ 6.2).
    private func observeActivation() {
        if let token = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Une réévaluation immédiate, sans attendre le prochain tour de sondage :
            // basculer d'application est exactement le moment où la cible doit suivre.
            // L'état est RELU, la notification n'est pas lue : `Notification` n'est pas
            // `Sendable`, et Swift 6 refuse de la faire traverser vers l'acteur
            // principal. Relire `frontmostApplication` donne la même information, à jour
            // par construction — c'est déjà la correction retenue en S18.
            MainActor.assumeIsolated {
                guard let self, let t = self.target else { return }
                guard self.isPinned else { self.refreshTarget(); return }
                let app = NSWorkspace.shared.frontmostApplication
                let isTarget = app?.processIdentifier == t.pid
                OptionGate.shared.setTargetFrontmost(isTarget)
                Journal.event(.focus, "\(app?.localizedName ?? "?")"
                              + (isTarget ? " — la cible" : " — les touches lui reviennent"))
            }
        }
    }

    // MARK: - Suivi

    private func startPolling() {
        poll?.invalidate()
        // Le sondage reste quatre ordres de grandeur sous le budget du callback, qu'il ne
        // touche de toute façon pas — il n'écrit qu'un rectangle atomique.
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func refresh() {
        guard isPinned else { refreshTarget(); return }
        guard var t = target else { return }
        guard let frame = Self.frontWindowFrame(pid: t.pid) else {
            // La fenêtre a disparu — application quittée, fenêtre fermée. On garde le
            // dernier cadre connu plutôt que d'ouvrir la porte à tout l'écran.
            return
        }
        guard frame != t.frame else { return }
        t.frame = frame
        target = t
        publish(frame)
        OptionGate.shared.setTargetFrontmost(true)
        observeActivation()
    }

    private func publish(_ frame: CGRect) {
        // Marge de tolérance : viser le bord d'une fenêtre à un pixel près est un geste
        // que personne ne réussit, et un clic à deux pixels dehors ne serait pas armé
        // alors que l'intention est évidente.
        OptionGate.shared.setTargetRect(frame.insetBy(dx: -Self.slack, dy: -Self.slack))
    }

    private static let slack: CGFloat = 6

    /// Cadre de la fenêtre la plus en avant d'un processus, barres accolées comprises.
    ///
    /// `CGWindowListCopyWindowInfo` renvoie les fenêtres de l'avant vers l'arrière, mais
    /// prendre la première ne suffit pas : **plusieurs applications découpent leur
    /// fenêtre en morceaux**, et le morceau listé en tête est souvent une barre.
    ///
    /// Warp expose une barre d'onglets de 3440×44 puis la vraie fenêtre de 3440×1440
    /// juste en dessous ; Chrome en plein écran fait de même avec trois barres. Retenir la
    /// première donnait une cible de 44 pixels de haut : ⌥⌘ n'armait que dans cette bande,
    /// et tracer dans le terminal ne faisait rien — sans le moindre message, puisque du
    /// point de vue du code la cible existait.
    ///
    /// On part donc de la fenêtre de tête et on lui agrège celles qui la TOUCHENT. Deux
    /// morceaux accolés d'une même fenêtre se rejoignent ; une seconde fenêtre posée
    /// ailleurs sur l'écran, non — ce qui préserve le sens de « la fenêtre du dessus ».
    static func frontWindowFrame(pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        // `layer == 0` écarte les panneaux flottants et les infobulles, dont le cadre
        // ferait rétrécir la cible à leur taille.
        var pieces: [CGRect] = []
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            guard rect.width > 40, rect.height > 40 else { continue }
            pieces.append(rect)
        }
        return merge(pieces)
    }

    /// Agrège les morceaux qui touchent le premier, de proche en proche.
    ///
    /// Séparée de la lecture système pour être vérifiable : c'est de la géométrie, et
    /// c'est là qu'était le défaut.
    static func merge(_ pieces: [CGRect]) -> CGRect? {
        guard var frame = pieces.first else { return nil }

        // Répété, parce qu'une barre peut en toucher une autre qui touche la fenêtre —
        // les trois barres de Chrome en plein écran.
        var remaining = Array(pieces.dropFirst())
        var merged = true
        while merged {
            merged = false
            for (i, piece) in remaining.enumerated()
            where piece.insetBy(dx: -contactSlack, dy: -contactSlack).intersects(frame) {
                frame = frame.union(piece)
                remaining.remove(at: i)
                merged = true
                break
            }
        }
        return frame
    }

    /// Tolérance de contact entre deux morceaux d'une même fenêtre. Assez pour absorber
    /// un liseré d'un pixel entre une barre et son contenu, trop peu pour rejoindre une
    /// fenêtre voisine.
    static let contactSlack: CGFloat = 2
}
