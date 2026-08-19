import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// T0.5 — Une NSPanel par NSScreen, § 6.1 a la lettre
//
// Jamais une fenetre couvrant l'union des ecrans : `backingScaleFactor` est une
// propriete de fenetre, l'union de deux ecrans n'est pas un rectangle en disposition
// L, et les echelles changent a chaud quand on branche un ecran.
//
// Trois proprietes sont des pieges documentes :
//
//   styleMask          fixe a l'init, JAMAIS mute ensuite : muter styleMask sur une
//                      fenetre visible reconstruit son backing store et fait clignoter
//                      le calque.
//   canBecomeKey       mecanisme DISTINCT de .nonactivatingPanel. Sans la surcharge,
//                      un clic peut encore rendre le panneau key et envoyer resignKey
//                      a l'application testee — popovers fermes, animations en pause,
//                      blur cote page web. C'est exactement la regression que le
//                      produit promet d'eviter.
//   hidesOnDeactivate  doit valoir false, sinon le calque ne s'affiche JAMAIS :
//                      l'application n'est jamais active, donc le panneau est
//                      perpetuellement masque.
// ─────────────────────────────────────────────────────────────────────────────

final class OverlayPanel: NSPanel {

    /// Identifiant de l'ecran porteur, conserve pour retrouver le panneau apres une
    /// reconfiguration d'ecrans.
    let displayID: CGDirectDisplayID

    let inkView: InkView

    init(screen: NSScreen) {
        self.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
        self.inkView = InkView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            // Fixe ici, definitivement.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // `.screenSaver` passe au-dessus des applications en plein ecran natif, ce qui
        // est le critere C8.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
                              .ignoresCycle, .transient]

        // En permanence a `true`. Ce reglage est COSMETIQUE, jamais decisionnel :
        // c'est le tap qui arbitre (ADR-0005). Le basculer au rythme de `flagsChanged`
        // etait l'option ecartee, parce qu'un mouseDown peut tomber dans l'intervalle.
        ignoresMouseEvents = true

        // Ceinture et bretelles, sans jamais y compter : `sharingType = .none` est
        // ignore par ScreenCaptureKit depuis macOS 15.4. L'exclusion reelle passera
        // par SCContentFilter(display:excludingApplications:) au lot 3.
        sharingType = .none

        contentView = inkView
        inkView.wantsLayer = true
        inkView.layer?.isOpaque = false
        inkView.layer?.backgroundColor = NSColor.clear.cgColor

        setFrame(screen.frame, display: false)
    }

    /// La surcharge qui compte. `false` ici est ce qui rend le panneau structurellement
    /// incapable de voler le focus clavier a l'application testee — critere C4.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// Affiche sans jamais activer l'application. `orderFront(_:)` ordinaire peut
    /// activer ; `orderFrontRegardless()` ne le fait pas.
    func show() {
        guard !isVisible else { return }
        orderFrontRegardless()
    }

    func hide() {
        guard isVisible else { return }
        orderOut(nil)
    }

    /// Repositionne le panneau apres un changement de disposition des ecrans.
    func realign(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
        inkView.frame = CGRect(origin: .zero, size: screen.frame.size)
        inkView.layoutLayers()
    }
}
