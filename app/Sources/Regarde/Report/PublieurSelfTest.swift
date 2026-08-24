import Foundation
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du publieur — S50
//
// Tout se joue sur une RACINE FABRIQUÉE dans $TMPDIR : l'arborescence, le
// gitignore, l'attribution, la publication complète. Et le verrou d'attribution
// se juge à DEUX PROCESSUS — fcntl verrouille par processus : la seconde
// demande d'un même processus serait accordée, et un test mono-processus
// passerait au vert sur un mécanisme qui n'a retenu personne.
// ─────────────────────────────────────────────────────────────────────────────

enum PublieurSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    // MARK: - Mode enfant du banc

    /// `--publier-bench <racine> <n> <sortie>` — attribue n numéros, note
    /// « pid numéro » dans son fichier de sortie, sort.
    static func bench(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 3, let n = Int(arguments[1]) else {
            FileHandle.standardError.write(Data("usage : --publier-bench <racine> <n> <sortie>\n".utf8))
            return 2
        }
        let racine = URL(fileURLWithPath: arguments[0], isDirectory: true)
        var lignes = ""
        do {
            for _ in 0..<n {
                let a = try Publieur.attribuer(racine: racine, uuid: UUID(),
                                               date: Date(timeIntervalSince1970: 1_787_300_000),
                                               slug: "banc")
                lignes += "\(getpid()) \(a.numero)\n"
            }
            try Data(lignes.utf8).write(to: URL(fileURLWithPath: arguments[2]))
            return 0
        } catch {
            FileHandle.standardError.write(Data("bench : \(error)\n".utf8))
            return 1
        }
    }

    // MARK: - La suite

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du publieur (S50) ──\n")
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("publieur-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }

        arborescence(t, racine)
        identite(t)
        publication(t, racine)
        deuxProcessus(t)
        metriques(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    private static func arborescence(_ t: Tally, _ racine: URL) {
        print("· L'arborescence et son gitignore")
        do {
            let regarde = try Publieur.preparer(racine: racine)
            let gitignore = try String(
                contentsOf: regarde.appendingPathComponent(".gitignore"), encoding: .utf8)
            // Le contenu du § 9.2, au caractère : les frames et le paste-web ne
            // se versionnent pas, manifest.json et report.md si.
            check(t, "le .gitignore du § 9.2, au caractère",
                  gitignore == "sessions/*/frames/\nsessions/*/context/\nsessions/*/paste-web.md\nstate.jsonl\n")
            _ = try Publieur.preparer(racine: racine)
            check(t, "préparer est idempotent", true)
        } catch {
            check(t, "préparation de l'arborescence", false, "\(error)")
        }
    }

    private static func identite(_ t: Tally) {
        print("\n· L'identité et la règle de slug (S46)")
        check(t, "feat/Checkout Coupon! → feat-checkout-coupon",
              Publieur.slug("feat/Checkout Coupon!") == "feat-checkout-coupon",
              Publieur.slug("feat/Checkout Coupon!"))
        check(t, "vingt-quatre caractères au plus, jamais de tiret pendu",
              Publieur.slug("une-branche-au-nom-vraiment-interminable").count <= 24
                && !Publieur.slug("une-branche-au-nom-vraiment-interminable").hasSuffix("-"))
        check(t, "les diacritiques se plient au lieu d'amputer",
              Publieur.slug("écran à côté") == "ecran-a-cote",
              Publieur.slug("écran à côté"))
        let date = Date(timeIntervalSince1970: 1_787_300_000)
        let id = Publieur.identifiant(numero: 43, date: date, slug: "checkout")
        check(t, "identifiant NNNN-date-heure-slug",
              id.hasPrefix("0043-") && id.hasSuffix("-checkout") && id.count > 18, id)
        check(t, "sans slug, pas de tiret pendu",
              !Publieur.identifiant(numero: 1, date: date, slug: nil).hasSuffix("-"))
    }

    private static func publication(_ t: Tally, _ racine: URL) {
        print("\n· La publication complète, numéro remplacé en publishing")
        // Le manifeste de référence sert de brouillon — son numéro 42 DOIT être
        // remplacé par l'attribution : c'est le point du § 9.2.
        let outils = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools")
        guard let data = try? Data(contentsOf: outils.appendingPathComponent("lot4-manifest-reference.json")),
              let brouillon = try? Manifeste.decoder(data) else {
            check(t, "le brouillon se charge", false); return
        }
        do {
            let uuid = UUID()
            let a = try Publieur.publier(racine: racine, manifeste: brouillon,
                                         uuid: uuid, date: Date(timeIntervalSince1970: 1_787_300_000),
                                         slug: "checkout")
            check(t, "premier numéro attribué : 1", a.numero == 1, "\(a.numero)")
            let manifeste = try Manifeste.decoder(
                Data(contentsOf: a.dossier.appendingPathComponent("manifest.json")))
            check(t, "le manifeste sur disque porte le numéro ATTRIBUÉ, pas le brouillon",
                  manifeste.session.number == 1 && manifeste.session.id == a.id
                    && manifeste.session.uuid == uuid.uuidString)
            let rapport = try String(
                contentsOf: a.dossier.appendingPathComponent("report.md"), encoding: .utf8)
            check(t, "report.md rendu avec le bon numéro",
                  rapport.hasPrefix("# Feedback #1 — "))
            check(t, "paste-web.md et frames/ existent",
                  FileManager.default.fileExists(
                    atPath: a.dossier.appendingPathComponent("paste-web.md").path)
                    && FileManager.default.fileExists(
                        atPath: a.dossier.appendingPathComponent("frames").path))
            check(t, "report.md sous les 25 Kio du seuil n°6",
                  rapport.utf8.count < 25 * 1024, "\(rapport.utf8.count) octets")
        } catch {
            check(t, "publication", false, "\(error)")
        }
    }

    private static func deuxProcessus(_ t: Tally) {
        print("\n· L'attribution, à deux processus")
        let lots = 300
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("publieur-bench-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: racine) }

        let binaire = URL(fileURLWithPath: CommandLine.arguments[0])
        var enfants: [(Process, URL)] = []
        for i in 0..<2 {
            let sortie = racine.appendingPathComponent("enfant-\(i).txt")
            let p = Process()
            p.executableURL = binaire
            p.arguments = ["--publier-bench", racine.path, "\(lots)", sortie.path]
            do { try p.run() } catch {
                check(t, "lancement des enfants", false, "\(error)"); return
            }
            enfants.append((p, sortie))
        }
        enfants.forEach { $0.0.waitUntilExit() }
        check(t, "les deux enfants sortent en 0",
              enfants.allSatisfy { $0.0.terminationStatus == 0 })

        var numeros: [Int] = []
        var pids: Set<String> = []
        for (_, sortie) in enfants {
            guard let texte = try? String(contentsOf: sortie, encoding: .utf8) else {
                check(t, "sortie d'enfant lisible", false); return
            }
            for l in texte.split(separator: "\n") {
                let champs = l.split(separator: " ")
                pids.insert(String(champs[0]))
                numeros.append(Int(champs[1])!)
            }
        }
        check(t, "600 numéros, tous DISTINCTS, de 1 à 600",
              Set(numeros) == Set(1...(2 * lots)), "\(numeros.count) numéros, \(Set(numeros).count) distincts")
        check(t, "DEUX processus réels — fcntl est par processus, le mono serait un faux vert",
              pids.count == 2, "\(pids.sorted())")

        // L'index lui-même : chaque ligne entière et JSON, aucune déchirée.
        let index = racine.appendingPathComponent(".regarde/index.jsonl")
        guard let texte = try? String(contentsOf: index, encoding: .utf8) else {
            check(t, "index.jsonl se relit", false); return
        }
        let lignes = texte.split(separator: "\n")
        let cassees = lignes.filter {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) == nil
        }
        check(t, "index.jsonl — \(2 * lots) lignes, toutes JSON entières",
              lignes.count == 2 * lots && cassees.isEmpty,
              "\(lignes.count) lignes, \(cassees.count) cassée(s)")
    }

    private static func metriques(_ t: Tally) {
        print("\n· Les métriques, hors projet")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("metriques-test-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        do {
            let url = try Metriques.url(base: base)
            check(t, "chemin … /Regarde/metrics.jsonl, répertoire créé",
                  url.path.hasSuffix("Regarde/metrics.jsonl")
                    && FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
            check(t, "et jamais sous une racine de projet — c'est un chemin de base utilisateur",
                  !url.path.contains(".regarde"))
        } catch {
            check(t, "résolution des métriques", false, "\(error)")
        }
    }
}
