import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import CoreMedia
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Le micro par fenêtre — S61, spécification § 7.2, ADR-0011
//
// Le micro est FERMÉ par défaut, et ouvert par fenêtre de parole : une
// session de capture démarrée à l'ouverture, arrêtée à la fermeture. Le prix —
// la latence de démarrage payée à chaque fenêtre — est celui qu'ADR-0011
// assume pour ne jamais capter quinze minutes de bureau ni afficher un point
// orange permanent. Ce fichier ne transcrit rien : il livre des tranches au
// format du moteur, datées en échantillons sortis (Voice/Audio.swift), à qui
// veut bien les recevoir.
//
// POURQUOI AVCaptureSession ET PAS AVAudioEngine — mesuré le 29 août 2026 sur
// macOS 26.1, quatre variantes en vivant : imposer un périphérique à
// l'inputNode d'AVAudioEngine par kAudioOutputUnitProperty_CurrentDevice —
// avant la préparation, entre uninit/init, après la préparation — répond
// « succès » et TUE l'entrée en silence : zéro appel du tap, moteur « en
// marche ». Sans imposition, 15 tranches contiguës. Or « jamais l'entrée par
// défaut » (§ 7.2) n'est pas négociable : quand Teams a fait de son pilote de
// boucle l'entrée par défaut, il faut viser le micro interne. AVCaptureSession
// prend le périphérique par construction (AVCaptureDeviceInput), ne touche
// aucune unité audio, et date chaque buffer sur l'horloge hôte — celle
// d'ADR-0007.
//
// Trois règles qui ne se voient pas dans le code d'un premier jet :
//
//   LE CONVERTER EST CRÉÉ UNE FOIS, hors du rappel, depuis le format actif du
//   périphérique. Le créer par buffer coûte des allocations sur la file audio
//   et perd les résidus de conversion entre deux buffers — les trous qui
//   hachent les mots (lot5-seuils § 2).
//
//   LE RAPPEL N'EST JAMAIS UNE FERMETURE ÉCRITE DANS CETTE CLASSE : @MainActor
//   l'inférerait isolée, et la file audio planterait à l'assertion
//   d'isolation (SIGTRAP dans dispatch_assert_queue_fail — constaté). Le
//   délégué est une classe à part, non isolée, nourrie d'un contexte Sendable.
//
//   LA FERMETURE D'OFFICE n'admet aucune exception (§ 6.3) : saisie sécurisée
//   (un champ de mot de passe prend le focus), veille, verrouillage de
//   l'écran, changement de session — le micro se ferme et la raison remonte.
//   Un déjeuner écran verrouillé ne devient jamais un enregistrement.
// ─────────────────────────────────────────────────────────────────────────────

enum MicroErreur: Error, CustomStringConvertible {
    /// La permission micro n'est pas accordée. On ne la DEMANDE pas ici — S72
    /// le fera au premier usage réel, avec son invite au bon moment.
    case nonAutorise
    case aucunPeripherique
    case peripheriqueIntrouvable(String)
    case conversionImpossible
    case capture(Error)

    var description: String {
        switch self {
        case .nonAutorise: "micro non autorisé — la permission sera demandée au premier usage réel"
        case .aucunPeripherique: "aucun périphérique d'entrée sain — que des pilotes de boucle ?"
        case .peripheriqueIntrouvable(let nom): "périphérique « \(nom) » introuvable pour la capture"
        case .conversionImpossible: "conversion vers le format du moteur impossible"
        case .capture(let e): "session de capture — \(e)"
        }
    }
}

/// L'état que la file audio touche — derrière un verrou, parce que le rappel
/// n'est pas sur le MainActor et qu'un converter n'est pas Sendable.
final class EtatDuMicro: @unchecked Sendable {
    let verrou = OSAllocatedUnfairLock<(converter: AVAudioConverter?, sortis: Int64)>(
        initialState: (nil, 0))
    /// Les compteurs du diagnostic — écrits par le rappel, lus par le doctor.
    let compteurs = OSAllocatedUnfairLock<(appels: Int, statut: Int, longueur: Int, erreur: String?)>(
        initialState: (0, -1, 0, nil))
}

/// Tout ce que le rappel a le droit de toucher — Sendable par construction.
struct ContexteDuMicro: @unchecked Sendable {
    let etat: EtatDuMicro
    let puits: PuitsAudio
    let format: AVAudioFormat
}

/// Le délégué de capture — une classe À PART, jamais isolée : la file audio
/// l'appelle, et elle n'a le droit de toucher que le contexte.
final class RappelDeCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let contexte: ContexteDuMicro
    init(contexte: ContexteDuMicro) { self.contexte = contexte }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Thread audio : pas de journal, pas de MainActor, pas d'allocation
        // évitable. On recopie, on convertit, on date en échantillons sortis,
        // on livre.
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let formatEntree = AVAudioFormat(streamDescription: asbd) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let brut = AVAudioPCMBuffer(pcmFormat: formatEntree, frameCapacity: frames) else { return }
        brut.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: brut.mutableAudioBufferList) == noErr
        else { return }

        let etat = contexte.etat
        let format = contexte.format
        let ratio = format.sampleRate / formatEntree.sampleRate
        let capacite = AVAudioFrameCount(Double(frames) * ratio) + 64
        guard let converti = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacite) else { return }

        // Le converter se LIT sous le verrou, la conversion se fait DEHORS :
        // une reconfiguration remplace la référence, jamais l'objet en cours
        // d'usage. Si le périphérique livre un autre format que son format
        // actif annoncé, le converter est refait — une fois, sous le verrou.
        let converter: AVAudioConverter? = etat.verrou.withLock { e in
            if let c = e.converter, c.inputFormat == formatEntree { return c }
            let neuf = AVAudioConverter(from: formatEntree, to: format)
            e.converter = neuf
            return neuf
        }
        guard let converter else { return }
        let source = SourceAudioUnique(brut)
        var erreur: NSError?
        let statutConversion = converter.convert(to: converti, error: &erreur) { _, statut in
            source.servir(statut)
        }
        let longueur = Int(converti.frameLength)
        let codeErreur = erreur.map { "\($0.code)" }

        // Sous le verrou : des entiers seulement — le compteur d'échantillons
        // sortis et les compteurs du diagnostic.
        let premier: Int64? = etat.verrou.withLock { e in
            etat.compteurs.withLock {
                $0.appels += 1; $0.statut = statutConversion.rawValue
                $0.longueur = longueur; $0.erreur = codeErreur
            }
            guard codeErreur == nil, longueur > 0 else { return nil }
            let p = e.sortis
            e.sortis += Int64(longueur)
            return p
        }
        guard let premier else { return }

        // L'instant de PRÉSENTATION du buffer, sur l'horloge hôte — la seule
        // horloge maîtresse (ADR-0007). Invalide → le consommateur se replie
        // sur le compteur d'échantillons.
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let valide = pts.isValid && !pts.isIndefinite
        let hostTime = valide ? CMClockConvertHostTimeToSystemUnits(pts) : 0
        contexte.puits.recevoir(TrancheAudio(buffer: converti, premierEchantillon: premier,
                                             hostTime: hostTime, hostTimeValide: valide))
    }
}

@MainActor
final class MicroParFenetre {

    private static let log = Logger(subsystem: logSubsystem, category: "micro")

    /// Appelé quand le micro DOIT se fermer sans que personne ne l'ait
    /// demandé — la raison est celle qu'on journalise et qu'on donne à la
    /// machine à états (`.fermetureDOffice`).
    var surFermetureDOffice: ((String) -> Void)?

    private(set) var estOuvert = false
    private(set) var peripherique: Peripheriques.Candidat?
    private(set) var latence: LatenceEntree.Mesure?
    private(set) var formatEntree: AVAudioFormat?

    private var session: AVCaptureSession?
    private var rappel: RappelDeCapture?
    private let fileDeCapture = DispatchQueue(label: "regarde.micro", qos: .userInteractive)
    private var format: AVAudioFormat?
    private var puits: PuitsAudio?
    private var identifiant: AudioDeviceID?
    private var observateurs: [any NSObjectProtocol] = []
    private var sondeSaisieSecurisee: Timer?
    private let etat = EtatDuMicro()

    /// Ce que l'ouverture a réellement obtenu — pour le self-test et le doctor.
    var diagnostic: String {
        let fmt = formatEntree.map { "\(Int($0.sampleRate)) Hz × \($0.channelCount)" } ?? "?"
        let c = etat.compteurs.withLock { $0 }
        return "périphérique \(peripherique?.nom ?? "?") · entrée \(fmt) · capture "
            + (session?.isRunning == true ? "en marche" : "arrêtée")
            + " · rappel \(c.appels) appel(s), statut \(c.statut), \(c.longueur) frame(s), erreur \(c.erreur ?? "aucune")"
    }

    // MARK: - Ouvrir, fermer

    /// Ouvre une fenêtre : choisit le périphérique, mesure la latence, démarre
    /// la capture. `format` est celui que le moteur veut recevoir.
    func ouvrir(format cible: AVAudioFormat, puits: PuitsAudio) throws {
        guard !estOuvert else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw MicroErreur.nonAutorise
        }
        guard let choix = Peripheriques.choisir(parmi: Peripheriques.candidatsVivants()) else {
            throw MicroErreur.aucunPeripherique
        }
        self.peripherique = choix
        self.identifiant = Peripheriques.identifiantCoreAudio(uid: choix.uid)
        self.format = cible
        self.puits = puits
        // Le compteur repart à zéro : la tranche 0 de CETTE fenêtre. Une
        // reconfiguration en cours de fenêtre, elle, ne le remet pas à zéro.
        etat.verrou.withLock { $0 = (nil, 0) }
        etat.compteurs.withLock { $0 = (0, -1, 0, nil) }

        try construireEtDemarrer()
        estOuvert = true
        observer()
        Journal.event(.system, "micro — \(choix.nom) · latence \(latence?.description ?? "non mesurée")")
    }

    /// Ferme la fenêtre : arrête la capture, cesse d'observer.
    func fermer() {
        guard estOuvert else { return }
        arreter()
        estOuvert = false
        cesserDObserver()
        Journal.event(.system, "micro — fermé")
    }

    // MARK: - La session de capture

    private func construireEtDemarrer() throws {
        guard let format, let puits, let choix = peripherique else { return }
        guard let appareil = AVCaptureDevice(uniqueID: choix.uid) else {
            throw MicroErreur.peripheriqueIntrouvable(choix.nom)
        }

        // Le format ACTIF du périphérique — ce qu'il livrera — pour créer le
        // converter une fois, avant le premier buffer.
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(appareil.activeFormat.formatDescription),
           let entree = AVAudioFormat(streamDescription: asbd) {
            formatEntree = entree
            guard let converter = AVAudioConverter(from: entree, to: format) else {
                throw MicroErreur.conversionImpossible
            }
            etat.verrou.withLock { $0.converter = converter }
        }

        if let identifiant {
            // La présentation d'un inputNode n'existe pas ici : le PTS de
            // chaque buffer porte déjà l'instant de capture ; restent les deux
            // termes du périphérique (§ 3.6), soustraits par le consommateur.
            latence = LatenceEntree.mesurer(peripherique: identifiant, presentationSecondes: 0)
        }

        let session = AVCaptureSession()
        let rappel = RappelDeCapture(contexte: ContexteDuMicro(etat: etat, puits: puits, format: format))
        session.beginConfiguration()
        do {
            let entree = try AVCaptureDeviceInput(device: appareil)
            guard session.canAddInput(entree) else { throw MicroErreur.peripheriqueIntrouvable(choix.nom) }
            session.addInput(entree)
            let sortie = AVCaptureAudioDataOutput()
            sortie.setSampleBufferDelegate(rappel, queue: fileDeCapture)
            guard session.canAddOutput(sortie) else { throw MicroErreur.conversionImpossible }
            session.addOutput(sortie)
        } catch let e as MicroErreur {
            session.commitConfiguration()
            throw e
        } catch {
            session.commitConfiguration()
            throw MicroErreur.capture(error)
        }
        session.commitConfiguration()
        session.startRunning()
        guard session.isRunning else { throw MicroErreur.capture(NSError(
            domain: "regarde.micro", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "la session de capture n'a pas démarré"])) }
        self.session = session
        self.rappel = rappel
    }

    private func arreter() {
        session?.stopRunning()
        session = nil
        rappel = nil
        etat.verrou.withLock { $0.converter = nil }
    }

    /// Le périphérique a disparu ou la session a trébuché : on reconstruit sur
    /// un nouveau choix, on remesure, sans remettre le compteur à zéro — la
    /// fenêtre continue, le moteur n'est pas recréé (§ 7.2).
    private func reconfigurer(raison: String) {
        guard estOuvert else { return }
        session?.stopRunning()
        session = nil
        rappel = nil
        guard let choix = Peripheriques.choisir(parmi: Peripheriques.candidatsVivants()) else {
            fermerDOffice(raison: "reconfiguration — plus aucun périphérique sain (\(raison))")
            return
        }
        peripherique = choix
        identifiant = Peripheriques.identifiantCoreAudio(uid: choix.uid)
        do {
            try construireEtDemarrer()
            Journal.event(.system, "micro — reconfiguration (\(raison)) · \(choix.nom) · latence \(latence?.description ?? "?")")
        } catch {
            Journal.warn(.system, "micro — reconfiguration impossible : \(error) — fenêtre fermée d'office")
            fermerDOffice(raison: "reconfiguration impossible")
        }
    }

    private func fermerDOffice(raison: String) {
        guard estOuvert else { return }
        fermer()
        Journal.warn(.system, "micro — fermé d'office : \(raison)")
        surFermetureDOffice?(raison)
    }

    // MARK: - Ce qu'on surveille, fenêtre ouverte

    private func observer() {
        let centre = NotificationCenter.default
        let atelier = NSWorkspace.shared.notificationCenter
        let distribue = DistributedNotificationCenter.default()

        observateurs.append(centre.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigurer(raison: "périphérique débranché") }
        })
        observateurs.append(centre.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigurer(raison: "erreur de session") }
        })
        observateurs.append(atelier.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fermerDOffice(raison: "mise en veille") }
        })
        observateurs.append(atelier.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fermerDOffice(raison: "changement de session") }
        })
        observateurs.append(distribue.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fermerDOffice(raison: "écran verrouillé") }
        })

        // La saisie sécurisée n'a pas de notification : un sondage léger,
        // seulement fenêtre ouverte — quatre lectures par seconde d'un
        // booléen, le prix d'une règle sans exception.
        sondeSaisieSecurisee = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.estOuvert, IsSecureEventInputEnabled() else { return }
                self.fermerDOffice(raison: "saisie sécurisée — un mot de passe a le focus")
            }
        }
    }

    private func cesserDObserver() {
        for o in observateurs {
            NotificationCenter.default.removeObserver(o)
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
        }
        observateurs.removeAll()
        sondeSaisieSecurisee?.invalidate()
        sondeSaisieSecurisee = nil
    }
}
