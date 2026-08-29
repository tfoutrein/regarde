import AVFoundation
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest du micro — S61
//
// Sans matériel par défaut : le choix du périphérique et la somme de latence
// sont des fonctions pures, jugées sur les cas réellement rencontrés — le
// pilote de boucle de Teams est sur cette machine. La partie VIVANTE ne se
// joue que sur demande (`--vivant`) et si la permission est déjà accordée :
// un autotest ne déclenche jamais l'invite micro, c'est S72 qui la place au
// bon moment.
// ─────────────────────────────────────────────────────────────────────────────

enum MicroSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest du micro (S61) ──\n")
        selection(t)
        latence(t)
        constat()
        vivant(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - Le choix, pur

    private static func selection(_ t: Tally) {
        print("· Le choix du périphérique — jamais l'entrée par défaut")
        typealias C = Peripheriques.Candidat
        let teams = C(uid: "MSLoopbackDriverDevice_UID", nom: "Microsoft Teams Audio", interne: false)
        let blackhole = C(uid: "BlackHole2ch_UID", nom: "BlackHole 2ch", interne: false)
        let agrege = C(uid: "~:AMS2_Aggregate:0", nom: "Aggregate Device", interne: false)
        let interne = C(uid: "BuiltInMicrophoneDevice", nom: "Micro MacBook Pro", interne: true)
        let casque = C(uid: "AppleUSBAudioEngine:…", nom: "AirPods Pro", interne: false)

        check(t, "Teams, BlackHole, agrégé, interne → l'interne gagne",
              Peripheriques.choisir(parmi: [teams, blackhole, agrege, interne]) == interne)
        check(t, "l'interne gagne même listé APRÈS un externe sain",
              Peripheriques.choisir(parmi: [casque, interne]) == interne)
        check(t, "sans interne → le premier externe sain, pas le premier tout court",
              Peripheriques.choisir(parmi: [teams, casque, blackhole]) == casque)
        check(t, "que des boucles → rien : rien vaut mieux qu'un pilote de boucle",
              Peripheriques.choisir(parmi: [teams, blackhole, agrege]) == nil)
        check(t, "liste vide → rien",
              Peripheriques.choisir(parmi: []) == nil)
        // La contre-épreuve : le marqueur « teams » fait le travail. Sans lui,
        // Teams serait choisi — donc l'exclusion n'est pas un effet de bord.
        let sansTeams = Peripheriques.marqueursDeBoucle.filter { $0 != "teams" }
        check(t, "contre-épreuve : retirer le marqueur « teams » ferait choisir Teams",
              Peripheriques.choisir(parmi: [teams, casque], marqueurs: sansTeams) == teams)
        check(t, "la liste des marqueurs est celle du doctor — une seule liste",
              Peripheriques.marqueursDeBoucle.contains("teams")
                && Peripheriques.marqueursDeBoucle.contains("aggregate")
                && Peripheriques.marqueursDeBoucle.count == 9)
    }

    // MARK: - La latence, pure

    private static func latence(_ t: Tally) {
        print("\n· La somme de latence — § 3.6, trois termes")
        let m = LatenceEntree.somme(presentationSecondes: 0.020,
                                    latenceFrames: 128, securiteFrames: 64, cadence: 48_000)
        check(t, "20 ms + 128 frames + 64 frames à 48 kHz = 24,00 ms",
              abs(m.totalMs - 24.0) < 0.01, String(format: "%.3f ms", m.totalMs))
        check(t, "les trois termes restent lisibles séparément",
              abs(m.presentationMs - 20) < 0.001
                && abs(m.peripheriqueMs - 2.6667) < 0.001
                && abs(m.securiteMs - 1.3333) < 0.001)
        // La contre-épreuve du facteur 48 : oublier la cadence rendrait
        // 128 + 64 = 192 « ms », et la ligne de journal serait fausse d'un
        // ordre de grandeur.
        let sansCadence = LatenceEntree.somme(presentationSecondes: 0,
                                              latenceFrames: 128, securiteFrames: 64, cadence: 1000)
        check(t, "contre-épreuve : la cadence divise — à 1 kHz, 192 frames = 192 ms",
              abs(sansCadence.totalMs - 192) < 0.001)
        let airpods = LatenceEntree.somme(presentationSecondes: 0.180,
                                          latenceFrames: 512, securiteFrames: 256, cadence: 48_000)
        check(t, "AirPods (180 ms + 768 frames) → 196 ms : tout le budget d'ancrage",
              airpods.totalMs > 150, String(format: "%.1f ms", airpods.totalMs))
    }

    // MARK: - Le constat, sur la machine réelle

    private static func constat() {
        print("\n· Constat — les périphériques de cette machine")
        let candidats = Peripheriques.candidatsVivants()
        for c in candidats {
            let marque = c.estBoucle() ? "  ← exclu" : (c.interne ? "  ← interne" : "")
            print("    \(c.nom)\(marque)")
        }
        if let choix = Peripheriques.choisir(parmi: candidats) {
            let id = Peripheriques.identifiantCoreAudio(uid: choix.uid)
            print("    → choix : \(choix.nom) (CoreAudio \(id.map(String.init) ?? "?"))")
            if let id {
                let l = LatenceEntree.mesurer(peripherique: id, presentationSecondes: 0)
                print("    → latence hors présentation : \(l.description)")
            }
        } else {
            print("    → aucun périphérique sain")
        }
    }

    // MARK: - Le vivant, sur demande

    private final class Compteur: PuitsAudio, @unchecked Sendable {
        let verrou = OSAllocatedUnfairLock<[(premier: Int64, longueur: Int64)]>(initialState: [])
        func recevoir(_ tranche: TrancheAudio) {
            verrou.withLock { $0.append((tranche.premierEchantillon, Int64(tranche.buffer.frameLength))) }
        }
    }

    private static func vivant(_ t: Tally) {
        print("\n· La partie vivante")
        print("  · entrée par défaut du système : \(Peripheriques.nomDuDefautSysteme() ?? "?")")
        // `--demander` : la seule voie qui déclenche l'invite micro depuis un
        // autotest — explicite, jamais par surprise. Le produit, lui, demande
        // au premier usage réel (S72) ; ici c'est l'auteur qui accorde une
        // fois pour toutes à l'application installée, pour développer.
        if CommandLine.arguments.contains("--vivant"),
           CommandLine.arguments.contains("--demander"),
           AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            print("  · demande d'autorisation micro — cliquez « Autoriser »")
            let attente = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { _ in attente.signal() }
            attente.wait()
        }
        guard CommandLine.arguments.contains("--vivant"),
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            print("  · partie vivante non jouée — --vivant absent ou micro non autorisé (S72)")
            return
        }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                         channels: 1, interleaved: false) else {
            check(t, "format cible 16 kHz mono Int16", false); return
        }
        // Les lignes vivantes vont AUSSI dans un fichier : lancée par
        // LaunchServices (`open --args`), l'application n'a pas de terminal.
        let journalVivant = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Regarde/micro-test.log")
        var lignes: [String] = ["lancement : \(ProcessInfo.processInfo.arguments.joined(separator: " "))"]
        func note(_ l: String) { print(l); lignes.append(l) }

        let compteur = Compteur()
        let resultat: String = MainActor.assumeIsolated {
            let micro = MicroParFenetre()
            do { try micro.ouvrir(format: format, puits: compteur) } catch { return "✗ ouverture : \(error)" }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
            let d = micro.diagnostic
            micro.fermer()
            return d
        }
        let meilleure = compteur.verrou.withLock { $0 }
        note("  · \(meilleure.count) tranche(s) en 1,5 s — \(resultat)")
        try? lignes.joined(separator: "\n").appending("\n").write(to: journalVivant, atomically: true, encoding: .utf8)

        let tranches = meilleure
        check(t, "des tranches sont arrivées en 1,5 s", tranches.count >= 3, "\(tranches.count) tranche(s)")
        check(t, "la première tranche commence à l'échantillon 0",
              tranches.first?.premier == 0)
        var contigu = true
        for i in 1..<max(1, tranches.count) where tranches[i].premier != tranches[i - 1].premier + tranches[i - 1].longueur {
            contigu = false
        }
        check(t, "premierEchantillon strictement croissant et CONTIGU — pas un trou, pas un chevauchement",
              contigu && tranches.count > 1)
    }
}
