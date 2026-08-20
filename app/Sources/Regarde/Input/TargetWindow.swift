import AppKit
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// La fenêtre cible — S22, spécification § 6.2 et § 8.1, ADR-0006
//
// Sans elle, ⌥⌘ arme PARTOUT. Un ⌥⌘-clic dans l'éditeur pour relire le code pendant la
// session poserait une marque sur l'éditeur — une marque qui n'a aucun sens dans le
// rapport, et qui a volé son clic à l'IDE au passage.
//
// La cible est fixée à l'ouverture de session : l'application au premier plan à cet
// instant. Regarde ne s'active jamais (ADR-0004, panneaux non activables, raccourcis
// Carbon), donc `frontmostApplication` désigne toujours l'application testée et non la
// nôtre — c'est ce qui rend la résolution fiable sans demander à l'utilisateur de
// désigner quoi que ce soit.
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

    /// Fixe la cible sur l'application au premier plan. Appelé à l'ouverture de session.
    @discardableResult
    func acquire() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            Journal.write("cible : aucune application au premier plan")
            return nil
        }

        let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        guard let frame = Self.frontWindowFrame(pid: app.processIdentifier) else {
            // Une application sans fenêtre listable — agent de menus, application en
            // cours de lancement. Refuser est plus honnête que d'armer partout : le
            // rapport dirait « cible X » alors que les marques viendraient d'ailleurs.
            Journal.write("cible : \(name) n'a aucune fenêtre exploitable")
            return nil
        }

        let t = Target(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                       name: name, frame: frame)
        target = t
        publish(frame)
        OptionGate.shared.setTargetFrontmost(true)
        observeActivation()
        Journal.write(String(format: "cible : %@ — cadre (%.0f, %.0f) %.0f×%.0f",
                             name, frame.minX, frame.minY, frame.width, frame.height))
        startPolling()
        return t
    }

    func release() {
        poll?.invalidate()
        poll = nil
        if let token = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            activationObserver = nil
        }
        OptionGate.shared.setTargetFrontmost(false)
        target = nil
        // `.infinite` remet l'arbitrage en veille : hors session, la porte ne doit rien
        // retenir, et un rectangle nul ferait taire le tap sans que rien ne le dise.
        OptionGate.shared.setTargetRect(.infinite)
        Journal.write("cible : relâchée")
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
            // L'état est RELU, la notification n'est pas lue : `Notification` n'est pas
            // `Sendable`, et Swift 6 refuse de la faire traverser vers l'acteur
            // principal. Relire `frontmostApplication` donne la même information, à jour
            // par construction — c'est déjà la correction retenue en S18.
            MainActor.assumeIsolated {
                guard let self, let t = self.target else { return }
                let app = NSWorkspace.shared.frontmostApplication
                let isTarget = app?.processIdentifier == t.pid
                OptionGate.shared.setTargetFrontmost(isTarget)
                Journal.write("application active : \(app?.localizedName ?? "?")"
                              + (isTarget ? " — la cible" : " — les touches lui reviennent"))
            }
        }
    }

    // MARK: - Suivi

    private func startPolling() {
        poll?.invalidate()
        // 250 ms : une fenêtre qu'on déplace se rattrape en un quart de seconde, et le
        // sondage reste quatre ordres de grandeur sous le budget du callback, qu'il ne
        // touche de toute façon pas — il n'écrit qu'un rectangle atomique.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func refresh() {
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

    /// Cadre de la fenêtre la plus en avant d'un processus.
    ///
    /// `CGWindowListCopyWindowInfo` renvoie les fenêtres de l'avant vers l'arrière : la
    /// première du bon pid est celle que l'utilisateur regarde.
    static func frontWindowFrame(pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            // `layer == 0` écarte les panneaux flottants et les infobulles, dont le
            // cadre est minuscule et ferait rétrécir la cible à leur taille.
            guard rect.width > 40, rect.height > 40 else { continue }
            return rect
        }
        return nil
    }
}
