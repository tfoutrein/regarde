import AppKit
import os
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'element de barre de menus — critere de fin de S9
//
// Son icone porte l'etat REEL de la session. Le lot 0 a montre qu'un indicateur qui
// ment coute plus cher que pas d'indicateur : c'est souvent la seule chose visible
// quand l'application est lancee normalement, sans terminal ou lire quoi que ce soit.
//
// Symboles SF plutot qu'un glyphe texte : un caractere absent de la police rendrait
// l'element large de zero pixel, donc invisible — panne silencieuse d'un indicateur
// dont le role est justement de ne pas mentir.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class StatusItemController {
    static let shared = StatusItemController()

    private let log = Logger(subsystem: logSubsystem, category: "statusitem")
    private var item: NSStatusItem?
    private let stateItem = NSMenuItem(title: "…", action: nil, keyEquivalent: "")
    private var geometryLogged = false

    func setUp() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item

        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        add(to: menu, "Diagnostic…", key: "d") { DoctorWindow.shared.show() }
        add(to: menu, "Rafraîchir l'autorisation d'écran", key: "") {
            TCCContact.shared.refresh(trigger: .settings)
        }
        menu.addItem(.separator())
        add(to: menu, "Simuler le cycle d'une session", key: "") {
            SessionCoordinator.shared.runStateDemo()
        }
        add(to: menu, "Afficher / masquer le HUD", key: "") {
            HUDWindow.shared.toggleForced()
        }
        add(to: menu, "Épingler / libérer le calque", key: "o") {
            if OverlayController.shared.isShowing {
                OverlayController.shared.hidePanels()
            } else {
                OverlayController.shared.showPanels()
                OverlayController.shared.redrawAll()
            }
        }
        add(to: menu, "Effacer les marques", key: "k") {
            MarkStore.shared.clear()
            OverlayController.shared.redrawAll()
        }
        add(to: menu, "Lister les marques", key: "") {
            Journal.section("Marques", MarkStore.shared.describe())
        }
        add(to: menu, "Vérifier les panneaux", key: "") {
            Journal.section("Panneaux — vérification", OverlayController.shared.audit())
        }
        add(to: menu, "Rejouer une reconstruction de panneaux", key: "") {
            // Exerce le chemin de reconstruction sans débrancher d'écran. Ne remplace
            // pas le test physique — un vrai débranchement change aussi la disposition —
            // mais attrape les régressions du réalignement et du nettoyage.
            OverlayController.shared.rebuildPanels(reason: "reconstruction manuelle")
            Journal.section("Panneaux — après reconstruction", OverlayController.shared.audit())
        }
        menu.addItem(.separator())
        add(to: menu, "Quitter Regarde", key: "q") { NSApp.terminate(nil) }

        item.menu = menu

        SessionCoordinator.shared.onStateChanged = { [weak self] state in
            self?.render(state)
        }
        render(SessionCoordinator.shared.state)

        // La géométrie n'est établie qu'après un tour de boucle : mesurée dans `setUp`,
        // la fenêtre de l'élément rapporte une hauteur nulle. Un diagnostic prématuré
        // est un diagnostic qui ment — c'est ce que tout ce lot cherche à éviter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.reportGeometry(trigger: "démarrage") }
        }

        // L'élément migre d'un écran à l'autre avec la barre de menus active. Une mesure
        // prise une seule fois au démarrage devient fausse dès qu'un écran est débranché,
        // et c'est précisément le moment où l'utilisateur a besoin de savoir où il est.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated {
                        StatusItemController.shared.reportGeometry(trigger: "changement d'écrans")
                    }
                }
            }
        }
    }

    /// Publie la géométrie réelle de l'élément.
    ///
    /// Sur un portable à encoche dont la barre est saturée, le système peut placer un
    /// élément hors de portée : il existe, l'accessibilité le voit, et l'utilisateur ne
    /// le trouve pas. Ce cas doit se diagnostiquer, pas se deviner.
    /// Vrai quand l'utilisateur ne peut pas atteindre l'icône, quoi qu'en dise le système.
    private(set) var isUnreachable = false

    private func reportGeometry(trigger: String) {
        guard let button = item?.button else {
            Journal.write("⚠ élément de barre de menus : aucun bouton")
            return
        }
        let visible = item?.isVisible ?? false
        var lines: [String] = ["raison     \(trigger)",
                               "visible    \(visible)",
                               "image      \(button.image != nil ? "construite" : "ABSENTE")"]
        var unreachable = false
        if let frame = button.window?.frame {
            lines.append(String(format: "position   x=%.0f y=%.0f", frame.minX, frame.minY))
            lines.append(String(format: "taille     %.0f × %.0f", frame.width, frame.height))
            if frame.width < 1 || frame.height < 1 {
                lines.append("⚠ dimension nulle — l'élément ne sera pas visible")
                unreachable = true
            }
        }
        if let screen = button.window?.screen {
            lines.append("écran      \(Int(screen.frame.width))×\(Int(screen.frame.height)) pt à (\(Int(screen.frame.minX)), \(Int(screen.frame.minY)))")

            // Sur un portable à encoche, `isVisible` reste vrai alors que l'élément est
            // physiquement masqué : le système le place entre les deux zones utilisables
            // de la barre. L'utilisateur ne le trouve pas et rien ne le lui dit.
            if let frame = button.window?.frame,
               let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea {
                let notch = CGRect(x: left.maxX, y: left.minY,
                                   width: right.minX - left.maxX, height: left.height)
                lines.append(String(format: "encoche    x %.0f à %.0f", notch.minX, notch.maxX))
                if notch.intersects(frame) {
                    lines.append("⚠ L'ÉLÉMENT EST SOUS L'ENCOCHE — invisible malgré isVisible=true.")
                    lines.append("  Libère de la place dans la barre de menus, ou retire une icône.")
                    unreachable = true
                }
            }
        }
        if unreachable {
            lines.append("→ ⌃⌥S reste le chemin d'accès garanti : les raccourcis Carbon ne")
            lines.append("  dépendent ni de la barre de menus ni d'aucune autorisation.")
        }
        Journal.section("Barre de menus", lines)

        // Prévenir par un canal qui ne dépend PAS de la barre de menus, puisque c'est
        // elle qui fait défaut. Le HUD est un panneau flottant : il s'affiche même quand
        // l'icône est introuvable, et c'est le seul moyen de dire à l'utilisateur que
        // l'application tourne toujours et comment l'atteindre.
        if unreachable && !isUnreachable {
            HUDWindow.shared.announce(
                "Icône introuvable dans la barre de menus",
                detail: "⌃⌥S ouvre le diagnostic"
            )
        }
        isUnreachable = unreachable
    }

    private func render(_ state: SessionState) {
        guard let button = item?.button else { return }

        let (symbol, description, tint): (String, String, NSColor?) = switch state.indicator {
        case .ready:     ("circle",                 "prêt",                  nil)
        case .active:    ("record.circle",          "session en cours",      .systemRed)
        case .working:   ("circle.dotted",          "traitement",            .systemOrange)
        case .suspended: ("circle.slash",           "suspendu par le système", .systemGray)
        case .fault:     ("exclamationmark.circle", "permission manquante",  .systemRed)
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Regarde — \(description)")
        if image == nil {
            // Un symbole absent rendrait l'élément large de zéro pixel : invisible, alors
            // que son unique raison d'être est de ne pas mentir sur l'état. On bascule sur
            // du texte plutôt que de disparaître en silence.
            log.error("symbole SF « \(symbol, privacy: .public) » introuvable — repli sur le texte")
        }
        button.image = image
        button.image?.isTemplate = (tint == nil)
        button.title = image == nil ? "◉" : ""
        button.contentTintColor = tint
        button.toolTip = "Regarde — \(description)"

        stateItem.title = SessionCoordinator.shared.blockingReason
            ?? "état : \(state.rawValue) — \(description)"
    }

    private func add(to menu: NSMenu, _ title: String, key: String, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: key)
        let box = MenuAction(action)
        item.target = box
        item.representedObject = box   // `target` est faible : sans cette prise, l'action meurt
        menu.addItem(item)
    }
}

/// `NSMenuItem` exige une cible Objective-C ; une fermeture Swift n'en est pas une.
private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}
