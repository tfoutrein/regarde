import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du rendu — S48 (barème, manifeste) puis S49 (le rendu lui-même)
//
// Il vit dans l'application mais ne teste QUE la cible RegardeRender : si un
// import du modèle applicatif devient nécessaire ici, c'est que la frontière
// du § 9.3 vient d'être trouée — et c'est le compilateur qui le dira.
// ─────────────────────────────────────────────────────────────────────────────

enum RenderSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du rendu (S48+) ──\n")
        bareme(t)
        manifeste(t)
        rendu(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - Le barème (§ 9.6)

    private static func bareme(_ t: Tally) {
        print("· Le barème plafonné")

        // Les quatre vecteurs NORMATIFS du § 9.6. Le premier porte la
        // contre-épreuve du plafond : ses patches bruts valent 9 920, et c'est
        // ce nombre — celui que la conception initiale annonçait à tort — que le
        // test verrait apparaître si quelqu'un retirait le min().
        check(t, "capture native 3456×2234 — 9 920 patches bruts…",
              Bareme.patches(largeur: 3456, hauteur: 2234) == 9920,
              "\(Bareme.patches(largeur: 3456, hauteur: 2234))")
        check(t, "…plafonnés à 4 784 — retirer le plafond annoncerait 9 920",
              Bareme.jetonsVisuels(largeur: 3456, hauteur: 2234, palier: .hauteResolution) == 4784,
              "\(Bareme.jetonsVisuels(largeur: 3456, hauteur: 2234, palier: .hauteResolution))")
        check(t, "full_hires optimal 2380×1540 → 4 675",
              Bareme.jetonsVisuels(largeur: 2380, hauteur: 1540, palier: .hauteResolution) == 4675)
        check(t, "full optimal 1316×868 → 1 457",
              Bareme.jetonsVisuels(largeur: 1316, hauteur: 868, palier: .standard) == 1457)
        check(t, "crop typique 756×532 → 513",
              Bareme.jetonsVisuels(largeur: 756, hauteur: 532, palier: .standard) == 513)

        // LE CINQUIÈME VECTEUR — 8:1, non multiple de 28. Les quatre lignes du
        // § 9.6 ne garderaient PAS l'arrondi : trois ont des dimensions
        // multiples exactes de 28, la quatrième est masquée par son plafond. Un
        // arrondi par le bas (91×11 = 1 001) passerait les quatre et fausserait
        // toutes les annonces intermédiaires.
        check(t, "vecteur 8:1 2560×320 — wp = 92, pas 91",
              (2560 + 27) / 28 == 92)
        check(t, "vecteur 8:1 — 92 × 12 = 1 104 jetons, sous le palier",
              Bareme.jetonsVisuels(largeur: 2560, hauteur: 320, palier: .standard) == 1104,
              "\(Bareme.jetonsVisuels(largeur: 2560, hauteur: 320, palier: .standard))")
    }

    // MARK: - Le manifeste (§ 9.5, schemaVersion 1.1)

    private static func manifeste(_ t: Tally) {
        print("\n· Le manifeste, ses réservations et sa majeure")

        // Un extrait fidèle au § 9.5, ENRICHI de deux choses que le décodeur
        // doit accepter : la clé réservée `full_hires`, et une clé INCONNUE
        // (`experimental`) comme en produirait un futur 1.2.
        let json = """
        {
          "schemaVersion": "1.1",
          "experimental": { "future": true },
          "session": {
            "number": 42, "uuid": "5F2C0000-0000-0000-0000-000000000000",
            "id": "0042-20260819-1432-checkout",
            "startedAt": "2026-08-19T14:32:46.031+02:00",
            "durationSeconds": 134.85, "wallDurationSeconds": 134.85,
            "tool": { "name": "Regarde", "version": "0.4.0", "os": "macOS 26.1", "build": "25B78" },
            "locale": "fr-FR", "audioInputLatencyMs": 18,
            "voice": [{
              "id": "v-001",
              "attachment": { "rule": "gesteGlobal", "auto": true, "editedByUser": false },
              "onset": 52.10, "end": 55.80,
              "text": "Globalement la page est lente.",
              "rawText": "Globalement la page est lente.",
              "lexiconSuggestions": []
            }],
            "captureSegments": [{
              "index": 0, "displayID": 1, "codec": "hevc", "fps": 15,
              "firstSamplePTSSeconds": 0.412, "lastSamplePTSSeconds": 134.60,
              "pixelSize": { "w": 3456, "h": 2234 }, "deleted": true
            }],
            "context": {
              "project": "/Users/dev/shop-front",
              "detection": "certaine",
              "git": "feat/checkout-coupon @ a3f19c2",
              "application": "Google Chrome",
              "screen": "Display 1",
              "interruptions": "aucune",
              "status": "nouveau"
            }
          },
          "marks": [{
            "number": 1, "kind": "rect", "sessionTime": 21.381, "captureSegment": 0,
            "isRetroactive": false, "intents": ["alignement"],
            "geometry": {
              "points":     { "x": 988,  "y": 806,  "w": 372, "h": 72 },
              "pixels":     { "x": 1976, "y": 1612, "w": 744, "h": 144 },
              "normalized": { "x": 0.5718, "y": 0.7216, "w": 0.2153, "h": 0.0645 },
              "frameContentRect": { "x": 0, "y": 0, "w": 3456, "h": 2234 },
              "frameScaleFactor": 2.0
            },
            "frames": { "crop": "crop-01", "full": "full-01" },
            "screenWasMoving": false,
            "voice": [{
              "id": "v-002", "attachedTo": 1,
              "attachment": { "rule": "fenetreDeParole", "auto": true, "editedByUser": false },
              "onset": 27.02, "end": 31.55,
              "text": "Il manque du pratique [padding ?] à droite.",
              "rawText": "Il manque du pratique à droite.",
              "lexiconSuggestions": [{ "heard": "pratique", "suggested": "padding", "confidence": 0.41, "at": 27.72 }]
            }]
          }],
          "frames": [{
            "id": "crop-01", "role": "crop",
            "absolutePath": "/Users/dev/shop-front/.regarde/sessions/0042/frames/crop-01.png",
            "size": { "w": 756, "h": 532 },
            "visualTokens": 513, "visualTokensNote": "min(patches, plafond du palier)",
            "bytes": 173044, "marks": [1], "engravedMarks": [1]
          }],
          "budget": {
            "reportTokensEstimate": 870,
            "estimateMethod": "approximation 4 car./jeton, pas un tokeniseur",
            "framesTokens": { "crop": 513, "full": 1457, "full_hires": null },
            "mcpHardLimit": 25000
          }
        }
        """

        do {
            let m = try Manifeste.decoder(Data(json.utf8))
            check(t, "un manifeste § 9.5 se décode, clé inconnue ignorée",
                  m.session.number == 42 && m.marks.count == 1)
            // S60, critère du lot 5 : les membres optionnels voix du § 9.5
            // (voice[], locale, audioInputLatencyMs — schéma 1.1 INCHANGÉ)
            // traversent le décodeur du lot 4 sans le casser, et le rendu les
            // ignore : la voix n'apparaît dans un rapport qu'à partir de S67.
            check(t, "les membres voix de 1.1 ne cassent ni décodeur ni rendu",
                  !Rendu.rendre(m).contains("pratique"))
            check(t, "la clé réservée full_hires est nil, pas zéro",
                  m.budget.framesTokens.full_hires == nil)
            check(t, "le barème confirme les jetons inscrits du crop",
                  Bareme.jetonsVisuels(largeur: m.frames[0].size.w,
                                       hauteur: m.frames[0].size.h,
                                       palier: .standard) == m.frames[0].visualTokens)

            // Aller-retour : ce qu'on encode se relit identique.
            let encodeur = JSONEncoder()
            let rejoue = try Manifeste.decoder(encodeur.encode(m))
            check(t, "aller-retour encode/décode sans perte",
                  rejoue.session.uuid == m.session.uuid
                    && rejoue.marks[0].geometry.pixels.w == 744)
        } catch {
            check(t, "décodage du manifeste de référence", false, "\(error)")
        }

        // Une MINEURE future passe ; une MAJEURE inconnue est refusée nommément.
        let mineure = json.replacingOccurrences(of: "\"1.1\"", with: "\"1.2\"")
        check(t, "schemaVersion 1.2 — la mineure future est acceptée",
              (try? Manifeste.decoder(Data(mineure.utf8))) != nil)
        let majeure = json.replacingOccurrences(of: "\"1.1\"", with: "\"2.0\"")
        do {
            _ = try Manifeste.decoder(Data(majeure.utf8))
            check(t, "schemaVersion 2.0 — la majeure inconnue est refusée", false)
        } catch {
            check(t, "schemaVersion 2.0 — la majeure inconnue est refusée nommément",
                  "\(error)".contains("2.0"))
        }
    }

    // MARK: - Le rendu contre l'empreinte de S46 (S49)

    private static func rendu(_ t: Tally) {
        print("\n· Le rendu, jugé à l'octet contre la cible de S46")

        // Les deux fichiers de référence vivent dans app/Tools/, localisés
        // depuis la source : ce test s'exécute sur la machine de développement,
        // là où le dépôt existe — c'est sa raison d'être.
        let outils = URL(fileURLWithPath: #filePath)          // …/Regarde/Report/RenderSelfTest.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools")
        let manifesteURL = outils.appendingPathComponent("lot4-manifest-reference.json")
        let cibleURL = outils.appendingPathComponent("lot4-rapport-reference.md")

        guard let data = try? Data(contentsOf: manifesteURL),
              let m = try? Manifeste.decoder(data) else {
            check(t, "le manifeste de référence se charge", false, manifesteURL.path)
            return
        }
        guard let cible = try? String(contentsOf: cibleURL, encoding: .utf8) else {
            check(t, "le rapport de référence se charge", false)
            return
        }

        let rapport = Rendu.rendre(m)
        if rapport == cible {
            check(t, "rendu = rapport de référence, octet pour octet", true,
                  "\(rapport.utf8.count) octets")
        } else {
            check(t, "rendu = rapport de référence, octet pour octet", false)
            // La PREMIÈRE ligne divergente, nommée — sans elle, l'écart à
            // l'empreinte est indéboguable.
            let a = rapport.split(separator: "\n", omittingEmptySubsequences: false)
            let b = cible.split(separator: "\n", omittingEmptySubsequences: false)
            for i in 0..<max(a.count, b.count) {
                let la = i < a.count ? String(a[i]) : "«fin du rendu»"
                let lb = i < b.count ? String(b[i]) : "«fin de la cible»"
                if la != lb {
                    print("    ligne \(i + 1) :")
                    print("      rendu : \(la)")
                    print("      cible : \(lb)")
                    break
                }
            }
        }

        // Les trois options, exercées SANS appelant — leurs consommateurs
        // n'existent qu'au lot 6, et une option jamais appelée est une
        // frontière à moitié posée.
        let avecBandeau = Rendu.rendre(m, options: .init(profil: .sidecar,
                                                         bandeau: "> **DÉJÀ TRAITÉ** le 20 août par Claude — « corrigé, sauf la marque 2 »"))
        check(t, "bandeau — préfixé avant l'en-tête",
              avecBandeau.hasPrefix("> **DÉJÀ TRAITÉ**") && avecBandeau.contains("# Feedback #42")
                && avecBandeau != rapport)

        let filtre = Rendu.rendre(m, options: .init(profil: .sidecar, marques: [1]))
        check(t, "filtre par marques — la 1 reste, la 3 disparaît, le compte suit",
              filtre.contains("## Marque 1") && !filtre.contains("## Marque 3")
                && filtre.contains("**1 marque**"))

        let sansContexte = Rendu.rendre(m, options: .init(profil: .sidecar, includeContext: false))
        check(t, "include_context: false — la section Contexte est omise",
              !sansContexte.contains("## Contexte") && sansContexte.contains("## Marque 1"))

        // includeHires est posée et INERTE : même sortie, c'est le contrat
        // jusqu'à S58 — le lot 6 compile contre la signature définitive.
        check(t, "include_hires — posée, inerte jusqu'à S58",
              Rendu.rendre(m, options: .init(includeHires: true)) == rapport)

        // La seconde sortie : paste-web, autonome — pas de chemin absolu, pas
        // de resolve_feedback, mais les mêmes marques.
        let web = Rendu.rendre(m, options: .init(profil: .chatWeb))
        check(t, "paste-web — autonome : ni chemin absolu, ni resolve_feedback",
              !web.contains("/Users/") && !web.contains("resolve_feedback")
                && web.contains("## Marque 3") && web != rapport)
    }
}
