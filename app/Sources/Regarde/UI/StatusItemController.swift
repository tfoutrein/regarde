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

        // S54 — l'historique des trois derniers feedbacks : la perte du
        // presse-papiers devient rattrapable d'un clic (§ 9.10, correction 2).
        menu.addItem(HistoriqueFeedbacks.shared.menuItem)

        // S55 — le repli DÉCLARÉ. Le GO/NO-GO n°2 mesure « replis / besoins » ;
        // un repli non déclaré est un besoin invisible, et lot4-gonogo.sh
        // refuse de conclure si aucun n'a jamais été noté — zéro mesurerait
        // l'oubli de déclarer, pas la perfection de l'outil.
        add(to: menu, "J'ai préféré une capture manuelle", key: "") {
            Metriques.enregistrer(["event": "repli"])
            Journal.event(.system, "repli déclaré — capture manuelle préférée à une session")
            HUDWindow.shared.announce("Repli noté", detail: "compté pour le GO/NO-GO", duration: 2)
        }
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
            Journal.warn(.system, "élément de barre de menus : aucun bouton")
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
        // `screen` est nil quand la fenêtre de l'élément ne recouvre AUCUN écran.
        //
        // C'est ce que fait macOS d'un élément qu'il ne peut plus placer : il le gare
        // hors champ. `isVisible` reste vrai, l'image est construite, et l'utilisateur
        // ne trouve rien — c'est le cas le plus déroutant des trois, parce que tout ce
        // qu'on sait mesurer dit que tout va bien.
        //
        // Le diagnostic ne le voyait pas : toute son analyse — écran porteur, encoche —
        // vivait DANS un `if let screen`, donc était sautée en silence précisément
        // quand il y avait quelque chose à dire. Une section qui omet ses lignes se lit
        // comme une section qui n'a rien à signaler.
        if button.window?.screen == nil {
            let ecrans = NSScreen.screens.map {
                String(format: "%.0f→%.0f", $0.frame.minY, $0.frame.maxY)
            }.joined(separator: ", ")
            lines.append("écran      AUCUN — la fenêtre ne recouvre aucun écran")
            lines.append("           écrans en y : \(ecrans)")
            lines.append("⚠ L'ÉLÉMENT EST GARÉ HORS ÉCRAN — invisible malgré isVisible=true.")
            lines.append("  macOS fait cela quand la barre de menus est pleine : il ne peut")
            lines.append("  plus placer l'élément et le pousse hors champ.")
            lines.append("  Libère de la place — retire une icône, ou masque celles du système.")
            unreachable = true
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
                detail: "Barre pleine — libère une place. ⌃⌥S ouvre le diagnostic.",
                duration: 8
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

        // La couleur voyage DANS l'image — voir `StatusIcon`, et l'autotest
        // `--icone-test` qui compte les pixels plutôt que de raisonner dessus.
        let image = StatusIcon.image(symbole: symbol, teinte: tint)
        if image == nil {
            // Un symbole absent rendrait l'élément large de zéro pixel : invisible, alors
            // que son unique raison d'être est de ne pas mentir sur l'état. On bascule sur
            // du texte plutôt que de disparaître en silence.
            log.error("symbole SF « \(symbol, privacy: .public) » introuvable — repli sur le texte")
        }
        button.image = image
        button.title = image == nil ? "◉" : ""
        // `contentTintColor` reste NIL, et ce n'est pas un oubli.
        //
        // Deux corrections s'y sont trompées avant qu'un pixel soit compté. Elle ne
        // teinte que les images template ; et sur un `NSStatusBarButton`, une image
        // template est de toute façon repeinte par le SYSTÈME à la couleur de la
        // barre de menus, ce qui écrase toute teinte. Les deux chemins mènent au
        // noir, ce que l'auteur a constaté deux fois de suite.
        //
        // La couleur est donc DANS l'image (`StatusIcon`), et il n'y a plus rien à
        // teindre ici. `--icone-test` le mesure : 1114 pixels colorés sur 1114
        // opaques avec la palette, zéro sans elle.
        button.contentTintColor = nil
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
