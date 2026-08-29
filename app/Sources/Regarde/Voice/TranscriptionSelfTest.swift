import AVFoundation
import CoreMedia
import Foundation
import Speech

// ─────────────────────────────────────────────────────────────────────────────
// L'autotest de la chaîne — S62
//
// PUR par défaut : les deux tampons, l'extraction des mots, la timeline en
// échantillons entiers avec sa contre-épreuve flottante. Et un BANC à la
// demande — `--transcription-bench <fichier>` — qui rejoue un fichier au
// temps réel à travers l'actor, exactement comme le tap le fera, et doit
// rendre ce que Tools/lot5-dictee.swift rend sur le même fichier.
// ─────────────────────────────────────────────────────────────────────────────

enum TranscriptionSelfTest {

    final class Tally { var passed = 0; var failed = 0 }

    static func check(_ t: Tally, _ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { t.passed += 1; print("  ✓ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
        else { t.failed += 1; print("  ✗ \(label)" + (detail.isEmpty ? "" : "  \(detail)")) }
    }

    static func run() -> Bool {
        let t = Tally()
        print("── Autotest de la transcription (S62) ──\n")
        tampons(t)
        mots(t)
        timeline(t)
        transcript(t)
        print("\n── \(t.passed) vérifications passées, \(t.failed) échouées ──")
        return t.failed == 0
    }

    // MARK: - Les deux tampons

    private static func tampons(_ t: Tally) {
        print("· La règle des deux tampons — le final ajoute, le volatil remplace")
        var tp = TamponsDeTexte()
        tp.recevoir(final: false, texte: "compos")
        tp.recevoir(final: false, texte: "composant")
        tp.recevoir(final: false, texte: "composant checkout")
        check(t, "trois volatils : le tampon porte le DERNIER, entier",
              tp.volatil == "composant checkout")
        check(t, "…et ne contient pas le premier — jamais concaténé, la contre-épreuve",
              !(tp.volatil ?? "").hasPrefix("compos composant"))
        check(t, "aucun final encore", tp.finaux.isEmpty)
        tp.recevoir(final: true, texte: "Le composant Checkout est mal aligné.")
        check(t, "un final s'ajoute ET vide le volatil",
              tp.finaux == ["Le composant Checkout est mal aligné."] && tp.volatil == nil)
        tp.recevoir(final: false, texte: "ensuite")
        tp.recevoir(final: true, texte: "Ensuite le padding.")
        check(t, "les finaux s'accumulent dans l'ordre",
              tp.finaux == ["Le composant Checkout est mal aligné.", "Ensuite le padding."])
    }

    // MARK: - Les mots

    private static func mots(_ t: Tally) {
        print("\n· L'extraction des mots, confiance et plage par passe")
        var bonjour = AttributedString("Bonjour")
        bonjour.transcriptionConfidence = 0.91
        bonjour.audioTimeRange = CMTimeRange(start: CMTime(seconds: 12.0, preferredTimescale: 90_000),
                                             end: CMTime(seconds: 12.4, preferredTimescale: 90_000))
        var pratique = AttributedString(" pratique")
        pratique.transcriptionConfidence = 0.41
        pratique.audioTimeRange = CMTimeRange(start: CMTime(seconds: 12.5, preferredTimescale: 90_000),
                                              end: CMTime(seconds: 12.9, preferredTimescale: 90_000))
        let sansPlage = AttributedString(" !")
        let texte = bonjour + pratique + sansPlage

        let mots = TamponsDeTexte.mots(depuis: texte)
        check(t, "deux mots datés, la passe sans plage ignorée", mots.count == 2, "\(mots.count)")
        check(t, "le texte est nettoyé de son espace de tête",
              mots.map(\.texte) == ["Bonjour", "pratique"])
        check(t, "la confiance traverse — 0,41 sous le seuil du lexique",
              mots.count == 2 && mots[1].confiance.map { abs($0 - 0.41) < 0.001 } == true)
        check(t, "la plage devient du temps de session, au tick près",
              mots.count == 2 && abs(mots[0].debut.seconds - 12.0) < 0.0001
                && abs(mots[1].fin.seconds - 12.9) < 0.0001)

        let segment = SegmentDeParole(mots: mots, texte: "Bonjour pratique !",
                                      plageDebut: SessionTime(seconds: 11.9),
                                      plageFin: SessionTime(seconds: 13))
        check(t, "l'onset est le PREMIER MOT, pas la plage du moteur",
              abs(segment.onset.seconds - 12.0) < 0.0001)
        var edite = segment
        edite.texte = "Bonjour padding !"
        check(t, "éditer le texte ne touche jamais le brut",
              edite.texteBrut == "Bonjour pratique !" && edite.texte == "Bonjour padding !")
        let vide = SegmentDeParole(mots: [], texte: "…",
                                   plageDebut: SessionTime(seconds: 5), plageFin: SessionTime(seconds: 6))
        check(t, "sans mot daté, l'onset retombe sur la plage du moteur",
              abs(vide.onset.seconds - 5) < 0.0001)

        // Le rattachement voyage avec le segment — au tick près, encodé/relu.
        do {
            var rattache = segment
            rattache.attachement = .marque(3, regle: .debordement)
            let data = try JSONEncoder().encode(rattache)
            let relu = try JSONDecoder().decode(SegmentDeParole.self, from: data)
            check(t, "un segment rattaché se relit identique, règle comprise",
                  relu == rattache && relu.attachement == .marque(3, regle: .debordement))
            var global = segment
            global.attachement = .global(regle: .gesteGlobal)
            let relu2 = try JSONDecoder().decode(SegmentDeParole.self, from: JSONEncoder().encode(global))
            check(t, "un segment global aussi", relu2.attachement == .global(regle: .gesteGlobal))
        } catch {
            check(t, "aller-retour Codable du segment", false, "\(error)")
        }
    }

    // MARK: - La timeline

    private static func timeline(_ t: Tally) {
        print("\n· La timeline en échantillons entiers — monotone à travers les fenêtres")
        let cadence = 16_000.0
        let f1 = TamponsDeTexte.bufferStartTime(origine: SessionTime(seconds: 10),
                                                echantillonsSortis: 0, cadence: cadence)
        let f1b = TamponsDeTexte.bufferStartTime(origine: SessionTime(seconds: 10),
                                                 echantillonsSortis: 7_000, cadence: cadence)
        let f2 = TamponsDeTexte.bufferStartTime(origine: SessionTime(seconds: 30),
                                                echantillonsSortis: 0, cadence: cadence)
        check(t, "fenêtre à 10 s → 160 000 échantillons à 16 kHz, exactement",
              f1.value == 160_000 && f1.timescale == 16_000)
        check(t, "7 000 échantillons plus loin → 167 000, pas 167 000,0000001",
              f1b.value == 167_000)
        check(t, "fenêtre à 30 s → 480 000 : strictement croissant, discontinu",
              f2.value == 480_000 && CMTimeCompare(f2, f1b) > 0)

        // La contre-épreuve du harnais : des secondes flottantes arrondies à une
        // échelle qui n'est pas celle des échantillons (90 000 n'est pas un
        // multiple de 16 000) tombent, une fois sur deux, AVANT l'instant exact
        // de l'échantillon — c'est « timestamp overlaps or precedes prior
        // audio input », l'erreur que le moteur a rendue au harnais de S59.
        // Des buffers de 7 001 échantillons (0,4375625 s, non dyadique) le
        // montrent ; en échantillons entiers, l'instant est exact par
        // construction et ne précède jamais.
        var secondes = 0.0
        var precedent = 0
        var sortis: Int64 = 0
        for _ in 0..<1_000 {
            let flottant = CMTime(seconds: secondes, preferredTimescale: 90_000)
            let exact = TamponsDeTexte.bufferStartTime(origine: SessionTime(seconds: 0),
                                                       echantillonsSortis: sortis, cadence: cadence)
            if CMTimeCompare(flottant, exact) < 0 { precedent += 1 }
            secondes += 7_001 / cadence
            sortis += 7_001
        }
        check(t, "en secondes flottantes à 90 000, des buffers PRÉCÈDENT l'échantillon exact",
              precedent > 0, "\(precedent) sur 1 000")
        check(t, "…en échantillons entiers, jamais : 1 000 × 7 001 exactement",
              sortis == 7_001_000
                && TamponsDeTexte.bufferStartTime(origine: SessionTime(seconds: 0),
                                                  echantillonsSortis: sortis,
                                                  cadence: cadence).value == 7_001_000)
    }

    // MARK: - Le banc

    /// `--transcription-bench <fichier>` : le fichier, au temps réel, à
    /// travers l'actor — le même chemin que le tap. Rend vrai si le drain a
    /// rendu au moins un segment.
    static func banc(fichier chemin: String) async -> Bool {
        do {
            let transcripteur = Transcripteur()
            let format = try await transcripteur.preparer()
            let fichier = try AVAudioFile(forReading: URL(fileURLWithPath: chemin))
            guard let converter = AVAudioConverter(from: fichier.processingFormat, to: format) else {
                print("✗ conversion impossible"); return false
            }
            print("· \(chemin) — \(String(format: "%.1f", Double(fichier.length) / fichier.processingFormat.sampleRate)) s, au temps réel\n")

            await transcripteur.brancher(
                surVolatil: { t in print(String(format: "  volatil  · parole jusqu'à %6.2f", t.seconds)) },
                surFinal: { s in print(String(format: "  FINAL    · [%6.2f → %6.2f]  %@", s.onset.seconds, s.fin.seconds, s.texte)) })
            try await transcripteur.ouvrirFenetre(origine: SessionTime(seconds: 0))

            let parBuffer = AVAudioFrameCount(fichier.processingFormat.sampleRate / 2)
            var sortis: Int64 = 0
            while fichier.framePosition < fichier.length {
                guard let brut = AVAudioPCMBuffer(pcmFormat: fichier.processingFormat,
                                                  frameCapacity: parBuffer) else { break }
                try fichier.read(into: brut, frameCount: parBuffer)
                guard brut.frameLength > 0 else { break }
                let ratio = format.sampleRate / fichier.processingFormat.sampleRate
                let capacite = AVAudioFrameCount(Double(brut.frameLength) * ratio) + 64
                guard let converti = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacite) else { break }
                var erreur: NSError?
                let source = SourceAudioUnique(brut)
                converter.convert(to: converti, error: &erreur) { _, statut in source.servir(statut) }
                if let erreur { throw erreur }
                transcripteur.recevoir(TrancheAudio(buffer: converti, premierEchantillon: sortis,
                                                    hostTime: SessionClock.hostTicksNow(), hostTimeValide: true))
                sortis += Int64(converti.frameLength)
                let duree = Double(brut.frameLength) / fichier.processingFormat.sampleRate
                try await Task.sleep(nanoseconds: UInt64(duree * 1_000_000_000))
            }
            let segments = try await transcripteur.drainer()
            print("\n── \(segments.count) segment(s) après drain ──")
            for (i, s) in segments.enumerated() {
                print(String(format: "%2d · [%6.2f → %6.2f]  %@", i + 1, s.onset.seconds, s.fin.seconds, s.texte))
                for m in s.mots where (m.confiance ?? 1) < 0.6 {
                    print(String(format: "      ⚠ confiance %.2f : « %@ »", m.confiance ?? 0, m.texte))
                }
            }
            return !segments.isEmpty
        } catch {
            print("✗ \(error)")
            return false
        }
    }

    // MARK: - La ligne du transcript (S66), pure

    private static func transcript(_ t: Tally) {
        print("\n· La ligne de transcript.txt — lot5-seuils § 3")
        var s = SegmentDeParole(mots: [], texte: "Il manque du pratique à droite.",
                                plageDebut: SessionTime(seconds: 26.9),
                                plageFin: SessionTime(seconds: 31.5))
        s.attachement = .marque(2, regle: .fenetreDeParole)
        check(t, "sans premier mot affiné : le temps est le début de plage",
              Transcript.ligne(s) == "[00:26.9] (marque 2) Il manque du pratique à droite.")
        s.premierMot = SessionTime(seconds: 87.02)
        check(t, "le premier mot affiné l'emporte, en MM:SS.d",
              Transcript.ligne(s) == "[01:27.0] (marque 2) Il manque du pratique à droite.")
        s.texte = "Il manque du padding à droite."
        check(t, "le texte édité ne change PAS la ligne — le brut seul",
              Transcript.ligne(s).hasSuffix("Il manque du pratique à droite."))
        s.attachement = .global(regle: .gesteGlobal)
        check(t, "global en session → (global) ; en éclair → (éclair)",
              Transcript.ligne(s).contains("(global)")
                && Transcript.ligne(s, contexte: .eclair).contains("(éclair)"))
        let dossier = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-test-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        check(t, "rien à dire → aucun fichier, et nil pour le dire",
              (try? Transcript.ecrire([], dans: dossier)) == nil
                && !FileManager.default.fileExists(atPath: dossier.appendingPathComponent("transcript.txt").path))
    }
}
