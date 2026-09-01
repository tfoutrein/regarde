import AppKit
import Carbon.HIToolbox
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// La sonde de la saisie texte — S69
//
// Le § 7.4 affirme trois choses que personne n'a vérifiées sur cette machine :
// qu'un `NSTextView` hors écran interprète des `NSEvent` reconstruits, que les
// touches mortes françaises composent, et qu'AUCUNE fenêtre ne devient clé.
// Ce fichier les met à l'épreuve, dans cet ordre — et si la troisième échoue,
// la fonction ne doit pas être livrée du tout : une fenêtre qui vole le focus
// est pire que pas de saisie.
// ─────────────────────────────────────────────────────────────────────────────

enum SaisieSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    /// Un événement clavier fabriqué, comme le tap en verrait passer un.
    private static func frappe(_ code: CGKeyCode, _ flags: CGEventFlags = []) -> CGEvent? {
        let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                        virtualKey: code, keyDown: true)
        e?.flags = flags
        return e
    }

    @MainActor
    static func run() -> Bool {
        let t = Tally()
        print("── Sonde de la saisie texte (S69) ──\n")

        let saisie = SaisieTexte.shared
        // La disposition, lue là où le doctor la lit — première ligne de sa
        // description (« disposition  French »).
        let disposition = KeyboardLayout.shared.describe().first ?? "?"
        print("· \(disposition)")

        // ── LE CRITÈRE, d'abord : aucune fenêtre clé ──
        print("\n· Le critère du § 7.4 : aucune fenêtre ne devient clé")
        check(t, "la fenêtre du champ REFUSE de devenir clé", !saisie.fenetrePeutDevenirClé)
        check(t, "elle n'est pas clé au repos", !saisie.fenetreEstClé)
        check(t, "elle n'est jamais visible", !saisie.fenetreEstVisible)
        let cleAvant = NSApp.keyWindow

        // ── La saisie elle-même ──
        print("\n· La saisie, sur des événements fabriqués")
        saisie.commencer()
        // « abc » — codes physiques ANSI, qui donnent « q », « b », « c » en
        // AZERTY : ce sont les CARACTÈRES rendus qui comptent, pas les codes.
        for code in [CGKeyCode(kVK_ANSI_A), CGKeyCode(kVK_ANSI_B), CGKeyCode(kVK_ANSI_C)] {
            if let e = frappe(code) { saisie.nourrir(e) }
        }
        let trois = saisie.texte
        check(t, "trois frappes donnent trois caractères", trois.count == 3, "« \(trois) »")
        check(t, "les caractères suivent la DISPOSITION, pas les codes ANSI",
              trois != "abc" || disposition.contains("U.S.") || disposition.contains("ABC"), "« \(trois) »")

        // ── Les touches mortes, l'argument technique du § 7.4 ──
        print("\n· Les touches mortes françaises")
        saisie.commencer()
        // Sur AZERTY français, l'accent circonflexe est en position ANSI `[`.
        if let mort = frappe(CGKeyCode(kVK_ANSI_LeftBracket)) { saisie.nourrir(mort) }
        let apresMort = saisie.texte
        if let e = frappe(CGKeyCode(kVK_ANSI_E)) { saisie.nourrir(e) }
        let compose = saisie.texte
        check(t, "la touche morte seule ne pose rien de définitif",
              apresMort.count <= 1, "« \(apresMort) »")
        check(t, "morte + voyelle composent UN caractère accentué",
              compose.count == 1 && compose != apresMort, "« \(compose) »")
        check(t, "et c'est bien un accent — ê, ë, ou l'équivalent de la disposition",
              compose.unicodeScalars.first.map {
                  !CharacterSet.letters.isSuperset(of: CharacterSet(charactersIn: String($0)))
                      || String($0).folding(options: .diacriticInsensitive, locale: nil) != String($0)
              } ?? false, "« \(compose) »")

        // ── L'édition, gratuite elle aussi ──
        print("\n· L'édition vient avec la machine à états de Cocoa")
        saisie.commencer()
        for code in [CGKeyCode(kVK_ANSI_A), CGKeyCode(kVK_ANSI_B)] {
            if let e = frappe(code) { saisie.nourrir(e) }
        }
        let avantEffacement = saisie.texte
        if let e = frappe(CGKeyCode(kVK_Delete)) { saisie.nourrir(e) }
        check(t, "la suppression arrière fonctionne sans une ligne de code",
              saisie.texte.count == avantEffacement.count - 1,
              "« \(avantEffacement) » → « \(saisie.texte) »")

        // ── Les portes ──
        print("\n· Les portes : rien n'entre hors saisie, rien ne fuit d'une fois à l'autre")
        let rendu = saisie.terminer()
        check(t, "terminer rend le texte et vide le champ",
              !rendu.isEmpty && saisie.texte.isEmpty)
        if let e = frappe(CGKeyCode(kVK_ANSI_A)) {
            check(t, "hors saisie, une frappe est REFUSÉE — le champ ne se remplit pas",
                  !saisie.nourrir(e) && saisie.texte.isEmpty)
        }
        saisie.commencer()
        if let e = frappe(CGKeyCode(kVK_ANSI_A)) { saisie.nourrir(e) }
        saisie.abandonner()
        check(t, "abandonner jette tout", saisie.texte.isEmpty && !saisie.active)

        // ── Et le critère, RE-vérifié après tout le trafic ──
        print("\n· Le critère, revérifié après la saisie")
        check(t, "aucune fenêtre clé n'a changé pendant la saisie",
              NSApp.keyWindow === cleAvant)
        check(t, "la fenêtre du champ n'est toujours ni clé ni visible",
              !saisie.fenetreEstClé && !saisie.fenetreEstVisible)

        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }
}
