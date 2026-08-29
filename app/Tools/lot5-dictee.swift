// ─────────────────────────────────────────────────────────────────────────────
// La mesure qui décide du lot 5 — § 10.1 du plan, session S59
//
// Un outil en ligne de commande qui lit un fichier audio et le passe dans la
// configuration EXACTE du lot 5 (§ 7.1) : fr-FR, transcription progressive
// indexée dans le temps, SpeechDetector présent, confiance par mot.
//
//   swift Tools/lot5-dictee.swift dictee.m4a                 la mesure
//   swift Tools/lot5-dictee.swift dictee.m4a --sans-detector fait de sonde n°1
//   swift Tools/lot5-dictee.swift dictee.m4a --vite          fait de sonde n°2
//
// Les deux drapeaux existent pour REPRODUIRE les faits de sonde d'ADR-0012
// plutôt que les croire sur parole : sans SpeechDetector, tout revient en un
// unique résultat final ; alimenté plus vite que le temps réel, la
// segmentation s'effondre. Le mode nominal pousse l'audio AU FIL DE L'EAU,
// buffer par buffer, au rythme du temps réel — comme le tap micro le fera.
//
// Le comptage final (termes techniques prononcés / corrects / erreurs
// PLAUSIBLES) reste humain : l'outil affiche les segments, les temps et les
// mots de confiance basse ; la table de décision du § 10.1 fait le reste.
// ─────────────────────────────────────────────────────────────────────────────

import AVFoundation
import Foundation
import Speech

@main
struct Dictee {
    static func main() async {
        do { try await mesurer() } catch {
            print("✗ \(error)")
            exit(1)
        }
    }

    static func mesurer() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            print("usage : swift lot5-dictee.swift <fichier-audio> [--sans-detector] [--vite]")
            exit(2)
        }
        let cheminAudio = arguments[1]
        let sansDetector = arguments.contains("--sans-detector")
        let vite = arguments.contains("--vite")

        // La locale du lot, résolue comme la spec l'écrit — jamais un
        // identifiant en dur qui raterait fr_FR@rg=…
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "fr-FR")) else {
            print("✗ fr-FR n'est pas prise en charge sur cette machine")
            exit(1)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence])

        // Le détecteur agit par sa seule PRÉSENCE dans les modules — c'est le
        // fait non documenté que --sans-detector rend visible.
        var modules: [any SpeechModule] = [transcriber]
        if !sansDetector {
            modules.append(SpeechDetector(
                detectionOptions: .init(sensitivityLevel: .medium),
                reportResults: false))
        }

        // Le modèle fr-FR, installé sans condition — un no-op s'il est là.
        if let demande = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]) {
            print("· téléchargement du modèle fr-FR…")
            try await demande.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: modules)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]) else {
            print("✗ aucun format audio compatible")
            exit(1)
        }

        let fichier = try AVAudioFile(forReading: URL(fileURLWithPath: cheminAudio))
        let dureeTotale = Double(fichier.length) / fichier.processingFormat.sampleRate
        print("· \(cheminAudio) — \(String(format: "%.1f", dureeTotale)) s, "
              + "poussé \(vite ? "PLUS VITE que le temps réel" : "au fil de l'eau")"
              + (sansDetector ? ", SANS SpeechDetector" : ""))

        // Le converter est créé UNE FOIS, hors de la boucle — la règle du tap.
        guard let converter = AVAudioConverter(from: fichier.processingFormat, to: format) else {
            print("✗ conversion \(fichier.processingFormat) → \(format) impossible")
            exit(1)
        }

        let (flux, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        async let analyse: () = analyzer.start(inputSequence: flux)

        // La collecte des résultats, en parallèle de la poussée.
        let volatils = arguments.contains("--volatils")
        let depart = Date()
        let collecte = Task { () -> [(plage: CMTimeRange, texte: AttributedString)] in
            var finals: [(CMTimeRange, AttributedString)] = []
            for try await resultat in transcriber.results {
                if volatils {
                    // L'horloge murale à côté du temps audio : un résultat
                    // « progressif » qui arrive à la fin n'est pas progressif.
                    let genre = resultat.isFinal ? "FINAL   " : "volatil "
                    let mur = Date().timeIntervalSince(depart)
                    print("  \(genre) mur \(String(format: "%5.1f", mur)) s · audio [\(String(format: "%6.2f", resultat.range.start.seconds)) → \(String(format: "%6.2f", resultat.range.end.seconds))] "
                          + String(resultat.text.characters.prefix(40)))
                }
                if resultat.isFinal { finals.append((resultat.range, resultat.text)) }
            }
            return finals
        }

        // Poussée buffer par buffer — un demi-seconde d'audio à la fois.
        let parBuffer = AVAudioFrameCount(fichier.processingFormat.sampleRate / 2)
        var echantillonsSortis: Int64 = 0
        while fichier.framePosition < fichier.length {
            guard let brut = AVAudioPCMBuffer(pcmFormat: fichier.processingFormat,
                                              frameCapacity: parBuffer) else { break }
            try fichier.read(into: brut, frameCount: parBuffer)
            guard brut.frameLength > 0 else { break }

            let ratio = format.sampleRate / fichier.processingFormat.sampleRate
            let capacite = AVAudioFrameCount(Double(brut.frameLength) * ratio) + 64
            guard let converti = AVAudioPCMBuffer(pcmFormat: format,
                                                  frameCapacity: capacite) else { break }
            var erreur: NSError?
            var donne = false
            converter.convert(to: converti, error: &erreur) { _, statut in
                if donne { statut.pointee = .noDataNow; return nil }
                donne = true; statut.pointee = .haveData; return brut
            }
            if let erreur { throw erreur }

            // Le temps déclaré suit les échantillons SORTIS du converter, pas
            // les entrants : la conversion de cadence retient des résidus, et
            // un temps calculé côté entrée dérive de ce qui est réellement
            // livré — le moteur voit alors des trous et hache les mots. Et il
            // se compte en ÉCHANTILLONS entiers : une somme de secondes
            // flottantes arrondie en CMTime chevauche d'un tick, et le moteur
            // refuse (« timestamp overlaps or precedes prior audio input »).
            continuation.yield(AnalyzerInput(
                buffer: converti,
                bufferStartTime: CMTime(value: CMTimeValue(echantillonsSortis),
                                        timescale: CMTimeScale(format.sampleRate))))
            echantillonsSortis += Int64(converti.frameLength)
            let duree = Double(brut.frameLength) / fichier.processingFormat.sampleRate

            // LE point de la mesure : au rythme du vrai temps, sauf --vite.
            if !vite { try await Task.sleep(nanoseconds: UInt64(duree * 1_000_000_000)) }
        }
        continuation.finish()

        // Le drain COMPLET — les finaux arrivent 1,3 à 2,7 s après la parole.
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await analyse
        let finals = try await collecte.value

        // ── Le rapport ──
        print("\n── \(finals.count) segment(s) final(aux) ──\n")
        var motsBasse = 0, mots = 0
        for (i, (plage, texte)) in finals.enumerated() {
            let debut = plage.start.seconds, fin = plage.end.seconds
            print(String(format: "%2d · [%6.2f → %6.2f]  %@",
                         i + 1, debut, fin, String(texte.characters)))
            // Les mots de confiance basse, candidats du lexique (< 0,6).
            for passe in texte.runs {
                mots += 1
                if let confiance = passe.transcriptionConfidence, confiance < 0.6 {
                    motsBasse += 1
                    let fragment = String(texte[passe.range].characters)
                        .trimmingCharacters(in: .whitespaces)
                    if !fragment.isEmpty {
                        print(String(format: "      ⚠ confiance %.2f : « %@ »",
                                     confiance, fragment))
                    }
                }
            }
        }
        print("\n── comptage machine ──")
        print("  segments finaux        \(finals.count)")
        print("  passes de texte        \(mots), dont \(motsBasse) sous 0,6")
        print("\n── comptage HUMAIN (table § 10.1, réconciliée : 4/5) ──")
        print("  1. termes techniques prononcés   : à compter à l'écoute")
        print("  2. correctement transcrits       : à compter ci-dessus")
        print("  3. erreurs PLAUSIBLES            : un mot faux qui se lit comme")
        print("     du français valide — indétectable par la confiance")
        print("  → plus de 4/5 corrects : lot tel que spécifié ;")
        print("    entre 1/3 et 4/5 : le clavier passe devant, +1 j ;")
        print("    moins de 1/3 : re-cadrage clavier-d'abord.")
    }
}
