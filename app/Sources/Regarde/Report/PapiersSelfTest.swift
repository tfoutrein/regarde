import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du dernier mètre — S54
//
// Le presse-papiers d'essai est un tableau NOMMÉ, privé à ce test : toucher
// `NSPasteboard.general` dans un autotest écraserait le vrai presse-papiers de
// la machine — précisément le comportement que S54 existe pour interdire.
// ─────────────────────────────────────────────────────────────────────────────

enum PapiersSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du dernier mètre (S54) ──\n")
        allerRetourRiche(t)
        inventaire(t)
        porteur(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - L'aller-retour riche

    private static func allerRetourRiche(_ t: Tally) {
        print("· Un contenu riche se recolle avec ses variantes")
        let tableau = NSPasteboard(name: NSPasteboard.Name("regarde-test-\(getpid())"))
        tableau.clearContents()

        // L'item riche du critère : RTF + TIFF + URL, plus un second item —
        // la sauvegarde est PAR ITEM, un seul aplatirait la structure.
        let rtf = Data("{\\rtf1 essai}".utf8)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation ?? Data([0x4D, 0x4D])
        let url = Data("https://exemple.fr/page".utf8)
        let riche = NSPasteboardItem()
        riche.setData(rtf, forType: .rtf)
        riche.setData(tiff, forType: .tiff)
        riche.setData(url, forType: NSPasteboard.PasteboardType("public.url"))
        let simple = NSPasteboardItem()
        simple.setString("second item", forType: .string)
        tableau.writeObjects([riche, simple])

        let sauvegarde = PressePapiers.sauvegarder(depuis: tableau)
        // ≥ 3 et non == 3 : le tableau AJOUTE des types d'alias au dépôt
        // (variantes dynamiques) — la photographie les garde aussi, tant mieux.
        check(t, "deux items photographiés, le riche avec au moins ses trois types",
              sauvegarde.items.count == 2 && sauvegarde.items[0].count >= 3,
              "\(sauvegarde.items.first?.count ?? 0) types sur l'item riche")

        // Écrasement — ce que fait le dépôt de la phrase — puis restauration.
        tableau.clearContents()
        tableau.setString("la phrase", forType: .string)
        let restaures = PressePapiers.restaurer(sauvegarde, vers: tableau)

        let items = tableau.pasteboardItems ?? []
        check(t, "deux items restaurés", items.count == 2)
        check(t, "le RTF revient à l'octet",
              items.first?.data(forType: .rtf) == rtf)
        check(t, "le TIFF revient à l'octet",
              items.first?.data(forType: .tiff) == tiff)
        check(t, "l'URL revient à l'octet",
              items.first?.data(forType: NSPasteboard.PasteboardType("public.url")) == url)
        check(t, "le second item aussi",
              items.count > 1 && items[1].string(forType: .string) == "second item")
        check(t, "l'inventaire de ce tour est VIDE — rien à nommer",
              PressePapiers.inventaire(vus: sauvegarde.typesVus, restaures: restaures).isEmpty)
        tableau.clearContents()
    }

    // MARK: - L'inventaire, sur les cas d'écart

    private static func inventaire(_ t: Tally) {
        print("\n· L'inventaire nomme tout écart")
        let ecarts = PressePapiers.inventaire(
            vus: [["public.rtf", "public.tiff"], ["public.utf8-plain-text"]],
            restaures: [["public.rtf"], ["public.utf8-plain-text"]])
        check(t, "un type perdu est nommé, avec son item",
              ecarts == ["item 1 : « public.tiff » vu mais non restauré"], "\(ecarts)")

        let perdus = PressePapiers.inventaire(
            vus: [["a"], ["b"]], restaures: [["a"]])
        check(t, "un item entier perdu est compté",
              perdus.contains { $0.contains("entier(s) perdus") })
    }

    // MARK: - Le porteur du ⏎, cas par cas

    private static func porteur(_ t: Tally) {
        print("\n· Le porteur du ⏎ — la décision, pure")
        check(t, "⏎ nu dans la grâce → porté",
              PorteurRetour.decision(graceActive: true, keyCode: 36, flags: []))
        check(t, "⏎ HORS de la grâce → passe intact — le critère du plan",
              !PorteurRetour.decision(graceActive: false, keyCode: 36, flags: []))
        check(t, "⌘⏎ dans la grâce → passe — un ⏎ modifié appartient à l'application",
              !PorteurRetour.decision(graceActive: true, keyCode: 36, flags: .maskCommand))
        check(t, "⇧⏎ dans la grâce → passe",
              !PorteurRetour.decision(graceActive: true, keyCode: 36, flags: .maskShift))
        check(t, "une autre touche dans la grâce → passe",
              !PorteurRetour.decision(graceActive: true, keyCode: 1, flags: []))

        // La grâce elle-même : armée, active ; échue, inactive ; désarmée, morte.
        MainActor.assumeIsolated { PorteurRetour.armer(phrase: "x", duree: 0.2) }
        check(t, "armée — la grâce est active", PorteurRetour.graceActive)
        usleep(300_000)
        check(t, "échue à 0,2 s — la grâce est retombée d'elle-même",
              !PorteurRetour.graceActive)
        MainActor.assumeIsolated { PorteurRetour.armer(phrase: "x", duree: 5) }
        PorteurRetour.desarmer()
        check(t, "désarmée explicitement — un seul port par grâce",
              !PorteurRetour.graceActive)
    }
}
