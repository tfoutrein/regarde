import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La saisie texte — S69, § 7.4 (arbitrage A2, acté en S59)
//
// Sans mode silencieux, le produit se réduit à des flèches numérotées sans
// mots : inutilisable en open space, en visioconférence, ou simplement quand
// quelqu'un passe. Le texte libre est donc dans le MVP.
//
// LE POINT DUR, ET TOUT LE FICHIER EST BÂTI DESSUS : aucune fenêtre ne doit
// devenir *key*. Une fenêtre qui prend le focus envoie `resignKey` à
// l'application testée — popovers fermés, curseur figé, animations en pause,
// `blur` côté page web qui suspend les `requestAnimationFrame`. C'est très
// exactement la régression que le produit promet d'éviter, et elle serait
// pire que l'absence de la fonction.
//
// La technique du § 7.4 : le tap consomme les `keyDown`, on reconstruit un
// `NSEvent` par `NSEvent(cgEvent:)` et on le passe à un `NSTextView` HORS
// ÉCRAN via `interpretKeyEvents(_:)`. Le champ ne reçoit jamais le focus au
// sens du système ; il interprète des événements qu'on lui apporte. Bénéfice
// collatéral, et c'est le vrai argument technique : les touches mortes
// françaises (`^`, `¨`), la répétition et les raccourcis d'édition viennent
// gratuitement, parce que c'est la machine à états de Cocoa qui travaille.
//
// Les IME asiatiques ne sont pas couverts — limitation assumée du § 7.4.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SaisieTexte {
    static let shared = SaisieTexte()

    /// La fenêtre qui héberge le champ. Hors écran, sans titre, sans ombre, et
    /// surtout : elle ne peut PAS devenir clé. `canBecomeKey` répond faux, et
    /// personne ne l'ordonne jamais à l'écran.
    private final class FenetreMuette: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let fenetre: FenetreMuette
    private let champ: NSTextView

    private init() {
        // Loin hors de tout écran : même une erreur d'ordonnancement ne la
        // rendrait pas visible.
        fenetre = FenetreMuette(contentRect: NSRect(x: -10_000, y: -10_000, width: 400, height: 80),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        fenetre.isReleasedWhenClosed = false
        fenetre.ignoresMouseEvents = true
        fenetre.alphaValue = 0
        champ = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        champ.isEditable = true
        champ.isSelectable = true
        champ.isFieldEditor = false
        fenetre.contentView = champ
        // `orderBack` — jamais `makeKeyAndOrderFront`. La fenêtre existe pour
        // que le champ ait un contexte de saisie ; elle ne participe à rien
        // d'autre.
        fenetre.orderBack(nil)
        // Premier répondant de SA fenêtre — sans la rendre clé. Un champ qui
        // n'est pas premier répondant n'a pas de contexte de saisie, et
        // `interpretKeyEvents` n'a alors nulle part où poser les caractères.
        fenetre.makeFirstResponder(champ)
    }

    /// Le texte saisi jusqu'ici.
    var texte: String { champ.string }

    /// Vrai quand la saisie est en cours — l'appelant décide, ce type n'a pas
    /// d'opinion sur les modes.
    private(set) var active = false

    func commencer() {
        champ.string = ""
        champ.setSelectedRange(NSRange(location: 0, length: 0))
        // Le contexte de saisie doit être ACTIF pour qu'`interpretKeyEvents`
        // ait où poser les caractères — et `activate()` le rend courant sans
        // rendre la fenêtre clé, ce qui est exactement ce qu'il nous faut.
        champ.inputContext?.activate()
        active = true
    }

    /// Rend le texte et referme. Le champ est vidé : rien ne fuit d'une saisie
    /// à la suivante.
    @discardableResult
    func terminer() -> String {
        let resultat = champ.string
        champ.string = ""
        champ.inputContext?.deactivate()
        active = false
        return resultat
    }

    func abandonner() {
        champ.string = ""
        champ.inputContext?.deactivate()
        active = false
    }

    /// Nourrit le champ d'un événement clavier venu du tap.
    ///
    /// `NSEvent(cgEvent:)` reconstruit l'événement AppKit — avec ses
    /// `characters`, résolus par la disposition courante — et
    /// `interpretKeyEvents` fait le reste : composition des touches mortes,
    /// suppression, déplacement du curseur.
    @discardableResult
    func nourrir(_ evenement: CGEvent) -> Bool {
        guard active, let nsEvent = NSEvent(cgEvent: evenement) else { return false }
        champ.interpretKeyEvents([nsEvent])
        return true
    }

    /// Ce que la sonde a besoin de voir pour comprendre un échec.
    func diagnostic(_ evenement: CGEvent) -> String {
        guard let e = NSEvent(cgEvent: evenement) else { return "NSEvent(cgEvent:) rend nil" }
        return "type \(e.type.rawValue) · code \(e.keyCode) · caractères « \(e.characters ?? "nil") »"
            + " · premier répondant \(fenetre.firstResponder === champ ? "le champ" : String(describing: fenetre.firstResponder))"
            + " · contexte \(champ.inputContext == nil ? "ABSENT" : "présent")"
    }

    /// La fenêtre est-elle clé ? Doit TOUJOURS répondre faux — c'est le
    /// critère du § 7.4, et l'autotest le vérifie plutôt que de l'espérer.
    var fenetreEstClé: Bool { fenetre.isKeyWindow }
    var fenetrePeutDevenirClé: Bool { fenetre.canBecomeKey }
    var fenetreEstVisible: Bool { fenetre.isVisible && fenetre.alphaValue > 0 }
}
