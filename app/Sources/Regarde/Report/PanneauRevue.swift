import AppKit
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// Le panneau de revue — S71, § 6.6 et § 10.3
//
// Il a sa fenêtre CLÉ, comme le sélecteur de projet (S51), et pour la raison
// inverse : la session est TERMINÉE. La cible est relâchée, le calque retiré,
// l'application testée n'attend plus rien de nous — prendre le focus ne vole
// donc plus rien à personne. C'est le seul moment du produit où une fenêtre
// peut légitimement être clé.
//
// Trois choses, dans l'ordre d'usage du § 6.6 : éditer le texte, supprimer une
// marque ou un segment, vérifier les images. Et une règle : ⏎ réécrit ce qui
// est publié, ⎋ referme SANS RIEN CHANGER — une revue qu'on ouvre par
// curiosité ne doit jamais modifier un rapport.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PanneauRevue: NSPanel {

    static var partage: PanneauRevue?

    /// Une ligne éditable : soit la note écrite d'une marque, soit un segment
    /// de parole. Le champ porte son identité, pour retrouver quoi modifier.
    private struct Ligne {
        enum Genre { case note(marque: Int), segment(id: String) }
        let genre: Genre
        let titre: String
        let texte: String
    }

    private var lignes: [Ligne] = []
    private var champs: [NSTextField] = []
    private var supprimees: Set<Int> = []
    private var segmentsSupprimes: Set<String> = []

    override var canBecomeKey: Bool { true }

    static func presenter() {
        guard let etat = Revue.charger() else {
            Journal.warn(.system, "revue — rien à revoir : aucun manifeste publié")
            HUDWindow.shared.announce("Rien à revoir",
                                      detail: "aucun feedback n'a été publié", duration: 3)
            return
        }
        let panneau = partage ?? PanneauRevue(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 10),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        partage = panneau
        panneau.title = "Revue du feedback #\(etat.manifeste.session.number)"
        panneau.level = .floating
        panneau.isReleasedWhenClosed = false
        panneau.supprimees = []
        panneau.segmentsSupprimes = []
        panneau.recomposer(etat.manifeste)
        panneau.center()
        panneau.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recomposer(_ m: Manifeste.Racine) {
        lignes = []
        for marque in m.marks.sorted(by: { $0.number < $1.number }) {
            if let note = marque.text, !note.isEmpty {
                lignes.append(Ligne(genre: .note(marque: marque.number),
                                    titre: "Marque \(marque.number) — note écrite", texte: note))
            }
            for v in (marque.voice ?? []).sorted(by: { $0.onset < $1.onset }) {
                lignes.append(Ligne(genre: .segment(id: v.id),
                                    titre: "Marque \(marque.number) — \(v.id)", texte: v.text))
            }
        }
        for v in (m.session.voice ?? []).sorted(by: { $0.onset < $1.onset }) {
            lignes.append(Ligne(genre: .segment(id: v.id),
                                titre: "Commentaire général — \(v.id)", texte: v.text))
        }

        let pile = NSStackView()
        pile.orientation = .vertical
        pile.alignment = .leading
        pile.spacing = 6
        pile.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        champs = []
        if lignes.isEmpty {
            let vide = NSTextField(labelWithString: "Aucun texte à revoir — ce feedback n'a que des images.")
            vide.textColor = .secondaryLabelColor
            pile.addArrangedSubview(vide)
        }
        for ligne in lignes {
            let titre = NSTextField(labelWithString: ligne.titre)
            titre.font = .systemFont(ofSize: 10, weight: .semibold)
            titre.textColor = .secondaryLabelColor
            pile.addArrangedSubview(titre)
            let champ = NSTextField(string: ligne.texte)
            champ.font = .systemFont(ofSize: 12)
            champ.lineBreakMode = .byTruncatingTail
            champ.widthAnchor.constraint(equalToConstant: 580).isActive = true
            champs.append(champ)
            pile.addArrangedSubview(champ)
        }

        // La bande de vignettes (§ 10.3) : ce qui va partir, visible avant de
        // partir. Réutilise ce qui est déjà calculé — les PNG sont écrits.
        let crops = m.frames.filter { $0.role == "crop" }
        if !crops.isEmpty {
            let titre = NSTextField(labelWithString: "Images qui partent — \(crops.count)")
            titre.font = .systemFont(ofSize: 10, weight: .semibold)
            titre.textColor = .secondaryLabelColor
            pile.addArrangedSubview(titre)
            let bande = NSStackView()
            bande.orientation = .horizontal
            bande.spacing = 8
            for f in crops {
                guard let image = NSImage(contentsOfFile: f.absolutePath) else { continue }
                let vue = NSImageView(image: image)
                vue.imageScaling = .scaleProportionallyUpOrDown
                vue.heightAnchor.constraint(equalToConstant: 64).isActive = true
                vue.widthAnchor.constraint(equalToConstant: 96).isActive = true
                vue.toolTip = "\(f.id) — \(f.size.w)×\(f.size.h) px, \(f.visualTokens) jetons"
                bande.addArrangedSubview(vue)
            }
            pile.addArrangedSubview(bande)
        }

        let aide = NSTextField(labelWithString:
            "⏎ enregistrer et réécrire le rapport · ⎋ fermer sans rien changer · ⌫ supprimer la ligne sélectionnée")
        aide.font = .systemFont(ofSize: 10)
        aide.textColor = .tertiaryLabelColor
        pile.addArrangedSubview(aide)

        contentView = pile
        setContentSize(pile.fittingSize)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36 where !event.modifierFlags.contains(.shift):   // ⏎ — enregistrer
            enregistrer()
        case 53:                                               // ⎋ — sans rien changer
            Journal.event(.system, "revue — fermée sans modification")
            close()
        default: super.keyDown(with: event)
        }
    }

    /// Applique les éditions, puis réécrit. Les suppressions passent par le
    /// champ VIDÉ : effacer un texte retire son segment — un geste, pas un
    /// bouton de plus.
    private func enregistrer() {
        guard var etat = Revue.courant else { close(); return }
        var m = etat.manifeste
        var retires = 0, edites = 0
        for (i, ligne) in lignes.enumerated() {
            guard i < champs.count else { continue }
            let texte = champs[i].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            switch ligne.genre {
            case .note(let numero):
                if texte.isEmpty {
                    m = Revue.supprimerMarque(numero, de: m); retires += 1
                } else if texte != ligne.texte {
                    m = Revue.editerNote(numero, texte: texte, de: m); edites += 1
                }
            case .segment(let id):
                if texte.isEmpty {
                    m = Revue.supprimerSegment(id, de: m); retires += 1
                } else if texte != ligne.texte {
                    m = Revue.editerSegment(id, texte: texte, de: m); edites += 1
                }
            }
        }
        etat.manifeste = m
        Revue.courant = etat
        do {
            try Revue.republier(etat)
            HUDWindow.shared.announce("Feedback #\(m.session.number) réécrit",
                                      detail: "\(edites) texte(s) modifié(s), \(retires) retiré(s)",
                                      duration: 3)
        } catch {
            Journal.warn(.system, "revue — réécriture impossible : \(error)")
        }
        close()
    }
}
