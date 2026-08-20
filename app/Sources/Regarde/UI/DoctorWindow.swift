import AppKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Fenêtre de diagnostic — S12
//
// C'est la seule fenêtre que l'application ouvre, et le raccourci qui l'appelle (S10)
// fonctionne AVANT que toute permission soit accordée — c'est même sa raison d'être.
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
