import AppKit

// ─────────────────────────────────────────────────────────────────────────────
// Le sélecteur de projet — S51, ADR-0017
//
// Il a sa FENÊTRE CLÉ PROPRE, et c'est un choix d'architecture, pas de confort :
// le calque de session (`OverlayPanel`) est construit pour ne JAMAIS prendre le
// focus — `canBecomeKey = false`, `.nonactivatingPanel` — parce qu'il vole
// sinon `resignKey` à l'application testée (popovers fermés, animations
// interrompues). Un sélecteur qui vivrait dans le calque hériterait de cette
// interdiction et ne recevrait ni flèches ni ⏎. Il vit donc dans son propre
// `NSPanel`, qui PEUT devenir clé — s'ouvre à l'arming, se referme d'un ⏎ ou
// d'un Échap, et rend le focus d'où il vient.
//
// Il ne BLOQUE rien : la session démarre pendant qu'il est ouvert. Confirmer le
// projet est un geste de passage, pas une porte — R2 dit que la confirmation
// obligatoire se dégrade en réflexe ; celle-ci s'ignore d'un Échap et se paie en
// pastille rouge dans le rapport, pas en clic forcé.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class SelecteurProjet: NSPanel {

    static var partage: SelecteurProjet?

    /// Le choix courant, lu par la publication (S53). Nil = aucun candidat
    /// retenu — le rapport le dira plutôt que d'inventer.
    private(set) static var choix: CandidatProjet?
    private(set) static var etat: EtatProjet = .ambigu

    private var candidats: [CandidatProjet] = []
    private var selection = 0

    override var canBecomeKey: Bool { true }

    /// Présente les candidats, préselectionne le premier, et journalise —
    /// la trace écrite est ce que la recette lira.
    static func presenter(candidats: [CandidatProjet], etat: EtatProjet) {
        Self.etat = etat
        Self.choix = candidats.first

        Journal.block("PROJET", [
            ("candidats", "\(candidats.count)"),
            ("état", etat.libelle),
        ] + candidats.map { ("· \($0.chemin)", $0.motif) })

        guard !candidats.isEmpty else { return }

        let panneau = partage ?? SelecteurProjet(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
            styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false)
        partage = panneau
        panneau.title = "Projet de la session"
        panneau.level = .floating
        panneau.isReleasedWhenClosed = false
        panneau.candidats = candidats
        panneau.selection = 0
        panneau.reconstruire()
        panneau.center()
        panneau.makeKeyAndOrderFront(nil)
    }

    private func reconstruire() {
        let pile = NSStackView()
        pile.orientation = .vertical
        pile.alignment = .leading
        pile.spacing = 8
        pile.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        pile.addArrangedSubview(PastilleProjet.vue(Self.etat))
        for (i, c) in candidats.enumerated() {
            let ligne = NSTextField(labelWithString:
                "\(i == selection ? "▸" : " ") \((c.chemin as NSString).abbreviatingWithTildeInPath)")
            ligne.font = .monospacedSystemFont(ofSize: 12, weight: i == selection ? .semibold : .regular)
            ligne.toolTip = c.motif
            pile.addArrangedSubview(ligne)
            let motif = NSTextField(labelWithString: "   \(c.motif)")
            motif.font = .systemFont(ofSize: 10)
            motif.textColor = .secondaryLabelColor
            pile.addArrangedSubview(motif)
        }
        let aide = NSTextField(labelWithString: "↑↓ choisir · ⏎ confirmer · ⎋ laisser \(EtatProjet.ambigu.libelle)")
        aide.font = .systemFont(ofSize: 10)
        aide.textColor = .tertiaryLabelColor
        pile.addArrangedSubview(aide)

        contentView = pile
        setContentSize(pile.fittingSize)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: selection = max(0, selection - 1); reconstruire()          // ↑
        case 125: selection = min(candidats.count - 1, selection + 1); reconstruire() // ↓
        case 36:                                                             // ⏎
            Self.choix = candidats[selection]
            Self.etat = .certain
            Journal.event(.system, "projet confirmé — \(candidats[selection].chemin)")
            close()
        case 53:                                                             // ⎋
            Self.etat = .ambigu
            Journal.event(.system, "projet laissé ambigu — aucun candidat confirmé")
            close()
        default: super.keyDown(with: event)
        }
    }
}
