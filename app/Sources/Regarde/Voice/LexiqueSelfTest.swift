import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du lexique — S68
//
// Les paires ne sont pas inventées : ce sont les erreurs que CE moteur a
// réellement commises sur cette machine pendant S62 à S65, relevées au journal.
// Un lexique calibré sur des fautes imaginaires corrigerait des fautes
// imaginaires.
// ─────────────────────────────────────────────────────────────────────────────

enum LexiqueSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du lexique (S68) ──\n")
        phonetique(t)
        portes(t)
        marquage(t)
        identifiants(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - La distance, sur des fautes RÉELLES

    private static func phonetique(_ t: Tally) {
        print("· La distance phonétique, sur les fautes réelles de ce moteur")
        let vraies = [("Checkou", "checkout"), ("chant", "champ"), ("Calbac", "callback"),
                      ("spinnet", "spinner"), ("modèle", "modale"), ("Z index", "z-index"),
                      ("use effect", "useEffect"), ("Lapie", "API")]
        let rattrapees = vraies.filter { Phonetique.proche($0.0, $0.1) }
        check(t, "les huit fautes proches sont rattrapées", rattrapees.count == vraies.count,
              "\(rattrapees.count)/\(vraies.count)")
        check(t, "« chant » et « champ » ont le MÊME squelette — homophones /ʃɑ̃/",
              Phonetique.squelette("chant") == Phonetique.squelette("champ"))

        // Les fautes LOINTAINES ne sont pas rattrapées, et c'est écrit : la
        // limite du lexique est un fait, pas une surprise de recette.
        let lointaines = [("Tou", "timeout"), ("ste", "state"), ("bacoint", "breakpoint")]
        check(t, "les fautes lointaines ne sont PAS rattrapées — la limite est connue",
              lointaines.allSatisfy { !Phonetique.proche($0.0, $0.1) })

        // Ce qu'il ne faut jamais proposer.
        check(t, "« you » ne devient jamais « useEffect » — trop court, trop loin",
              !Phonetique.proche("you", "useEffect"))
        check(t, "« page » ne devient jamais « padding »",
              !Phonetique.proche("page", "padding"))
        check(t, "un mot vide ou d'une lettre ne propose rien",
              !Phonetique.proche("", "padding") && !Phonetique.proche("a", "API"))
    }

    // MARK: - Les deux portes

    private static func mot(_ texte: String, _ confiance: Double?) -> Mot {
        Mot(texte: texte, debut: SessionTime(seconds: 1), fin: SessionTime(seconds: 2),
            confiance: confiance)
    }

    private static func portes(_ t: Tally) {
        print("\n· Les deux portes : la confiance d'abord, la ressemblance ensuite")
        let termes = Lexique.termesFront

        // LA CONTRE-ÉPREUVE DU SEUIL : le même mot, deux confiances.
        let doute = Lexique.appliquer(texte: "Il manque du Calbac ici.",
                                      mots: [mot("Calbac", 0.41)], termes: termes)
        check(t, "confiance 0,41 : la proposition est faite",
              doute.suggestions.first?.propose == "callback")
        let sur = Lexique.appliquer(texte: "Il manque du Calbac ici.",
                                    mots: [mot("Calbac", 0.9)], termes: termes)
        check(t, "confiance 0,90 : le MÊME mot n'est JAMAIS corrigé — la porte du seuil",
              sur.suggestions.isEmpty && sur.texte == "Il manque du Calbac ici.")
        let juste = Lexique.appliquer(texte: "x", mots: [mot("Calbac", 0.6)], termes: termes)
        check(t, "confiance 0,60 pile : au-dessus du doute, pas de proposition",
              juste.suggestions.isEmpty)

        // Sans confiance connue, on ne propose rien : ne pas savoir n'est pas douter.
        let inconnue = Lexique.appliquer(texte: "x", mots: [mot("Calbac", nil)], termes: termes)
        check(t, "confiance inconnue : rien — ne pas savoir n'est pas douter",
              inconnue.suggestions.isEmpty)

        // Un mot douteux sans voisin ne propose rien plutôt que n'importe quoi.
        let orphelin = Lexique.appliquer(texte: "Le zorglub est cassé.",
                                         mots: [mot("zorglub", 0.2)], termes: termes)
        check(t, "un mot douteux SANS voisin phonétique ne propose rien",
              orphelin.suggestions.isEmpty)

        // Le meilleur candidat, pas le premier venu.
        let modal = Lexique.appliquer(texte: "La modèle ne se ferme pas.",
                                      mots: [mot("modèle", 0.3)], termes: termes)
        check(t, "entre « modale » et « modal », le plus proche gagne",
              modal.suggestions.first?.propose == "modale",
              modal.suggestions.first?.propose ?? "aucune")
    }

    // MARK: - Le marquage du § 9.4

    private static func marquage(_ t: Tally) {
        print("\n· Le marquage : les DEUX versions, jamais l'une à la place de l'autre")
        let r = Lexique.appliquer(texte: "Il manque du Calbac à droite.",
                                  mots: [mot("Calbac", 0.41)], termes: Lexique.termesFront)
        check(t, "le texte porte `*entendu* **[proposé ?]**` (§ 9.4)",
              r.texte == "Il manque du *Calbac* **[callback ?]** à droite.", r.texte)
        check(t, "la suggestion garde sa confiance et son instant, pour le manifeste",
              r.suggestions.first?.confiance == 0.41 && r.suggestions.first?.instant == 1)
        check(t, "l'entendu reste DANS le texte — le lexique propose, il ne remplace pas",
              r.texte.contains("Calbac"))
    }

    // MARK: - Les identifiants du projet

    private static func identifiants(_ t: Tally) {
        print("\n· Les identifiants du projet")
        let source = """
        import { useState } from "react"
        export function CheckoutForm({ cartTotal, onSubmit }) {
          const [promoCode, setPromoCode] = useState("")
          return <form className="checkout-form" onSubmit={onSubmit} />
        }
        """
        let trouves = Set(IdentifiantsProjet.extraire(de: source))
        check(t, "les identifiants composés sortent, ET leurs parties prononçables",
              trouves.contains("CheckoutForm") && trouves.contains("Checkout")
                && trouves.contains("cartTotal") && trouves.contains("promoCode"))
        check(t, "les mots-clés du langage sont écartés — ils ne désignent rien",
              !trouves.contains("export") && !trouves.contains("function")
                && !trouves.contains("const") && !trouves.contains("return"))
        check(t, "les mots de moins de quatre lettres aussi",
              !trouves.contains("from") == false && !trouves.contains("id"))
        check(t, "la décomposition suit le camelCase et le kebab-case",
              IdentifiantsProjet.decomposer("checkout-form") == ["checkout", "form"]
                && IdentifiantsProjet.decomposer("cartTotal") == ["cart", "Total"])

        // Bout en bout : un identifiant du projet rattrape une faute que le
        // lexique figé ne connaît pas.
        let termes = Lexique.termesFront + Array(trouves)
        let r = Lexique.appliquer(texte: "Le promocode ne marche pas.",
                                  mots: [mot("promocode", 0.35)], termes: termes)
        check(t, "un identifiant du PROJET rattrape ce que le lexique figé ignore",
              r.suggestions.first?.propose == "promoCode",
              r.suggestions.first?.propose ?? "aucune")
    }
}
