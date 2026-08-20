import AppKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Fenêtre de diagnostic — coquille posée en S9, remplie en S11 et S12.
//
// Elle existe dès maintenant pour une raison : c'est la seule fenêtre que l'application
// ouvre, et le raccourci qui l'appelle (S10) doit fonctionner AVANT que toute permission
// soit accordée. Poser sa place tôt évite d'avoir à démêler plus tard son activation de
// celle du reste de l'interface.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DoctorWindow {
    static let shared = DoctorWindow()

    private var window: NSWindow?

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Regarde — diagnostic"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: DoctorView())
        self.window = window
        bringToFront(window)
    }

    /// Cette fenêtre est la seule pour laquelle l'application s'active volontairement.
    ///
    /// La politique `.accessory` la rend incapable de passer au premier plan autrement,
    /// et c'est voulu partout ailleurs — le produit repose sur le fait de ne jamais voler
    /// le focus à l'application testée. Le diagnostic est l'exception : il est ouvert
    /// délibérément par l'utilisateur, et lui serait inutile s'il restait derrière.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct DoctorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostic")
                .font(.title2.weight(.semibold))
            Text("Le moteur du doctor arrive en S11, son interface en S12.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
