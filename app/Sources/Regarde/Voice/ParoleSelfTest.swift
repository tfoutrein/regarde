import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest de la fenêtre de parole — S63
//
// Une table de cas sur des événements FABRIQUÉS, chaque règle du § 3.5 avec
// sa contre-épreuve : un premier mot 1 ms après la fermeture est global, pas
// rattaché ; les volatils ne prolongent jamais au-delà de 20 s ; deux fenêtres
// successives font une timeline discontinue mais monotone. Et la question
// elle-même est pure : la poser deux fois ne change ni la réponse ni l'état.
// ─────────────────────────────────────────────────────────────────────────────

enum ParoleSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    private static func s(_ v: Double) -> SessionTime { SessionTime(seconds: v) }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la fenêtre de parole (S63) ──\n")
        rattachement(t)
        gesteGlobal(t)
        verrou(t)
        fermeture(t)
        prolongation(t)
        suite(t)
        scission(t)
        office(t)
        purete(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    /// Une session type : prise à 10, tracé de la marque 1 à 11, relâchement
    /// à 12, fermeture d'elle-même à 20.
    private static func sessionType() -> FenetreDeParole.Machine {
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(10)))
        m.appliquer(.mouvement(s(10.5)))
        m.appliquer(.trace(s(11), marque: 1))
        m.appliquer(.relachement(s(12)))
        m.appliquer(.tic(s(20)))
        return m
    }

    private static func rattachement(_ t: Tally) {
        print("· Les quatre règles du § 3.5, sur une session type")
        let m = sessionType()
        check(t, "parole pendant la fenêtre → marque du geste, .fenetreDeParole",
              m.rattacher(premierMot: s(13), fin: s(15))
                == .marque(1, regle: .fenetreDeParole))
        check(t, "parole commencée AVANT le tracé, même tenue → même marque",
              m.rattacher(premierMot: s(10.2), fin: s(12))
                == .marque(1, regle: .fenetreDeParole))
        check(t, "segment final qui DÉBORDE après la fermeture → rattaché, .debordement",
              m.rattacher(premierMot: s(19), fin: s(22.5))
                == .marque(1, regle: .debordement))
        check(t, "premier mot 1 ms APRÈS la fermeture → global, .aucuneFenetre — la contre-épreuve",
              m.rattacher(premierMot: s(20.001), fin: s(23))
                == .global(regle: .aucuneFenetre))
        check(t, "premier mot AVANT la prise → .aucuneFenetre — aucun tampon ne précède l'ouverture",
              m.rattacher(premierMot: s(9.9), fin: s(11))
                == .global(regle: .aucuneFenetre))
    }

    private static func gesteGlobal(_ t: Tally) {
        print("\n· Le geste global : tenue > 400 ms, ni mouvement ni tracé")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(30)))
        let effets = m.appliquer(.relachement(s(30.6)))
        check(t, "l'effet « commentaire général » sort au relâchement",
              effets.contains(.commentaireGeneral))
        m.appliquer(.tic(s(40)))
        check(t, "la parole de cette fenêtre est globale, .gesteGlobal",
              m.rattacher(premierMot: s(31), fin: s(33)) == .global(regle: .gesteGlobal))

        var court = FenetreDeParole.Machine()
        court.appliquer(.prise(s(30)))
        let effetsCourt = court.appliquer(.relachement(s(30.3)))
        check(t, "tenue de 300 ms : PAS d'annonce — sous le seuil de 400 ms",
              !effetsCourt.contains(.commentaireGeneral))
        check(t, "…mais sa parole reste globale : elle ne se jette jamais en silence",
              court.rattacher(premierMot: s(31), fin: s(32)) == .global(regle: .gesteGlobal))

        var bouge = FenetreDeParole.Machine()
        bouge.appliquer(.prise(s(30)))
        bouge.appliquer(.mouvement(s(30.2)))
        let effetsBouge = bouge.appliquer(.relachement(s(31)))
        check(t, "tenue longue MAIS avec mouvement : pas de geste global explicite",
              !effetsBouge.contains(.commentaireGeneral))
    }

    private static func verrou(_ t: Tally) {
        print("\n· Le verrou ⌃⌥M l'emporte sur la fenêtre")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(10)))
        m.appliquer(.trace(s(11), marque: 1))
        m.appliquer(.verrou(s(12), actif: true))
        check(t, "verrouillé pendant une fenêtre à marque → global, .gesteGlobal",
              m.rattacher(premierMot: s(13), fin: s(15)) == .global(regle: .gesteGlobal))
        check(t, "…la parole d'AVANT le verrou reste à la marque",
              m.rattacher(premierMot: s(11.5), fin: s(11.9)) == .marque(1, regle: .fenetreDeParole))
        m.appliquer(.verrou(s(14), actif: false))
        check(t, "après déverrouillage, la fenêtre reprend ses droits",
              m.rattacher(premierMot: s(14.5), fin: s(15)) == .marque(1, regle: .fenetreDeParole))
        check(t, "la période verrouillée reste globale, même relue après coup",
              m.rattacher(premierMot: s(13.5), fin: s(14)) == .global(regle: .gesteGlobal))
    }

    private static func fermeture(_ t: Tally) {
        print("\n· La fermeture : 8 s après le relâchement, pas avant")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(0)))
        m.appliquer(.trace(s(1), marque: 1))
        check(t, "⌥⌘ tenu : aucune échéance", m.echeance == nil)
        m.appliquer(.relachement(s(2)))
        check(t, "échéance = relâchement + 8 s", m.echeance == s(10))
        check(t, "tic à 9,9 s : encore ouverte", m.appliquer(.tic(s(9.9))).isEmpty && m.estOuverte)
        let effets = m.appliquer(.tic(s(10)))
        check(t, "tic à 10 s : fermée, à l'échéance exacte et pas à l'instant du tic",
              !m.estOuverte && effets.contains(where: {
                  if case .fermeture(let f) = $0 { return f.fermeture == s(10) }
                  return false
              }))
        check(t, "un tic tardif ferme à l'ÉCHÉANCE, pas à l'heure du tic",
              { var r = FenetreDeParole.Machine()
              r.appliquer(.prise(s(0))); r.appliquer(.relachement(s(2)))
              r.appliquer(.tic(s(15)))
              return r.rattacher(premierMot: s(12), fin: s(13)) == .global(regle: .aucuneFenetre) }())
    }

    private static func prolongation(_ t: Tally) {
        print("\n· La prolongation par les volatils, sous le plafond de 20 s")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(0)))
        m.appliquer(.trace(s(1), marque: 1))
        m.appliquer(.relachement(s(2)))
        m.appliquer(.volatil(s(9.5)))
        check(t, "un volatil à 9,5 s repousse l'échéance à 10,5 s", m.echeance == s(10.5))
        m.appliquer(.volatil(s(5)))
        check(t, "un volatil ANCIEN ne raccourcit rien — max, pas dernier venu",
              m.echeance == s(10.5))
        var longue = FenetreDeParole.Machine()
        longue.appliquer(.prise(s(0)))
        longue.appliquer(.trace(s(1), marque: 1))
        longue.appliquer(.relachement(s(2)))
        for i in stride(from: 3.0, through: 19.9, by: 0.3) { longue.appliquer(.volatil(s(i))) }
        check(t, "volatils continus jusqu'à 19,9 s : échéance = 20 s, le plafond — jamais 20,9",
              longue.echeance == s(20))
        longue.appliquer(.tic(s(20)))
        check(t, "à 20 s la fenêtre est close malgré la parole en cours",
              !longue.estOuverte)
    }

    private static func suite(_ t: Tally) {
        print("\n· Deux fenêtres successives : timeline discontinue, mais monotone")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(0))); m.appliquer(.trace(s(1), marque: 1)); m.appliquer(.relachement(s(2)))
        m.appliquer(.tic(s(10)))
        m.appliquer(.prise(s(30))); m.appliquer(.trace(s(31), marque: 2)); m.appliquer(.relachement(s(32)))
        m.appliquer(.tic(s(40)))
        check(t, "premier mot à 5 s → marque 1", m.rattacher(premierMot: s(5), fin: s(6)) == .marque(1, regle: .fenetreDeParole))
        check(t, "premier mot à 35 s → marque 2", m.rattacher(premierMot: s(35), fin: s(36)) == .marque(2, regle: .fenetreDeParole))
        check(t, "premier mot dans le TROU (20 s) → .aucuneFenetre",
              m.rattacher(premierMot: s(20), fin: s(21)) == .global(regle: .aucuneFenetre))

        var chevauche = FenetreDeParole.Machine()
        chevauche.appliquer(.prise(s(0))); chevauche.appliquer(.trace(s(1), marque: 1))
        chevauche.appliquer(.relachement(s(2)))
        let effets = chevauche.appliquer(.prise(s(5)))     // avant l'échéance de la 1re
        check(t, "une nouvelle prise FERME la précédente : intervalles disjoints",
              effets.contains(where: { if case .fermeture(let f) = $0 { return f.fermeture == s(5) }; return false }))
        chevauche.appliquer(.trace(s(6), marque: 2))
        check(t, "4 s → marque 1, 6,5 s → marque 2 : la frontière est la prise",
              chevauche.rattacher(premierMot: s(4), fin: s(4.5)) == .marque(1, regle: .fenetreDeParole)
                && chevauche.rattacher(premierMot: s(6.5), fin: s(7)) == .marque(2, regle: .fenetreDeParole))
    }

    private static func scission(_ t: Tally) {
        print("\n· Deux tracés dans la même tenue : la fenêtre se scinde")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(0)))
        m.appliquer(.trace(s(1), marque: 1))
        let effets = m.appliquer(.trace(s(4), marque: 2))
        check(t, "le second tracé ferme la première fenêtre et en ouvre une autre",
              effets.count == 2 && m.marqueCourante == 2)
        check(t, "premier mot à 2 s → marque 1 ; à 5 s → marque 2",
              m.rattacher(premierMot: s(2), fin: s(3)) == .marque(1, regle: .fenetreDeParole)
                && m.rattacher(premierMot: s(5), fin: s(6)) == .marque(2, regle: .fenetreDeParole))
        check(t, "la seconde fenêtre hérite de la tenue : pas d'échéance tant que ⌥⌘ est tenu",
              m.echeance == nil)
    }

    private static func office(_ t: Tally) {
        print("\n· La fermeture d'office : saisie sécurisée, veille")
        var m = FenetreDeParole.Machine()
        m.appliquer(.prise(s(0))); m.appliquer(.trace(s(1), marque: 1)); m.appliquer(.relachement(s(2)))
        let effets = m.appliquer(.fermetureDOffice(s(4), raison: "saisie sécurisée"))
        check(t, "fermée à l'instant de l'ordre, pas à l'échéance",
              !m.estOuverte && effets.contains(where: { if case .fermeture(let f) = $0 { return f.fermeture == s(4) }; return false }))
        check(t, "un premier mot après l'ordre est global — rien ne s'enregistre plus",
              m.rattacher(premierMot: s(4.5), fin: s(6)) == .global(regle: .aucuneFenetre))
        check(t, "un second ordre sur une fenêtre close ne fait rien",
              m.appliquer(.fermetureDOffice(s(5), raison: "veille")).isEmpty)
    }

    private static func purete(_ t: Tally) {
        print("\n· La question est pure")
        let m = sessionType()
        let avant = m
        _ = m.rattacher(premierMot: s(13), fin: s(15))
        _ = m.rattacher(premierMot: s(25), fin: s(26))
        check(t, "rattacher deux fois ne change ni la réponse ni l'état",
              m == avant && m.rattacher(premierMot: s(13), fin: s(15))
                == m.rattacher(premierMot: s(13), fin: s(15)))
        check(t, "un événement hors fenêtre (volatil sans fenêtre) ne crée rien",
              { var v = FenetreDeParole.Machine(); return v.appliquer(.volatil(s(1))).isEmpty && !v.estOuverte }())
    }
}
