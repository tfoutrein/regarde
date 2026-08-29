import AppKit
import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest de la boucle — S53
//
// Le critère du plan finit par : « git status d'un dépôt neuf ne propose que
// manifest.json, report.md et index.jsonl ». On le prend au mot : un VRAI
// `git init`, une VRAIE publication avec de VRAIS PNG, et `git status
// --porcelain` jugé par ÉGALITÉ D'ENSEMBLES — pas « contient », pas « au
// moins » : exactement ces fichiers, et le .gitignore qui les accompagne.
// Un fichier de trop dans un dépôt client est le bug que ce test garde.
// ─────────────────────────────────────────────────────────────────────────────

enum BoucleSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la boucle (S53) ──\n")
        phrase(t)
        assembleur(t)
        publicationDansGit(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - La phrase du § 9.10

    private static func phrase(_ t: Tally) {
        print("· La phrase du presse-papiers (§ 9.10)")
        let p = BouclePublication.phrase(numero: 42, cheminRapport: "/p/x/report.md")
        check(t, "une seule ligne, sans retour chariot", !p.contains("\n"))
        check(t, "la clause « puis applique les corrections »",
              p.contains("puis applique les corrections"))
        check(t, "l'appel d'outil et le repli chemin absolu",
              p.contains("get_feedback number=42")
                && p.hasSuffix("Si l'outil n'est pas disponible, lis /p/x/report.md"))
    }

    // MARK: - L'assembleur, pur

    private static func donneesFabriquees(images: [BouclePublication.Donnees.Image],
                                          voix: [SegmentDeParole] = [])
        -> BouclePublication.Donnees {
        BouclePublication.Donnees(
            uuid: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            debut: Date(timeIntervalSince1970: 1_787_300_000),
            dureeSecondes: 95, dureeMuraleSecondes: 95,
            cible: "Aperçu — fenêtre « maquette.png »",
            ecran: "Display principal, 1728×1117 pt @2×",
            interruptions: "aucune",
            marques: [
                .init(numero: 1, genre: "arrow", tempsSession: 12.5,
                      intention: "alignement", ecranEnMouvement: false,
                      boite: NormRect(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
                      ecranPoints: CGSize(width: 1728, height: 1117), facteurEcran: 2),
                .init(numero: 2, genre: "rect", tempsSession: 47.0,
                      intention: nil, ecranEnMouvement: false,
                      boite: NormRect(x: 0.5, y: 0.5, w: 0.2, h: 0.2),
                      ecranPoints: CGSize(width: 1728, height: 1117), facteurEcran: 2),
            ],
            images: images,
            outilVersion: "0.4.0-test", os: "macOS 26.1", build: "999", voix: voix)
    }

    private static func assembleur(_ t: Tally) {
        print("\n· L'assembleur — la traduction vers le § 9.5")
        let images = [BouclePublication.Donnees.Image(
            numero: 1, url: URL(fileURLWithPath: "/x/marque-01.png"),
            taillePixels: CGSize(width: 756, height: 532))]
        let m = BouclePublication.assembler(
            donneesFabriquees(images: images),
            projet: "/p/x", detection: "**probable** — 1 shell", git: nil)

        check(t, "deux marques traduites, la 2 sans image ni cadre",
              m.marks.count == 2 && m.marks[1].frames == nil)
        check(t, "les jetons du crop viennent du barème, pas d'une constante",
              m.frames.first?.visualTokens == Bareme.jetonsVisuels(
                largeur: 756, hauteur: 532, palier: .standard))
        check(t, "la géométrie normalisée traverse",
              m.marks[0].geometry.normalized.x == 0.1
                && m.marks[0].geometry.normalized.h == 0.4)
        // Contre-épreuve du défaut D-01 de la recette : les points sont la bbox
        // × l'écran, les pixels × le facteur — plus jamais « 0×0 pt à (0, 0) ».
        check(t, "les points et pixels sortent du repère écran, pas du recadrage",
              abs(m.marks[0].geometry.points.x - 172.8) < 0.001
                && abs(m.marks[0].geometry.points.h - 446.8) < 0.001
                && abs(m.marks[0].geometry.pixels.w - 1036.8) < 0.001
                && m.marks[0].geometry.frameScaleFactor == 2
                && m.marks[1].geometry.points.w > 0)
        check(t, "le numéro est PROVISOIRE — l'attribution le remplacera",
              m.session.number == 0)
        check(t, "le contexte porte les sept lignes, chacune renseignée",
              m.session.context?.project != nil && m.session.context?.detection != nil
                && m.session.context?.application != nil && m.session.context?.screen != nil
                && m.session.context?.interruptions != nil && m.session.context?.status != nil)
        check(t, "le rendu du brouillon tient debout",
              Rendu.rendre(m).contains("## Marque 2"))
    }

    // MARK: - La publication, dans un vrai dépôt git

    private static func png(_ taille: CGSize, vers url: URL) -> Bool {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(taille.width), pixelsHigh: Int(taille.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private static func git(_ racine: URL, _ arguments: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", racine.path] + arguments
        let sortie = Pipe()
        p.standardOutput = sortie; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: sortie.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func publicationDansGit(_ t: Tally) {
        print("\n· Un dépôt git neuf, une publication, git status au mot près")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("boucle-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let depot = base.appendingPathComponent("projet", isDirectory: true)
        let regardeHome = base.appendingPathComponent("regarde-home", isDirectory: true)
        try? FileManager.default.createDirectory(at: depot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: regardeHome, withIntermediateDirectories: true)
        guard git(depot, ["init", "-q"]) != nil else {
            check(t, "git init", false); return
        }

        // Deux PNG réels, comme la session en aurait laissés sous ~/Regarde.
        let src1 = regardeHome.appendingPathComponent("marque-01.png")
        let src2 = regardeHome.appendingPathComponent("marque-02.png")
        guard png(CGSize(width: 756, height: 532), vers: src1),
              png(CGSize(width: 448, height: 280), vers: src2) else {
            check(t, "PNG de test écrits", false); return
        }
        let images = [
            BouclePublication.Donnees.Image(numero: 1, url: src1,
                taillePixels: CGSize(width: 756, height: 532)),
            BouclePublication.Donnees.Image(numero: 2, url: src2,
                taillePixels: CGSize(width: 448, height: 280)),
        ]
        let donnees = donneesFabriquees(images: images)
        let brouillon = BouclePublication.assembler(
            donnees, projet: depot.path, detection: "**certaine** — test", git: nil)

        do {
            let resultat = try BouclePublication.publier(
                donnees, brouillon: brouillon, racine: depot, slug: "test")
            check(t, "numéro 1 attribué, phrase construite",
                  resultat.attribution.numero == 1
                    && resultat.phrase.contains("get_feedback number=1"))

            // LE critère : git status --porcelain, en ensemble EXACT.
            guard let statut = git(depot, ["status", "--porcelain", "-uall"]) else {
                check(t, "git status", false); return
            }
            let proposes = Set(statut.split(separator: "\n").map {
                String($0.dropFirst(3))
            })
            let id = resultat.attribution.id
            let attendus: Set<String> = [
                ".regarde/.gitignore",
                ".regarde/index.jsonl",
                ".regarde/sessions/\(id)/manifest.json",
                ".regarde/sessions/\(id)/report.md",
            ]
            check(t, "git ne propose QUE gitignore, index, manifest et report",
                  proposes == attendus,
                  proposes == attendus ? "" : "écart : \(proposes.symmetricDifference(attendus).sorted())")

            // Les images ont bien traversé, renommées crop-NN.
            let frames = resultat.attribution.dossier.appendingPathComponent("frames")
            check(t, "les PNG copiés en crop-01/crop-02, dans le projet",
                  FileManager.default.fileExists(atPath: frames.appendingPathComponent("crop-01.png").path)
                    && FileManager.default.fileExists(atPath: frames.appendingPathComponent("crop-02.png").path))

            // state.jsonl : alimenté, et ignoré par git (déjà prouvé par
            // l'ensemble exact ci-dessus — il n'y figure pas).
            let state = try String(contentsOf:
                depot.appendingPathComponent(".regarde/state.jsonl"), encoding: .utf8)
            check(t, "state.jsonl porte l'événement published",
                  state.contains("\"event\":\"published\"") && state.contains("\"number\":1"))

            // Le manifeste relu du disque est complet et rendu-compatible.
            let manifeste = try Manifeste.decoder(Data(contentsOf:
                resultat.attribution.dossier.appendingPathComponent("manifest.json")))
            check(t, "le manifeste relu rend un rapport aux six sections",
                  Rendu.rendre(manifeste).contains("## Récapitulatif")
                    && manifeste.session.number == 1)

            // S66 — une seconde session, PARLÉE cette fois : le transcript est
            // le cinquième chemin, et il n'existe que s'il a quelque chose à
            // dire — la première session, muette, n'en avait pas.
            var rattache = SegmentDeParole(
                mots: [], texte: "Il manque du pratique à droite.",
                plageDebut: SessionTime(seconds: 26.9), plageFin: SessionTime(seconds: 31.5))
            rattache.attachement = .marque(1, regle: .fenetreDeParole)
            rattache.premierMot = SessionTime(seconds: 27.02)
            rattache.texte = "Il manque du padding à droite."   // édité : le brut ne bouge pas
            var global = SegmentDeParole(
                mots: [], texte: "Globalement la page est lente.",
                plageDebut: SessionTime(seconds: 50), plageFin: SessionTime(seconds: 53))
            global.attachement = .global(regle: .gesteGlobal)
            let parlee = donneesFabriquees(images: images, voix: [global, rattache])
            let brouillon2 = BouclePublication.assembler(
                parlee, projet: depot.path, detection: "**certaine** — test", git: nil)
            let resultat2 = try BouclePublication.publier(
                parlee, brouillon: brouillon2, racine: depot, slug: "parlee")
            guard let statut2 = git(depot, ["status", "--porcelain", "-uall"]) else {
                check(t, "git status, session parlée", false); return
            }
            let proposes2 = Set(statut2.split(separator: "\n").map { String($0.dropFirst(3)) })
            let id2 = resultat2.attribution.id
            let attendus2 = attendus.union([
                ".regarde/sessions/\(id2)/manifest.json",
                ".regarde/sessions/\(id2)/report.md",
                ".regarde/sessions/\(id2)/transcript.txt",
            ])
            check(t, "session parlée : transcript.txt est le CINQUIÈME chemin, versionnable",
                  proposes2 == attendus2,
                  proposes2 == attendus2 ? "" : "écart : \(proposes2.symmetricDifference(attendus2).sorted())")
            let transcript = try String(contentsOf:
                resultat2.attribution.dossier.appendingPathComponent("transcript.txt"), encoding: .utf8)
            let lignes = transcript.split(separator: "\n").map(String.init)
            check(t, "deux lignes, dans l'ordre du premier mot — la marque avant le global",
                  lignes.count == 2 && lignes[0].hasPrefix("[00:27.0] (marque 1)")
                    && lignes[1].hasPrefix("[00:50.0] (global)"))
            check(t, "le transcript porte le BRUT, pas le texte édité",
                  lignes[0].hasSuffix("Il manque du pratique à droite.")
                    && !transcript.contains("padding"))
            check(t, "la session muette n'a PAS de transcript.txt — rien à dire, pas de fichier",
                  !FileManager.default.fileExists(
                      atPath: resultat.attribution.dossier.appendingPathComponent("transcript.txt").path))
        } catch {
            check(t, "publication dans le dépôt", false, "\(error)")
        }
    }
}
