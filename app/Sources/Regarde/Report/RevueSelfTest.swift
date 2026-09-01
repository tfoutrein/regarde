import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest de la revue — S71
//
// Les opérations sont PURES : un manifeste entre, un manifeste sort. C'est ce
// qui permet de les juger sans ouvrir une fenêtre — et de vérifier ce qui
// compte vraiment, qui n'est pas visible à l'écran : que le BRUT survit à une
// édition, et qu'un numéro supprimé laisse un TROU plutôt que de glisser.
// ─────────────────────────────────────────────────────────────────────────────

enum RevueSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    private static func voix(_ id: String, _ marque: Int?, _ texte: String,
                             onset: Double) -> Manifeste.Voice {
        Manifeste.Voice(id: id, attachedTo: marque,
                        attachment: .init(rule: marque == nil ? "gesteGlobal" : "fenetreDeParole",
                                          auto: true, editedByUser: false),
                        onset: onset, end: onset + 3,
                        text: texte, rawText: texte)
    }

    private static func marque(_ n: Int, note: String? = nil,
                               voix v: [Manifeste.Voice] = []) -> Manifeste.Mark {
        Manifeste.Mark(number: n, kind: note == nil ? "rect" : "text", sessionTime: Double(n) * 10,
                       captureSegment: nil, isRetroactive: false, intents: [],
                       geometry: .init(points: .init(x: 0, y: 0, w: 10, h: 10),
                                       pixels: .init(x: 0, y: 0, w: 20, h: 20),
                                       normalized: .init(x: 0, y: 0, w: 0.1, h: 0.1),
                                       frameContentRect: .init(x: 0, y: 0, w: 100, h: 100),
                                       frameScaleFactor: 2),
                       frames: .init(crop: String(format: "crop-%02d", n), full: nil),
                       screenWasMoving: false, contextFramesAvailable: nil, zoneNote: nil,
                       voice: v.isEmpty ? nil : v, text: note)
    }

    private static func fabrique() -> Manifeste.Racine {
        Manifeste.Racine(
            session: .init(number: 42, uuid: "U", id: "0042-x",
                           startedAt: "2026-08-30T10:00:00.000+02:00",
                           durationSeconds: 60, wallDurationSeconds: 60,
                           tool: .init(name: "Regarde", version: "0.5.0", os: "macOS 26.1", build: "1"),
                           locale: "fr-FR", captureSegments: [], context: nil,
                           audioInputLatencyMs: 1,
                           voice: [voix("v-003", nil, "Globalement la page est lente.", onset: 50)]),
            marks: [marque(1, voix: [voix("v-001", 1, "Le bouton est mal aligné.", onset: 10)]),
                    marque(2, note: "il manque un état vide"),
                    marque(3, voix: [voix("v-002", 3, "Le total ne bouge pas.", onset: 30)])],
            frames: [.init(id: "crop-01", role: "crop", absolutePath: "/x/crop-01.png",
                           size: .init(w: 100, h: 100), visualTokens: 100,
                           visualTokensNote: "n", bytes: nil, marks: [1], engravedMarks: [1]),
                     .init(id: "crop-02", role: "crop", absolutePath: "/x/crop-02.png",
                           size: .init(w: 100, h: 100), visualTokens: 100,
                           visualTokensNote: "n", bytes: nil, marks: [2], engravedMarks: [2]),
                     .init(id: "crop-03", role: "crop", absolutePath: "/x/crop-03.png",
                           size: .init(w: 100, h: 100), visualTokens: 100,
                           visualTokensNote: "n", bytes: nil, marks: [3], engravedMarks: [3])],
            budget: .init(reportTokensEstimate: 0, estimateMethod: "n",
                          framesTokens: .init(crop: 300, full: 0, full_hires: nil),
                          mcpHardLimit: 25000))
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la revue (S71) ──\n")
        let m = fabrique()

        print("· Éditer un segment — le BRUT survit")
        let edite = Revue.editerSegment("v-001", texte: "Le bouton Valider est mal aligné.", de: m)
        let v1 = edite.marks.first { $0.number == 1 }?.voice?.first
        check(t, "le texte affiché change", v1?.text == "Le bouton Valider est mal aligné.")
        check(t, "le BRUT ne bouge pas — c'est lui que transcript.txt porte",
              v1?.rawText == "Le bouton est mal aligné.")
        check(t, "editedByUser passe à vrai — le rapport peut le dire",
              v1?.attachment.editedByUser == true)
        let remis = Revue.editerSegment("v-001", texte: "Le bouton est mal aligné.", de: edite)
        check(t, "remettre le texte d'origine remet editedByUser à faux",
              remis.marks.first { $0.number == 1 }?.voice?.first?.attachment.editedByUser == false)

        print("\n· Supprimer un segment")
        let sansSegment = Revue.supprimerSegment("v-002", de: m)
        check(t, "le segment part, sa marque RESTE — supprimer un mot n'efface pas une image",
              sansSegment.marks.first { $0.number == 3 }?.voice == nil
                && sansSegment.marks.count == 3)
        let sansGeneral = Revue.supprimerSegment("v-003", de: m)
        check(t, "un commentaire général se supprime aussi, et la liste devient nil",
              sansGeneral.session.voice == nil)

        print("\n· Supprimer une marque — le numéro laisse un TROU")
        let sansMarque = Revue.supprimerMarque(2, de: m)
        check(t, "la marque part avec son image",
              sansMarque.marks.count == 2
                && !sansMarque.frames.contains { $0.id == "crop-02" })
        check(t, "les numéros restants ne GLISSENT pas — 1 et 3, jamais 1 et 2",
              sansMarque.marks.map(\.number) == [1, 3])
        check(t, "les autres images sont intactes",
              sansMarque.frames.map(\.id) == ["crop-01", "crop-03"])
        check(t, "la parole d'une AUTRE marque survit",
              sansMarque.marks.first { $0.number == 3 }?.voice?.count == 1)

        print("\n· Éditer une note écrite")
        let note = Revue.editerNote(2, texte: "il manque un état vide et un message", de: m)
        check(t, "la note change", note.marks.first { $0.number == 2 }?.text
                == "il manque un état vide et un message")
        let noteVide = Revue.editerNote(2, texte: "", de: m)
        check(t, "une note vidée devient nil, pas une chaîne vide — le rendu n'en parle plus",
              noteVide.marks.first { $0.number == 2 }?.text == nil
                && !Rendu.rendre(noteVide).contains("> « »"))

        print("\n· Le rendu suit, sans être touché")
        check(t, "le rapport réécrit ne cite plus le segment supprimé",
              !Rendu.rendre(sansSegment).contains("Le total ne bouge pas"))
        check(t, "…ni la marque supprimée",
              !Rendu.rendre(sansMarque).contains("## Marque 2"))
        check(t, "le numéro de session ne bouge JAMAIS — il a pu être prononcé",
              sansMarque.session.number == 42 && sansSegment.session.number == 42)

        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }
}
