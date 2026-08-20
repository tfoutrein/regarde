import AppKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// HUD de session — S15, version minimale
//
// Il portera au lot 2 le projet cible, le compteur de marques et le sens actif de
// ⌥⌘ + chiffre. Ici il ne montre que l'état de session, mais il le montre avec les
// contraintes définitives — celles-là ne sont pas négociables plus tard :
//
//   • `.nonactivatingPanel` et `canBecomeKey = false` : le HUD s'affiche PENDANT que
//     l'utilisateur teste son application. S'il lui volait le focus, il casserait
//     exactement ce que le produit promet de préserver.
//   • `hidesOnDeactivate = false` : sans lui, le HUD ne s'afficherait jamais, puisque
//     l'application n'est jamais active.
//   • `ignoresMouseEvents = true` : c'est un affichage, pas une cible de clic.
//   • `.statusBar` plutôt que `.screenSaver` : au-dessus des fenêtres ordinaires, mais
//     sous le calque d'annotation qui viendra au lot 2.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class HUDWindow {
    static let shared = HUDWindow()

    private var panel: NSPanel?
    private var forced = false

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],   // fixé à l'init, jamais muté
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: HUDView())
        return panel
    }

    /// Place le HUD en bas à droite de l'écran portant la souris.
    ///
    /// Pas de l'écran principal : sur deux écrans, l'utilisateur teste là où est son
    /// curseur, et un HUD sur l'autre écran ne servirait à rien.
    private func reposition(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 20,
                                     y: frame.minY + 20))
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        // `orderFrontRegardless` et non `orderFront` : ce dernier peut activer
        // l'application, ce qui volerait le focus à l'application testée.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Suit l'état de session : visible pendant qu'une session vit, masqué sinon.
    func follow(_ state: SessionState) {
        guard !forced else { return }
        switch state {
        case .arming, .recording, .finalizing, .publishing: show()
        case .idle, .preflight, .suspended, .blocked: hide()
        }
    }

    /// Affichage forcé, pour vérifier la mise en page sans ouvrir de session.
    func toggleForced() {
        forced.toggle()
        if forced { show() } else { follow(SessionCoordinator.shared.state) }
    }

    var isForced: Bool { forced }
}

private struct HUDView: View {
    @State private var state = SessionCoordinator.shared.state

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text("le lot 2 y ajoutera le projet et les marques")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 260, height: 64, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onReceive(NotificationCenter.default.publisher(for: .sessionStateChanged)) { note in
            if let s = note.object as? SessionState { state = s }
        }
    }

    private var title: String {
        switch state {
        case .idle: "Prêt"
        case .preflight: "Vérification…"
        case .arming: "Démarrage…"
        case .recording: "Session en cours"
        case .finalizing: "Traitement…"
        case .publishing: "Écriture du rapport…"
        case .suspended: "Suspendu"
        case .blocked: "Autorisation manquante"
        }
    }

    private var color: Color {
        switch state.indicator {
        case .ready: .secondary
        case .active: .red
        case .working: .orange
        case .suspended: .gray
        case .fault: .red
        }
    }
}

extension Notification.Name {
    static let sessionStateChanged = Notification.Name("dev.tfoutrein.regarde.sessionStateChanged")
}
