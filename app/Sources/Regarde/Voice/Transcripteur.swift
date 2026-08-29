import AVFoundation
import CoreMedia
import Foundation
import os
import Speech

// ─────────────────────────────────────────────────────────────────────────────
// Le transcripteur — S62, spécification § 7.1 et § 7.2, ADR-0012
//
// La chaîne exacte de la spec : `fr-FR` résolue par `supportedLocale`,
// `SpeechTranscriber` progressif indexé dans le temps avec confiance par
// mot, `SpeechDetector` présent — gardé en DÉFENSE EN PROFONDEUR : sur
// macOS 26.1 le harnais de S59 a montré que la segmentation tient sans lui,
// mais l'ADR le voulait obligatoire et une régression système le rendrait à
// nouveau nécessaire, sans note. Le modèle est installé sans condition (un
// no-op quand il est là), aucune permission de reconnaissance vocale n'est
// déclarée (fait de sonde n°3).
//
// L'audio arrive AU FIL DE L'EAU par `recevoir` — depuis le tap micro, jamais
// depuis une file de rattrapage — et porte le temps de session via
// `bufferStartTime`, en échantillons entiers sortis du converter.
//
// Une analyse par FENÊTRE de parole : `ouvrirFenetre` crée les modules et
// l'analyseur, `drainer` les finit — le drain COMPLET, jamais coupé : les
// résultats finaux arrivent 1,3 à 2,7 s après la fin de la parole, et couper
// avant perd la conclusion de chaque commentaire (lot5-seuils § 1 n°5). Un
// `ConfigurationChange` en pleine fenêtre reconstruit le MOTEUR AUDIO (S61),
// jamais l'analyseur en cours.
// ─────────────────────────────────────────────────────────────────────────────

actor Transcripteur: PuitsAudio {

    private static let log = Logger(subsystem: logSubsystem, category: "transcription")

    enum Erreur: Error, CustomStringConvertible {
        case localeAbsente
        case formatAbsent
        case fenetreDejaOuverte
        case aucuneFenetre

        var description: String {
            switch self {
            case .localeAbsente: "fr-FR n'est pas prise en charge sur cette machine"
            case .formatAbsent: "aucun format audio compatible avec le transcripteur"
            case .fenetreDejaOuverte: "une fenêtre de transcription est déjà ouverte"
            case .aucuneFenetre: "aucune fenêtre de transcription ouverte"
            }
        }
    }

    // MARK: - Ce qui vit le temps d'une session

    private var locale: Locale?
    private var format: AVAudioFormat?
    private var surVolatil: (@Sendable (SessionTime) -> Void)?
    private var surFinal: (@Sendable (SegmentDeParole) -> Void)?

    // MARK: - Ce qui vit le temps d'une fenêtre

    private var analyzer: SpeechAnalyzer?
    private var analyse: Task<Void, Error>?
    private var collecte: Task<[SegmentDeParole], Error>?
    private var tampons = TamponsDeTexte()
    /// Le diagnostic du drain : combien de volatils, et le dernier — c'est ce
    /// qui distingue « le moteur n'a rien entendu » de « il n'a pas fini ».
    private var volatilsVus = 0
    private var dernierVolatil: (texte: String, instant: SessionTime)?

    /// Le côté « non isolé » de la fenêtre : `recevoir` est appelé du tap
    /// audio, sans attente possible — il lit la continuation et l'origine sous
    /// un verrou, et pousse. Rien d'autre ne traverse.
    private struct Entree {
        var continuation: AsyncStream<AnalyzerInput>.Continuation?
        var origine = SessionTime(seconds: 0)
        var cadence = 16_000.0
    }
    private nonisolated let entree = OSAllocatedUnfairLock(initialState: Entree())

    init() {}

    func brancher(surVolatil: (@Sendable (SessionTime) -> Void)?,
                  surFinal: (@Sendable (SegmentDeParole) -> Void)?) {
        self.surVolatil = surVolatil
        self.surFinal = surFinal
    }

    // MARK: - Préparation, une fois par session

    /// Résout la locale, installe le modèle, découvre le format que le moteur
    /// veut — c'est CE format que le micro devra livrer (Voice/Audio.swift).
    func preparer() async throws -> AVAudioFormat {
        if let format { return format }
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "fr-FR")) else {
            throw Erreur.localeAbsente
        }
        self.locale = locale
        let sonde = Self.transcripteur(locale: locale)
        if let demande = try await AssetInventory.assetInstallationRequest(supporting: [sonde]) {
            Journal.event(.system, "transcription — installation du modèle fr-FR")
            try await demande.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [sonde]) else {
            throw Erreur.formatAbsent
        }
        self.format = format
        entree.withLock { $0.cadence = format.sampleRate }
        Journal.event(.system, "transcription — prête, \(locale.identifier), "
                      + "\(Int(format.sampleRate)) Hz \(format.channelCount == 1 ? "mono" : "stéréo")")
        return format
    }

    private static func transcripteur(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                          transcriptionOptions: [],
                          reportingOptions: [.volatileResults],
                          attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }

    // MARK: - Une fenêtre

    /// Ouvre une fenêtre de transcription dont l'audio commencera à `origine`
    /// (temps de session). Les résultats partent aux rappels au fil de l'eau.
    func ouvrirFenetre(origine: SessionTime) async throws {
        guard analyzer == nil else { throw Erreur.fenetreDejaOuverte }
        if locale == nil { _ = try await preparer() }
        guard let locale else { throw Erreur.localeAbsente }

        let transcriber = Self.transcripteur(locale: locale)
        // SANS SpeechDetector, par décision mesurée (lot5-seuils § 10) : sur
        // macOS 26.1 il ne segmente rien de plus (S59, trois modes identiques)
        // et, face au bruit réel d'un micro, il AVALE toute énonciation après
        // la première finale — un monologue verrouillé perdait sa seconde
        // phrase, retrouvée intacte sans lui. ADR-0012 le disait obligatoire
        // sur un macOS antérieur ; `--avec-detecteur` au lancement le remet,
        // pour re-vérifier à chaque mise à jour système.
        var modules: [any SpeechModule] = [transcriber]
        if CommandLine.arguments.contains("--avec-detecteur") {
            modules.append(SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium),
                                          reportResults: false))
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        self.analyzer = analyzer
        tampons = TamponsDeTexte()
        volatilsVus = 0
        dernierVolatil = nil

        let (flux, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        entree.withLock {
            $0.continuation = continuation
            $0.origine = origine
        }

        // La collecte applique la règle des deux tampons et prévient : un
        // volatil dit « la parole continue » à la machine (son instant est la
        // FIN de la plage — le dernier audio couvert —, pas son début, qui ne
        // bouge pas pendant une phrase et ne prolongerait rien) ; un final
        // devient un segment.
        collecte = Task { [weak self] () -> [SegmentDeParole] in
            var finaux: [SegmentDeParole] = []
            for try await resultat in transcriber.results {
                guard let self else { break }
                let texte = String(resultat.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if resultat.isFinal {
                    guard !texte.isEmpty else { continue }
                    let segment = SegmentDeParole(
                        mots: TamponsDeTexte.mots(depuis: resultat.text),
                        texte: texte,
                        plageDebut: SessionTime(resultat.range.start),
                        plageFin: SessionTime(resultat.range.end))
                    finaux.append(segment)
                    await self.noter(final: true, texte: texte, segment: segment)
                } else {
                    await self.noter(final: false, texte: texte,
                                     instant: SessionTime(resultat.range.end))
                }
            }
            return finaux
        }
        analyse = Task { try await analyzer.start(inputSequence: flux) }
        Journal.event(.system, "transcription — fenêtre ouverte à \(origine), \(locale.identifier)")
    }

    private func noter(final: Bool, texte: String,
                       segment: SegmentDeParole? = nil, instant: SessionTime? = nil) {
        tampons.recevoir(final: final, texte: texte)
        if final, let segment {
            let premier = segment.mots.first.map { "premier mot « \($0.texte) » à \($0.debut)" } ?? "AUCUN mot horodaté"
            Journal.event(.system, "transcription — final [\(segment.plageDebut) → \(segment.plageFin)] \(segment.mots.count) mot(s), \(premier) « \(texte) »")
            surFinal?(segment)
        }
        if !final, let instant {
            volatilsVus += 1
            if volatilsVus == 1 {
                // La latence du PREMIER volatile décide si « aucun volatile
                // depuis l'ouverture » est un critère tenable à 0,8 s.
                Journal.event(.system, "transcription — premier volatil à \(SessionClock.shared.now()) (audio \(instant)) « \(texte) »")
            }
            dernierVolatil = (texte, instant)
            surVolatil?(instant)
        }
    }

    /// Du tap, sans attente : la tranche part au moteur avec son temps de
    /// session. Une tranche hors fenêtre est perdue — et comptée par le tap,
    /// pas ici.
    nonisolated func recevoir(_ tranche: TrancheAudio) {
        let (continuation, temps) = entree.withLock { e -> (AsyncStream<AnalyzerInput>.Continuation?, CMTime) in
            (e.continuation,
                    TamponsDeTexte.bufferStartTime(origine: e.origine,
                                                   echantillonsSortis: tranche.premierEchantillon,
                                                   cadence: e.cadence))
        }
        continuation?.yield(AnalyzerInput(buffer: tranche.buffer, bufferStartTime: temps))
    }

    /// Le drain COMPLET : fin du flux, finalisation à travers la fin de
    /// l'entrée, attente des derniers finaux. Rend les segments de la fenêtre.
    func drainer() async throws -> [SegmentDeParole] {
        guard let analyzer, let analyse, let collecte else { throw Erreur.aucuneFenetre }
        let depart = SessionClock.hostTicksNow()
        Journal.event(.system, "transcription — drain demandé à \(SessionClock.shared.now())")
        entree.withLock { $0.continuation?.finish(); $0.continuation = nil }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await analyse.value
        let segments = try await collecte.value
        self.analyzer = nil
        self.analyse = nil
        self.collecte = nil
        let duree = SessionClock.millis(from: depart, to: SessionClock.hostTicksNow())
        Journal.event(.system, String(format: "transcription — %d segment(s), drain %.0f ms · %d volatil(s)",
                                      segments.count, duree, volatilsVus)
                      + (dernierVolatil.map { " · dernier « \($0.texte.suffix(50)) » à \($0.instant)" } ?? ""))
        volatilsVus = 0
        dernierVolatil = nil
        return segments
    }

    var fenetreOuverte: Bool { analyzer != nil }
}
