import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La fenêtre de parole — S63, ADR-0011, spécification § 3.5
//
// « Le micro suit le geste. » Il est fermé par défaut ; une FENÊTRE s'ouvre à
// la prise de ⌥⌘ et se ferme 8 s après le relâchement, prolongée tant que des
// résultats volatiles arrivent, avec un plafond dur de 20 s. Tout segment dont
// le PREMIER MOT tombe dans une fenêtre appartient à la marque de cette
// fenêtre. Le rattachement n'est pas inféré : il est déterministe par
// construction — c'est ce qui supprime l'écran de revue obligatoire, et donc
// le coût fixe que le produit prétend abolir.
//
// Cette machine est PURE : des événements horodatés entrent, des effets
// sortent, et une question — « à qui appartient ce segment ? » — se pose sans
// micro, sans moteur, sans horloge réelle. Comme `decision()` du porteur ou
// l'assembleur de S53 : tout se juge sur des événements fabriqués, avant qu'un
// seul buffer réel n'existe. Le branchement au geste (S64) ne fait que la
// nourrir ; le HUD, le journal et le calque lui obéissent, jamais l'inverse.
//
// Trois choix que l'ADR laissait ouverts, tranchés ici et vérifiés par
// l'autotest :
//   · un second tracé dans la même tenue de ⌥⌘ SCINDE la fenêtre — une fenêtre
//     porte une marque et une seule, « l'utilisateur décrit puis pointe » ;
//   · une fenêtre sans marque (tenue sans tracé) est GLOBALE : la parole de
//     l'utilisateur ne se jette jamais en silence ; le geste global EXPLICITE
//     (> 400 ms, immobile) est en plus annoncé au HUD ;
//   · la prolongation par les volatils repousse l'échéance d'une seconde après
//     le dernier — jamais au-delà du plafond.
// ─────────────────────────────────────────────────────────────────────────────

enum FenetreDeParole {

    /// Les règles chiffrées, en secondes — une seule table, celle de
    /// `lot5-seuils.md` § 1.
    struct Regles: Equatable, Sendable {
        var grace: Double = 8            // après le relâchement
        var prolongation: Double = 1     // après le dernier volatil
        var plafond: Double = 20         // dur, volatils compris
        var gesteGlobalMinimum: Double = 0.4
        static let defaut = Regles()
    }

    /// Pourquoi un segment est là où il est — les quatre règles du § 3.5.
    enum Regle: String, Codable, Sendable {
        case fenetreDeParole, debordement, gesteGlobal, aucuneFenetre
    }

    /// À qui appartient un segment.
    enum Attachement: Equatable, Sendable {
        case marque(Int, regle: Regle)
        case global(regle: Regle)
    }

    /// Ce qui entre : le geste, le moteur, l'horloge — horodatés en temps de
    /// session.
    enum Evenement: Equatable, Sendable {
        case prise(SessionTime)                       // ⌥⌘ pressé
        case mouvement(SessionTime)                   // la souris bouge sous ⌥⌘
        case trace(SessionTime, marque: Int)          // une marque vient d'être posée
        case relachement(SessionTime)                 // ⌥⌘ relâché
        case volatil(SessionTime)                     // un résultat volatile est arrivé
        case verrou(SessionTime, actif: Bool)         // ⌃⌥M
        case fermetureDOffice(SessionTime, raison: String) // saisie sécurisée, veille…
        case tic(SessionTime)                         // l'horloge — les échéances
    }

    /// Ce qui sort : ce que S64 branchera sur le micro, le calque et le HUD.
    enum Effet: Equatable, Sendable {
        case ouverture(SessionTime)
        case fermeture(Fenetre)
        case commentaireGeneral                       // HUD « commentaire général »
    }

    /// Une fenêtre, ouverte ou close. Close, elle reste dans l'historique :
    /// un segment final peut arriver APRÈS la fermeture (drain), et son premier
    /// mot doit encore trouver sa fenêtre.
    struct Fenetre: Equatable, Sendable {
        let ouverture: SessionTime
        var marque: Int?
        var relachement: SessionTime?
        var dernierVolatil: SessionTime?
        var mouvement = false
        var fermeture: SessionTime?
        /// Le geste global EXPLICITE : tenue > 400 ms, ni tracé ni mouvement.
        var gesteGlobalExplicite = false

        var estOuverte: Bool { fermeture == nil }

        /// La marge d'ouverture : le moteur date ses résultats sur une timeline
        /// discrétisée à la cadence audio (16 kHz), l'horloge de session compte
        /// à 90 kHz — l'arrondi place la plage d'un segment un cheveu AVANT
        /// l'ouverture qui l'a produite. Cinq millisecondes couvrent cent fois
        /// ce cheveu, et restent cent fois sous la première syllabe possible.
        static let margeOuverture = 0.005

        func contient(_ t: SessionTime) -> Bool {
            guard t.seconds >= ouverture.seconds - Self.margeOuverture else { return false }
            guard let fermeture else { return true }
            return t <= fermeture
        }
    }

    /// L'état complet — une valeur, comparable, copiable : l'autotest vérifie
    /// que `rattacher` ne le modifie jamais.
    struct Machine: Equatable, Sendable {
        var regles: Regles
        private(set) var courante: Fenetre?
        private(set) var historique: [Fenetre] = []
        private(set) var verrouDepuis: SessionTime?
        private(set) var verrousClos: [(SessionTime, SessionTime)] = []

        init(regles: Regles = .defaut) { self.regles = regles }

        static func == (a: Machine, b: Machine) -> Bool {
            a.regles == b.regles && a.courante == b.courante
                && a.historique == b.historique && a.verrouDepuis == b.verrouDepuis
                && a.verrousClos.map { [$0.0, $0.1] } == b.verrousClos.map { [$0.0, $0.1] }
        }

        var estOuverte: Bool { courante?.estOuverte ?? false }
        var marqueCourante: Int? { courante?.marque }
        var verrouActif: Bool { verrouDepuis != nil }

        /// L'instant où la fenêtre courante se fermera d'elle-même, si elle
        /// est relâchée. Nil tant que ⌥⌘ est tenu.
        var echeance: SessionTime? {
            guard let f = courante, f.estOuverte, let relachement = f.relachement else { return nil }
            let plafond = f.ouverture.seconds + regles.plafond
            var base = relachement.seconds + regles.grace
            if let v = f.dernierVolatil, v.seconds + regles.prolongation > base {
                base = v.seconds + regles.prolongation
            }
            return SessionTime(seconds: min(base, plafond))
        }

        // MARK: - Les événements

        @discardableResult
        mutating func appliquer(_ evenement: Evenement) -> [Effet] {
            switch evenement {
            case .prise(let t):
                var effets: [Effet] = []
                // Une nouvelle prise ferme la fenêtre précédente : les fenêtres
                // forment une suite d'intervalles disjoints, et un premier mot
                // ne peut tomber que dans une seule.
                if let f = courante, f.estOuverte { effets.append(fermer(a: t)) }
                courante = Fenetre(ouverture: t)
                effets.append(.ouverture(t))
                return effets

            case .mouvement:
                courante?.mouvement = true
                return []

            case .trace(let t, let marque):
                guard var f = courante, f.estOuverte else { return [] }
                if f.marque == nil {
                    f.marque = marque
                    courante = f
                    return []
                }
                // Second tracé dans la même tenue : la fenêtre se scinde, la
                // suivante porte la nouvelle marque et hérite de la tenue.
                let clos = fermer(a: t)
                courante = Fenetre(ouverture: t, marque: marque)
                return [clos, .ouverture(t)]

            case .relachement(let t):
                guard var f = courante, f.estOuverte, f.relachement == nil else { return [] }
                f.relachement = t
                var effets: [Effet] = []
                if f.marque == nil, !f.mouvement,
                   t.seconds - f.ouverture.seconds > regles.gesteGlobalMinimum {
                    f.gesteGlobalExplicite = true
                    effets.append(.commentaireGeneral)
                }
                courante = f
                return effets

            case .volatil(let t):
                guard var f = courante, f.estOuverte else { return [] }
                // Le DERNIER volatil au sens du temps, pas de l'ordre d'arrivée :
                // un résultat en retard ne doit jamais raccourcir l'échéance.
                f.dernierVolatil = f.dernierVolatil.map { max($0, t) } ?? t
                courante = f
                return []

            case .verrou(let t, let actif):
                if actif {
                    if verrouDepuis == nil { verrouDepuis = t }
                } else if let depuis = verrouDepuis {
                    verrousClos.append((depuis, t))
                    verrouDepuis = nil
                }
                return []

            case .fermetureDOffice(let t, _):
                guard let f = courante, f.estOuverte else { return [] }
                return [fermer(a: t)]

            case .tic(let t):
                guard let echeance, t >= echeance else { return [] }
                return [fermer(a: echeance)]
            }
        }

        /// Ferme la fenêtre courante à l'instant donné et la verse à
        /// l'historique.
        private mutating func fermer(a t: SessionTime) -> Effet {
            var f = courante!
            f.fermeture = max(t, f.ouverture)
            historique.append(f)
            courante = f
            return .fermeture(f)
        }

        // MARK: - La question : à qui appartient ce segment ?

        /// PURE, et vérifiée telle : elle ne touche pas l'état.
        ///
        /// L'ordre des règles est celui du § 3.5 : le verrou l'emporte sur tout
        /// (un monologue verrouillé est global même si une fenêtre a une
        /// marque) ; puis la fenêtre contenant le PREMIER mot ; sans fenêtre,
        /// `.aucuneFenetre`.
        func rattacher(premierMot debut: SessionTime, fin: SessionTime) -> Attachement {
            if verrouCouvre(debut) { return .global(regle: .gesteGlobal) }

            let candidates = historique + (courante.map { [$0] } ?? [])
            guard let f = candidates.last(where: { $0.contient(debut) }) else {
                return .global(regle: .aucuneFenetre)
            }
            guard let marque = f.marque else { return .global(regle: .gesteGlobal) }
            let deborde = f.fermeture.map { fin > $0 } ?? false
            return .marque(marque, regle: deborde ? .debordement : .fenetreDeParole)
        }

        private func verrouCouvre(_ t: SessionTime) -> Bool {
            if let depuis = verrouDepuis, t >= depuis { return true }
            return verrousClos.contains { t >= $0.0 && t <= $0.1 }
        }
    }
}
