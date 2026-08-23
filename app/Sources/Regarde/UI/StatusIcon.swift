import AppKit

// ─────────────────────────────────────────────────────────────────────────────
// L'image de l'icône de barre de menus, construite en un seul endroit
//
// Extraite de `StatusItemController` pour une raison simple : elle doit pouvoir
// être MESURÉE sans barre de menus, sans écran et sans permission. Deux
// tentatives de correction se sont succédé sur cette icône, plausibles toutes les
// deux et fausses toutes les deux, faute d'un pixel compté.
//
// LA RÈGLE, tirée de ces deux échecs :
//
//   la couleur doit être DANS L'IMAGE, et l'image ne doit PAS être template.
//
// `contentTintColor` ne sert à rien ici. Sur un `NSStatusBarButton`, une image
// template est rendue par le SYSTÈME à la couleur de la barre de menus — noire en
// thème clair, blanche en sombre — et rien ne le lui fait lâcher. C'est le bon
// comportement pour une icône neutre ; c'en est un mauvais pour une icône qui doit
// dire « une session enregistre votre écran ».
//
// Sans teinte, en revanche, template est exactement ce qu'on veut : l'icône suit
// la barre de menus dans les deux thèmes, là où une couleur codée en dur serait
// illisible dans l'un des deux.
// ─────────────────────────────────────────────────────────────────────────────

enum StatusIcon {

    /// Construit l'image d'un état. `nil` si le symbole SF n'existe pas.
    static func image(symbole: String, teinte: NSColor?) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbole,
                                 accessibilityDescription: "Regarde") else { return nil }
        guard let teinte else {
            base.isTemplate = true
            return base
        }
        // `paletteColors` peint le glyphe : la couleur voyage AVEC l'image, et le
        // système n'a plus rien à décider.
        let config = NSImage.SymbolConfiguration(paletteColors: [teinte])
        let peinte = base.withSymbolConfiguration(config) ?? base
        peinte.isTemplate = false
        return peinte
    }
}
