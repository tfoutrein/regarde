import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest de la porte d'écriture — S47
//
// Deux étages, et le second ne remplace pas le premier :
//
//   L'UNITÉ, sur write injecté. Écritures courtes fabriquées, EINTR fabriqués,
//   erreur franche. C'est ici que « retirer la boucle fait rougir » devient un
//   fait : le faux write ne livre qu'un octet par appel, et sans boucle, un seul
//   octet arrive.
//
//   LES DEUX PROCESSUS, sur fichier réel. Le banc relance ce binaire deux fois
//   (`--append-bench`), chacun écrit 2 000 lignes de 4 096 octets dans le MÊME
//   fichier, et on compte : 4 000 lignes entières, zéro entrelacée, deux PID
//   distincts. Un test mono-processus est REFUSÉ par le test lui-même — flock
//   est attaché à la description de fichier ouverte : dans un même processus,
//   deux threads sur le même log partagent le verrou et un test « à deux
//   écrivains » passerait au vert sur un mécanisme qui n'a jamais servi. Deux
//   verrous et des threads, ensemble, ne prouvent rien.
// ─────────────────────────────────────────────────────────────────────────────

enum AppendSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    // MARK: - Mode enfant du banc

    /// `--append-bench <fichier> <lignes> <taille>` — écrit puis sort. Chaque
    /// ligne commence par le PID et le numéro de séquence : c'est ce qui rend
    /// l'entrelacement et la perte DÉTECTABLES au dépouillement, pas seulement
    /// improbables.
    static func bench(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 3, let lignes = Int(arguments[1]),
              let taille = Int(arguments[2]) else {
            FileHandle.standardError.write(Data("usage : --append-bench <fichier> <lignes> <taille>\n".utf8))
            return 2
        }
        do {
            let log = try AppendOnlyLog(url: URL(fileURLWithPath: arguments[0]))
            let pid = getpid()
            for seq in 0..<lignes {
                let entete = "\(pid) \(seq) "
                // Taille EXACTE, \n compris : un remplissage d'un seul caractère
                // rend toute rupture de ligne visible d'un coup d'œil et d'un grep.
                let bourrage = String(repeating: "x", count: max(0, taille - entete.utf8.count - 1))
                try log.append(ligne: entete + bourrage)
            }
            log.fermer()
            return 0
        } catch {
            FileHandle.standardError.write(Data("bench : \(error)\n".utf8))
            return 1
        }
    }

    // MARK: - La suite

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la porte d'écriture (S47) ──\n")
        unite(t)
        deuxProcessus(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: unité — le cœur sur write injecté

    private static func unite(_ t: Tally) {
        print("· Le cœur, sur write injecté")
        let octets = Array("abcdefghij".utf8)   // 10 octets

        // 1 — Un write généreux : un seul appel suffit.
        var recus: [UInt8] = []
        var r = AppendOnlyLog.ecrireTout(octets) { p, n in
            recus.append(contentsOf: UnsafeRawBufferPointer(start: p, count: n))
            return n
        }
        check(t, "write intégral — un appel, tout écrit",
              r == .succes(appels: 1) && recus == octets)

        // 2 — LE test qui garde la boucle : un octet par appel. Sans la boucle,
        //     un seul octet serait écrit et « appels » vaudrait 1.
        recus = []
        r = AppendOnlyLog.ecrireTout(octets) { p, _ in
            recus.append(p.load(as: UInt8.self))
            return 1
        }
        check(t, "écriture courte — la boucle reprend jusqu'au bout",
              r == .succes(appels: 10) && recus == octets,
              "10 appels attendus")

        // 3 — EINTR une fois sur deux : repris sans perte ni double.
        recus = []
        var tour = 0
        r = AppendOnlyLog.ecrireTout(octets) { p, _ in
            tour += 1
            if tour % 2 == 1 { errno = EINTR; return -1 }
            recus.append(p.load(as: UInt8.self))
            return 1
        }
        check(t, "EINTR — repris sans rien perdre ni doubler",
              r == .succes(appels: 10) && recus == octets)

        // 4 — Une vraie erreur est rendue telle quelle, avec son errno.
        r = AppendOnlyLog.ecrireTout(octets) { _, _ in errno = ENOSPC; return -1 }
        check(t, "ENOSPC — l'erreur remonte nommée", r == .echec(errno: ENOSPC))

        // 5 — Un write à zéro octet de progrès ne boucle pas éternellement.
        r = AppendOnlyLog.ecrireTout(octets) { _, _ in 0 }
        check(t, "progrès nul — refusé plutôt que boucle infinie",
              r == .echec(errno: EIO))
    }

    // MARK: deux processus — le banc réel

    private static func deuxProcessus(_ t: Tally) {
        print("\n· Deux processus, un fichier")
        let lignes = 2000, taille = 4096

        let fichier = FileManager.default.temporaryDirectory
            .appendingPathComponent("append-bench-\(getpid()).jsonl")
        try? FileManager.default.removeItem(at: fichier)
        defer { try? FileManager.default.removeItem(at: fichier) }

        let binaire = URL(fileURLWithPath: CommandLine.arguments[0])
        var enfants: [Process] = []
        for _ in 0..<2 {
            let p = Process()
            p.executableURL = binaire
            p.arguments = ["--append-bench", fichier.path, "\(lignes)", "\(taille)"]
            do { try p.run() } catch {
                check(t, "lancement des deux enfants", false, "\(error)"); return
            }
            enfants.append(p)
        }
        enfants.forEach { $0.waitUntilExit() }
        check(t, "les deux enfants sortent en 0",
              enfants.allSatisfy { $0.terminationStatus == 0 },
              "\(enfants.map(\.terminationStatus))")

        guard let data = try? Data(contentsOf: fichier),
              let texte = String(data: data, encoding: .utf8) else {
            check(t, "le fichier se relit", false); return
        }

        // Le dépouillement. Chaque ligne doit être EXACTEMENT
        // « <pid> <seq> xxxx… » de `taille` octets — toute rupture, fusion ou
        // entrelacement casse au moins une de ces propriétés.
        let brutes = texte.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        check(t, "4 000 lignes, ni plus ni moins", brutes.count == 2 * lignes,
              "\(brutes.count)")

        var parPid: [String: Set<Int>] = [:]
        var malFormees = 0, mauvaiseTaille = 0
        for l in brutes {
            if l.utf8.count != taille - 1 { mauvaiseTaille += 1; continue }
            let champs = l.split(separator: " ", maxSplits: 2)
            guard champs.count == 3, let seq = Int(champs[1]),
                  champs[2].allSatisfy({ $0 == "x" }) else { malFormees += 1; continue }
            parPid[String(champs[0]), default: []].insert(seq)
        }
        check(t, "chaque ligne fait exactement \(taille) octets", mauvaiseTaille == 0,
              "\(mauvaiseTaille) en défaut")
        check(t, "aucune ligne entrelacée ou déchirée", malFormees == 0,
              "\(malFormees) mal formée(s)")

        // Le REFUS du mono-processus : flock est par description de fichier
        // ouverte — un seul processus se verrouillerait avec lui-même et le test
        // passerait au vert sans avoir rien prouvé.
        check(t, "DEUX processus distincts ont écrit — le mono-processus est refusé",
              parPid.count == 2, "\(parPid.count) PID vu(s) : \(parPid.keys.sorted())")

        for (pid, seqs) in parPid.sorted(by: { $0.key < $1.key }) {
            check(t, "pid \(pid) — ses \(lignes) séquences sont toutes là",
                  seqs == Set(0..<lignes),
                  seqs.count == lignes ? "" : "\(lignes - seqs.count) manquante(s)")
        }
    }
}
