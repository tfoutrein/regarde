import AppKit
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Le dernier mètre — S54, spécification § 9.10
//
// Trois corrections que la conception initiale n'avait pas, et qui font la
// différence entre un outil poli et un outil qu'on désinstalle :
//
//   LA SAUVEGARDE, item par item et TYPE par type. Écraser sans prévenir le
//   presse-papiers d'un développeur est un comportement qu'aucun outil de
//   développement ne se permet. Et une restauration naïve — le premier type
//   venu — perd les variantes riches : un extrait de page copié porte RTF,
//   HTML, texte ET l'URL source ; ne restaurer que le texte, c'est rendre un
//   presse-papiers appauvri en silence. On garde TOUT, on rend TOUT, et
//   l'inventaire des types vus face aux types restaurés est PUBLIÉ, tout écart
//   nommé — un type promis dont le fournisseur a disparu ne se restaure pas,
//   et le journal doit le dire plutôt que le taire.
//
//   L'HISTORIQUE des trois derniers feedbacks dans la barre de menus : la
//   perte du presse-papiers devient rattrapable d'un clic.
//
//   LE PORTEUR DU ⏎ — dans PressePapiers+Retour.swift.
// ─────────────────────────────────────────────────────────────────────────────

enum PressePapiers {

    private static let log = Logger(subsystem: logSubsystem, category: "papiers")

    /// Une photographie complète : chaque item, chacun de ses types, ses octets.
    struct Sauvegarde {
        var items: [[NSPasteboard.PasteboardType: Data]]
        /// Les types VUS, item par item — y compris ceux dont les octets n'ont
        /// pas pu être lus : c'est la moitié « vus » de l'inventaire.
        var typesVus: [[String]]
        var changeCount: Int
    }

    /// Photographie le tableau. Un type promis dont `data(forType:)` rend nil
    /// est retenu dans `typesVus` mais absent des octets — l'écart se verra à
    /// l'inventaire, nommé.
    static func sauvegarder(depuis tableau: NSPasteboard = .general) -> Sauvegarde {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        var vus: [[String]] = []
        for item in tableau.pasteboardItems ?? [] {
            var octets: [NSPasteboard.PasteboardType: Data] = [:]
            vus.append(item.types.map(\.rawValue))
            for type in item.types {
                if let data = item.data(forType: type) { octets[type] = data }
            }
            items.append(octets)
        }
        return Sauvegarde(items: items, typesVus: vus, changeCount: tableau.changeCount)
    }

    /// Restaure la photographie, item par item, et rend les types RESTAURÉS —
    /// l'autre moitié de l'inventaire.
    @discardableResult
    static func restaurer(_ sauvegarde: Sauvegarde,
                          vers tableau: NSPasteboard = .general) -> [[String]] {
        tableau.clearContents()
        var restaures: [[String]] = []
        var nouveaux: [NSPasteboardItem] = []
        for octets in sauvegarde.items {
            let item = NSPasteboardItem()
            for (type, data) in octets { item.setData(data, forType: type) }
            nouveaux.append(item)
            restaures.append(octets.keys.map(\.rawValue).sorted())
        }
        tableau.writeObjects(nouveaux)
        return restaures
    }

    /// L'inventaire : ce qui a été vu contre ce qui a été rendu, écart par
    /// écart. Fonction PURE — c'est elle que l'autotest juge sur les cas
    /// d'écart, sans dépendre d'un fournisseur de presse-papiers capricieux.
    static func inventaire(vus: [[String]], restaures: [[String]]) -> [String] {
        var ecarts: [String] = []
        for (i, typesVus) in vus.enumerated() {
            let rendus = Set(i < restaures.count ? restaures[i] : [])
            for type in typesVus where !rendus.contains(type) {
                ecarts.append("item \(i + 1) : « \(type) » vu mais non restauré")
            }
        }
        if restaures.count < vus.count {
            ecarts.append("\(vus.count - restaures.count) item(s) entier(s) perdus")
        }
        return ecarts
    }

    // MARK: - Le dépôt de la phrase, avec retour à 60 s

    /// Sur le MainActor : le dépôt et la restauration y vivent tous deux —
    /// c'est l'isolation, pas un verrou, qui garde cet état.
    @MainActor private static var enAttente: (sauvegarde: Sauvegarde, notreCompte: Int)?

    /// Dépose la phrase après avoir photographié l'existant. À l'échéance, si le
    /// tableau porte ENCORE notre phrase, l'existant est restauré — s'il a été
    /// réécrit entre-temps, on ne touche plus à rien : écraser le NOUVEAU
    /// contenu de l'utilisateur pour restaurer l'ancien serait le bug inverse.
    @MainActor
    static func deposerPhrase(_ phrase: String, restaurationApres delai: TimeInterval = 60,
                              tableau: NSPasteboard = .general) {
        let sauvegarde = sauvegarder(depuis: tableau)
        tableau.clearContents()
        tableau.setString(phrase, forType: .string)
        enAttente = (sauvegarde, tableau.changeCount)

        DispatchQueue.main.asyncAfter(deadline: .now() + delai) {
            guard let (sauvegarde, compte) = enAttente else { return }
            enAttente = nil
            guard tableau.changeCount == compte else {
                Journal.event(.system, "presse-papiers réécrit entre-temps — restauration abandonnée")
                return
            }
            let restaures = restaurer(sauvegarde, vers: tableau)
            let ecarts = inventaire(vus: sauvegarde.typesVus, restaures: restaures)
            var lignes: [(String, String)] = [
                ("items restaurés", "\(restaures.count)"),
                ("types vus", "\(sauvegarde.typesVus.map(\.count).reduce(0, +))"),
                ("types restaurés", "\(restaures.map(\.count).reduce(0, +))"),
            ]
            lignes += ecarts.map { ("⚠ écart", $0) }
            Journal.block("PRESSE-PAPIERS RESTAURÉ", lignes)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// L'historique des trois derniers feedbacks — § 9.10, correction 2
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class HistoriqueFeedbacks {
    static let shared = HistoriqueFeedbacks()

    struct Entree {
        let numero: Int
        let projet: String
        let phrase: String
        let date: Date
    }

    private(set) var entrees: [Entree] = []
    /// L'élément de menu que la barre affiche — reconstruit à chaque ajout.
    let menuItem = NSMenuItem(title: "Feedbacks récents", action: nil, keyEquivalent: "")

    private init() { reconstruire() }

    func ajouter(numero: Int, projet: String, phrase: String) {
        entrees.insert(Entree(numero: numero, projet: projet, phrase: phrase, date: Date()),
                       at: 0)
        if entrees.count > 3 { entrees.removeLast() }   // les TROIS derniers, § 9.10
        reconstruire()
    }

    private func reconstruire() {
        let sous = NSMenu()
        sous.autoenablesItems = false
        if entrees.isEmpty {
            let vide = NSMenuItem(title: "aucun pour l'instant", action: nil, keyEquivalent: "")
            vide.isEnabled = false
            sous.addItem(vide)
        }
        for e in entrees {
            let nom = (e.projet as NSString).lastPathComponent
            let item = NSMenuItem(title: "#\(e.numero) — \(nom) — copier la phrase",
                                  action: #selector(copier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.phrase
            sous.addItem(item)

            // Le verdict du diff (S55) se pose ICI, là où le feedback vit déjà :
            // un sous-menu par entrée, trois issues, persistées dans metrics.
            let verdicts = NSMenu()
            for (titre, code) in [("diff pertinent", "pertinent"),
                                  ("il a fallu réexpliquer", "a-reexpliquer"),
                                  ("non utilisé", "non-utilise")] {
                let v = NSMenuItem(title: titre, action: #selector(verdict(_:)), keyEquivalent: "")
                v.target = self
                v.representedObject = ["numero": e.numero, "verdict": code] as [String: Any]
                verdicts.addItem(v)
            }
            let porteVerdict = NSMenuItem(title: "   verdict du #\(e.numero)…",
                                          action: nil, keyEquivalent: "")
            porteVerdict.submenu = verdicts
            sous.addItem(porteVerdict)
        }
        menuItem.submenu = sous
    }

    @objc private func copier(_ sender: NSMenuItem) {
        guard let phrase = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phrase, forType: .string)
        Journal.event(.system, "phrase recopiée depuis l'historique")
    }

    @objc private func verdict(_ sender: NSMenuItem) {
        guard let infos = sender.representedObject as? [String: Any],
              let numero = infos["numero"] as? Int,
              let verdict = infos["verdict"] as? String else { return }
        Metriques.enregistrer(["event": "verdict", "number": numero, "verdict": verdict])
        Journal.event(.system, "verdict persisté — #\(numero) : \(verdict)")
    }
}
