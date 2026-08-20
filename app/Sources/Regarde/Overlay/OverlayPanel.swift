import AppKit
import QuartzCore

// ─────────────────────────────────────────────────────────────────────────────
// Un panneau d'annotation par écran — spécification § 6.1
//
// Jamais une fenêtre couvrant l'union des écrans : `backingScaleFactor` est une
// propriété PAR FENÊTRE, l'union de deux écrans n'est pas un rectangle en disposition
// L, et les échelles changent à chaud quand on branche un écran.
//
// Trois propriétés sont des pièges documentés, et le lot 0 les a validées :
//
//   styleMask          fixé à l'init, JAMAIS muté ensuite : le muter sur une fenêtre
//                      visible reconstruit son backing store et fait clignoter le calque.
//   canBecomeKey       mécanisme DISTINCT de `.nonactivatingPanel`. Sans cette
//                      surcharge, un clic peut rendre le panneau key et envoyer
//                      `resignKey` à l'application testée — popovers fermés, animations
//                      en pause, `blur` côté page web. C'est la régression exacte que le
//                      produit promet d'éviter.
//   hidesOnDeactivate  doit valoir false, sinon le calque ne s'affiche JAMAIS :
//                      l'application n'est jamais active, donc le panneau serait
//                      perpétuellement masqué.
// ─────────────────────────────────────────────────────────────────────────────

final class OverlayPanel: NSPanel {

    /// Identifiant de l'écran porteur. Sert à retrouver le panneau après une
    /// reconfiguration, plutôt que de se fier à l'ordre de `NSScreen.screens` qui change.
    let displayID: CGDirectDisplayID

    let inkView: InkView

    /// Géométrie de l'écran au moment de la dernière construction ou réalignement.
    private(set) var screenInfo: ScreenInfo

    init(screen: NSScreen, geometry: ScreenGeometry) {
        let id = Self.displayID(of: screen)
        self.displayID = id
        self.screenInfo = geometry.screens.first { $0.displayID == id }
            ?? ScreenInfo(displayID: id, cocoaFrame: screen.frame, scale: screen.backingScaleFactor)
        self.inkView = InkView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],   // fixé ici, définitivement
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
        // `.screenSaver` passe au-dessus des applications en plein écran natif — le
        // critère C8 du lot 0 — et au-dessus du HUD, qui est en `.statusBar`.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
                              .ignoresCycle, .transient]

        // En permanence à `true`. Ce réglage est COSMÉTIQUE, jamais décisionnel : c'est
        // le tap qui arbitre (ADR-0005). Le basculer au rythme de `flagsChanged` était
        // l'option écartée, parce qu'un `mouseDown` peut tomber dans l'intervalle.
        ignoresMouseEvents = true

        // Le lot 0 a montré que `sharingType = .none` fonctionne réellement sur
        // macOS 26.1 — un trait existant n'apparaissait ni dans `screencapture` ni dans
        // ScreenCaptureKit — alors que la spécification le donnait pour ignoré depuis
        // macOS 15.4. On le garde comme seconde ligne de défense sans s'y fier :
        // l'exclusion par application couvre aussi les fenêtres créées après coup.
        sharingType = TestFlags.visibleCapture ? .readOnly : .none

        contentView = inkView
        inkView.wantsLayer = true
        inkView.layer?.isOpaque = false
        inkView.layer?.backgroundColor = NSColor.clear.cgColor

        setFrame(screen.frame, display: false)
    }

    /// La surcharge qui compte. `false` rend le panneau structurellement incapable de
    /// voler le focus clavier à l'application testée — critère C4 du lot 0.
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

    /// Repositionne le panneau après un changement de disposition des écrans.
    ///
    /// Le cadre ET la géométrie sont remis à jour : un panneau dont le cadre a suivi
    /// mais pas l'échelle produirait des traits à la mauvaise densité — le décalage ×2,
    /// mais seulement après avoir rebranché un écran, donc introuvable.
    func realign(to screen: NSScreen, geometry: ScreenGeometry) {
        let id = Self.displayID(of: screen)
        screenInfo = geometry.screens.first { $0.displayID == id }
            ?? ScreenInfo(displayID: id, cocoaFrame: screen.frame, scale: screen.backingScaleFactor)
        setFrame(screen.frame, display: false)
        inkView.frame = CGRect(origin: .zero, size: screen.frame.size)
        inkView.layoutLayers()
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }
}
