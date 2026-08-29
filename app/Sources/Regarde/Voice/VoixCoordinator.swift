import AppKit
import AVFoundation
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Le coordinateur de la voix — S64, le branchement au geste
//
// Ici se rejoignent les trois pièces pures ou presque des sessions
// précédentes : la machine à états (S63) qui décide, le micro (S61) qui
// livre, le moteur (S62) qui transcrit. Le coordinateur ne DÉCIDE rien : il
// nourrit la machine avec le vrai ⌥⌘, obéit à ses effets, et pose la question
// du rattachement quand les segments arrivent. Le journal dit à quelle marque
// chaque segment est allé, et par quelle règle — c'est ce que la recette lira.
//
// Deux choses qu'il faut savoir en lisant ce fichier :
//
//   LA VOIX EST OPTIONNELLE. Micro non autorisé, modèle absent, locale
//   inconnue : la machine tourne quand même — à vide —, les marques, la
//   palette et le clavier ne changent pas d'un pixel. Rien de ce que les lots
//   2 à 4 ont livré ne dépend de ce fichier.
//
//   LES GESTES ARRIVENT EN DOUBLE. `modifierChanged` est publié sur chaque
//   changement d'état du gate — la prise, puis le début du tracé — : la
//   machine verrait deux prises et scinderait une fenêtre pour rien. Les
//   points d'entrée détectent les FRONTS : une prise n'est prise que hors
//   tenue, un relâchement que pendant une tenue.
// ─────────────────────────────────────────────────────────────────────────────

/// Entre le micro et le moteur : laisse tout passer, et dit « on parle »
/// quand une tranche dépasse le seuil d'énergie — au plus quatre fois par
/// seconde. C'est ce signal, pas les volatils du moteur, qui prolonge la
/// fenêtre et retient l'éclair : le moteur n'a rien à dire avant douze
/// secondes, l'énergie parle tout de suite.
final class EcouteDEnergie: PuitsAudio, @unchecked Sendable {
    let suivant: PuitsAudio
    let seuil: Double
    var surParole: (@Sendable () -> Void)?
    private let etat = OSAllocatedUnfairLock<(max: Double, dernierSignal: UInt64, tranches: Int, parlees: [Int64])>(
        initialState: (0, 0, 0, []))

    init(suivant: PuitsAudio, seuil: Double) { self.suivant = suivant; self.seuil = seuil }

    func recevoir(_ tranche: TrancheAudio) {
        suivant.recevoir(tranche)
        let signaler: Bool = etat.withLock { e in
            e.max = max(e.max, tranche.energie)
            e.tranches += 1
            guard tranche.energie >= seuil else { return false }
            // La carte de « quand on a entendu parler », en échantillons
            // sortis — pour le journal de fermeture, et pour savoir si un
            // silence du moteur est un silence de l'audio.
            e.parlees.append(tranche.premierEchantillon)
            let maintenant = SessionClock.hostTicksNow()
            guard e.dernierSignal == 0 || SessionClock.millis(from: e.dernierSignal, to: maintenant) > 250 else { return false }
            e.dernierSignal = maintenant
            return true
        }
        if signaler { surParole?() }
    }

    /// Les plages parlées — en secondes depuis l'ouverture du micro —, deux
    /// tranches à moins de 0,6 s formant une même plage.
    func plagesParlees(cadence: Double) -> [(debut: Double, fin: Double)] {
        let parlees = etat.withLock { $0.parlees }
        var plages: [(Double, Double)] = []
        var debut: Double?, fin: Double?
        for ech in parlees {
            let t = Double(ech) / cadence
            if let f = fin, t - f < 0.6 { fin = t; continue }
            if let d = debut, let f = fin { plages.append((d, f)) }
            debut = t; fin = t
        }
        if let d = debut, let f = fin { plages.append((d, f)) }
        return plages
    }

    /// Le bilan de la fenêtre — énergie maximale, tranches, plages parlées —
    /// puis remise à zéro.
    func bilanEtRemise(cadence: Double) -> String {
        let plages = plagesParlees(cadence: cadence)
            .map { String(format: "%.1f-%.1f", $0.debut, $0.fin) }
        return etat.withLock { e in
            defer { e = (0, 0, 0, []) }
            return "énergie max \(Int(e.max)) · \(e.tranches) tranche(s) · parlé \(plages.isEmpty ? "jamais" : plages.joined(separator: ", "))"
        }
    }
}

@MainActor
final class VoixCoordinator {
    static let shared = VoixCoordinator()

    private static let log = Logger(subsystem: logSubsystem, category: "voix")

    private(set) var machine = FenetreDeParole.Machine()
    private let micro = MicroParFenetre()
    private let transcripteur = Transcripteur()
    /// Le seuil d'énergie de parole — RMS Int16 —, calibré sur cette machine
    /// (lot5-seuils § 10) : le bruit d'un bureau reste sous quelques centaines,
    /// une voix normale dépasse le millier.
    nonisolated static let seuilEnergie = 400.0
    private lazy var ecoute: EcouteDEnergie = {
        let e = EcouteDEnergie(suivant: transcripteur, seuil: Self.seuilEnergie)
        e.surParole = { Task { @MainActor in VoixCoordinator.shared.paroleEntendue() } }
        return e
    }()
    private var format: AVAudioFormat?
    /// Vrai quand le micro est autorisé et le moteur prêt : la seule condition
    /// pour qu'une fenêtre ouvre autre chose qu'un état.
    private(set) var disponible = false
    private(set) var verrou = false

    /// Les segments de la session (ou de l'éclair) en cours, rattachés —
    /// S66 les écrit, S67 les rend.
    private(set) var segments: [SegmentDeParole] = []

    private var ouverture: Task<Void, Never>?
    private var tic: Timer?
    private var volatilVu = false
    /// Posé par le mode éclair quand il attend la fin d'une fenêtre parlée.
    var apresDrain: (() -> Void)?
    private var demandeEnCours = false
    private var annonceGlobaleMuette = false

    private init() {
        micro.surFermetureDOffice = { [weak self] raison in
            MainActor.assumeIsolated { self?.fermetureDOffice(raison: raison) }
        }
    }

    // MARK: - Préparation

    /// Une fois : la locale, le modèle, le format. Sans permission micro, on
    /// ne demande RIEN (S72) — la voix reste simplement indisponible, et le
    /// journal le dit une fois.
    func preparer() async {
        guard !disponible else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            // Pas d'invite au lancement : elle viendra au PREMIER usage réel —
            // la première fenêtre de parole — quand l'utilisateur sait pourquoi.
            Journal.event(.system, "voix — micro jamais demandé : l'invite viendra à la première fenêtre de parole")
            return
        default:
            Journal.event(.system, "voix — micro refusé : la palette d'intentions et le clavier restent (Réglages > Confidentialité > Microphone)")
            return
        }
        do {
            format = try await transcripteur.preparer()
            await transcripteur.brancher(
                surVolatil: { t in Task { @MainActor in VoixCoordinator.shared.volatil(t) } },
                surFinal: nil)
            disponible = true
            Journal.event(.system, "voix — prête")
        } catch {
            Journal.warn(.system, "voix — indisponible : \(error)")
        }
    }

    /// Le premier usage réel : une fenêtre de parole s'ouvre et le micro n'a
    /// jamais été demandé. L'invite part MAINTENANT — une seule fois —, la
    /// fenêtre en cours vit sans audio, la suivante aura le micro.
    private func demanderLaPermissionSiJamaisPosee() {
        guard !demandeEnCours,
              AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        demandeEnCours = true
        Journal.event(.system, "voix — première fenêtre de parole : demande d'autorisation du micro")
        Task { @MainActor in
            let accorde = await AVCaptureDevice.requestAccess(for: .audio)
            Journal.event(.system, "voix — permission micro \(accorde ? "accordée" : "refusée")")
            self.demandeEnCours = false
            if accorde { await self.preparer() }
        }
    }

    /// À l'ouverture d'une session, et après la publication d'un éclair : la
    /// machine repart, les segments aussi. Le verrou, lui, survit — c'est
    /// l'utilisateur qui l'a posé.
    func nouvelleSession() {
        segments.removeAll()
        machine = FenetreDeParole.Machine()
        if verrou { poserLeVerrou() }
    }

    // MARK: - Le geste

    private var enTenue: Bool {
        guard let f = machine.courante, f.estOuverte else { return false }
        return f.relachement == nil
    }

    /// Sous le verrou, la fenêtre est tenue et tout est global : le geste ne
    /// la ferme ni ne la scinde — un monologue ne se coupe pas parce qu'on
    /// trace pendant qu'on parle.
    private var verrouTient: Bool { verrou && machine.estOuverte }

    func prise() {
        guard !enTenue, !verrouTient else { return }
        appliquer(.prise(maintenant()))
    }

    func relachement() {
        guard enTenue, !verrou else { return }
        appliquer(.relachement(maintenant()))
    }

    func mouvement() {
        guard enTenue, !verrou, let f = machine.courante, !f.mouvement, f.marque == nil else { return }
        appliquer(.mouvement(maintenant()))
    }

    func trace(marque: Int, t: SessionTime) {
        guard !verrouTient else { return }
        appliquer(.trace(t, marque: marque))
    }

    func volatil(_ t: SessionTime) {
        volatilVu = true
        appliquer(.volatil(t))
    }

    /// Le signal d'énergie : de la parole, maintenant. Pour la machine c'est
    /// un volatil — « la parole continue » — daté de l'instant présent.
    func paroleEntendue() {
        guard machine.estOuverte else { return }
        volatilVu = true
        appliquer(.volatil(maintenant()))
    }

    private func fermetureDOffice(raison: String) {
        appliquer(.fermetureDOffice(maintenant(), raison: raison))
    }

    // MARK: - Le verrou ⌃⌥M

    /// Verrouillé, le micro reste ouvert et tout est global jusqu'au
    /// déverrouillage (§ 3.5) : une fenêtre TENUE, que rien ne ferme.
    func basculerVerrou() {
        verrou.toggle()
        if verrou {
            poserLeVerrou()
            Journal.event(.system, "verrou micro — activé, commentaire global jusqu'au déverrouillage")
            HUDWindow.shared.announce("Micro verrouillé — commentaire global",
                                      detail: "⌃⌥M pour déverrouiller", duration: 86_400)
        } else {
            appliquer(.verrou(maintenant(), actif: false))
            // La fenêtre tenue par le verrou se relâche ici : ce n'est pas un
            // geste global explicite, l'annonce n'a pas lieu d'être.
            annonceGlobaleMuette = true
            if enTenue { appliquer(.relachement(maintenant())) }
            annonceGlobaleMuette = false
            Journal.event(.system, "verrou micro — désactivé")
            HUDWindow.shared.announce("Micro déverrouillé", detail: "la fenêtre se fermera d'elle-même", duration: 3)
        }
    }

    private func poserLeVerrou() {
        appliquer(.verrou(maintenant(), actif: true))
        if !machine.estOuverte { appliquer(.prise(maintenant())) }
    }

    // MARK: - La machine et ses effets

    private func maintenant() -> SessionTime { SessionClock.shared.now() }

    private var drainEnCours: Task<Void, Never>?
    /// L'instant de session où le micro de la fenêtre courante a ouvert — les
    /// échantillons de l'écoute se comptent depuis lui.
    private var origineAudio: SessionTime?

    private func appliquer(_ evenement: FenetreDeParole.Evenement) {
        let effets = machine.appliquer(evenement)
        // Une fermeture ET une ouverture dans le même lot — une nouvelle prise
        // qui ferme la précédente, un second tracé qui scinde — : la machine
        // change de fenêtre, mais l'AUDIO CONTINUE. Fermer le micro et drainer
        // pour rouvrir aussitôt perdrait une à deux secondes de parole à chaque
        // enchaînement de marques ; l'historique de la machine rattachera
        // chaque segment à sa fenêtre au drain final.
        let continuite = effets.contains { if case .fermeture = $0 { true } else { false } }
            && effets.contains { if case .ouverture = $0 { true } else { false } }
        for effet in effets { executer(effet, continuite: continuite) }
    }

    private func executer(_ effet: FenetreDeParole.Effet, continuite: Bool) {
        switch effet {
        case .ouverture(let t):
            OverlayController.shared.retenirLeCalque(true)
            OverlayController.shared.pulser(marque: machine.marqueCourante)
            demarrerLeTic()
            if continuite {
                Journal.event(.system, "parole — fenêtre enchaînée à \(Self.mmss(t)), l'audio continue")
                return
            }
            volatilVu = false
            origineAudio = t
            guard disponible, let format else {
                demanderLaPermissionSiJamaisPosee()
                return
            }
            let transcripteur = transcripteur, micro = micro
            let drainPrecedent = drainEnCours
            ouverture = Task { @MainActor in
                // Le drain de la fenêtre précédente peut encore courir : on
                // l'attend, sinon « une fenêtre est déjà ouverte » et celle-ci
                // vivrait sans audio.
                await drainPrecedent?.value
                do {
                    try await transcripteur.ouvrirFenetre(origine: t)
                    try micro.ouvrir(format: format, puits: ecoute)
                    Journal.event(.system, "parole — fenêtre ouverte à \(Self.mmss(t))")
                } catch {
                    Journal.warn(.system, "parole — fenêtre non ouverte : \(error)")
                }
            }

        case .fermeture(let fenetre):
            if continuite { return }
            arreterLeTic()
            OverlayController.shared.pulser(marque: nil)
            OverlayController.shared.retenirLeCalque(false)
            micro.fermer()
            let transcripteur = transcripteur
            let ouverture = ouverture
            drainEnCours = Task { @MainActor in
                await ouverture?.value
                do {
                    let arrives = try await transcripteur.drainer()
                    self.rattacher(arrives, fenetre: fenetre)
                } catch {
                    Journal.event(.system, "parole — fenêtre fermée sans transcription (\(error))")
                }
                self.apresDrain?()
                self.apresDrain = nil
            }

        case .commentaireGeneral:
            guard !annonceGlobaleMuette else { return }
            Journal.event(.system, "parole — commentaire général")
            HUDWindow.shared.announce("Commentaire général", detail: "la parole de ce geste ne vise aucune marque", duration: 3)
        }
    }

    /// La question posée à la machine, segment par segment, et le journal
    /// qui dit la réponse — c'est ce que la recette relit.
    private func rattacher(_ arrives: [SegmentDeParole], fenetre: FenetreDeParole.Fenetre) {
        var rattaches: [SegmentDeParole] = []
        // Le moteur date le premier mot d'une énonciation au DÉBUT de sa plage —
        // silence de tête compris, jusqu'à l'origine de l'audio. Pour la règle
        // du premier mot (ADR-0011), c'est trop tôt de plusieurs secondes : la
        // première tranche PARLÉE de la plage (énergie, ± 11 ms) le corrige.
        let cadence = format?.sampleRate ?? 16_000
        let plages = ecoute.plagesParlees(cadence: cadence)
        let origine = origineAudio?.seconds ?? 0
        for var segment in arrives {
            var premierMot = segment.onset
            if let plage = plages.first(where: {
                origine + $0.fin >= segment.plageDebut.seconds && origine + $0.debut <= segment.plageFin.seconds
            }) {
                let parle = SessionTime(seconds: origine + plage.debut)
                if parle > premierMot { premierMot = parle }
            }
            let attachement = machine.rattacher(premierMot: premierMot, fin: segment.fin)
            segment.attachement = attachement
            segment.premierMot = premierMot
            rattaches.append(segment)
            let extrait = segment.texteBrut
            let quand = "premier mot à \(Self.mmss(premierMot))"
            switch attachement {
            case .marque(let n, let regle):
                Journal.event(.system, "parole — segment → marque \(n) (\(Self.libelle(regle)), \(quand)) : « \(extrait) »")
            case .global(let regle):
                Journal.event(.system, "parole — segment → global (\(Self.libelle(regle)), \(quand)) : « \(extrait) »")
            }
        }
        segments.append(contentsOf: rattaches)
        Journal.event(.system, "parole — fenêtre fermée à \(Self.mmss(fenetre.fermeture ?? fenetre.ouverture)) · \(rattaches.count) segment(s) · \(ecoute.bilanEtRemise(cadence: format?.sampleRate ?? 16_000))")
    }

    // MARK: - Le tic de l'horloge

    private func demarrerLeTic() {
        tic?.invalidate()
        tic = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.appliquer(.tic(SessionClock.shared.now())) }
        }
    }

    private func arreterLeTic() {
        tic?.invalidate()
        tic = nil
    }

    // MARK: - La fin de session (S66)

    /// ⌃⌥F : la fenêtre ouverte se ferme MAINTENANT — pas huit secondes plus
    /// tard —, et son drain part. La publication l'attendra : c'est LE critère
    /// du lot, la fin d'une phrase coupée par le raccourci est dans le rapport.
    func fermerPourFinDeSession() {
        guard machine.estOuverte else { return }
        Journal.event(.system, "parole — fin de session : la fenêtre se ferme, drain en cours")
        appliquer(.fermetureDOffice(maintenant(), raison: "fin de session"))
    }

    /// La latence d'entrée compensée de la dernière fenêtre, en ms entiers.
    var latenceEntreeMs: Int? { micro.latence.map { Int($0.totalMs.rounded()) } }

    /// Attend le drain en cours et rend les segments de la session, rattachés.
    /// `--sans-drain` au lancement est la contre-épreuve : ne pas attendre
    /// perd la fin de la dernière phrase, et la recette le voit.
    func attendreLeDrain() async -> [SegmentDeParole] {
        if CommandLine.arguments.contains("--sans-drain") {
            Journal.warn(.system, "parole — drain NON attendu (--sans-drain) : la fin de la dernière phrase sera perdue")
            return segments
        }
        let depart = SessionClock.hostTicksNow()
        await drainEnCours?.value
        let attente = SessionClock.millis(from: depart, to: SessionClock.hostTicksNow())
        if attente > 1 {
            Journal.event(.system, String(format: "parole — drain attendu %.0f ms, %d segment(s) pour le rapport", attente, segments.count))
        }
        return segments
    }

    // MARK: - L'éclair

    /// L'éclair parle (S60 § 5) : silencieux, il publie à 0,8 s comme avant ;
    /// parlé, il attend la fermeture de la fenêtre et son drain.
    var retientLeFlash: Bool { machine.estOuverte && volatilVu }

    func nouvelEclair() { nouvelleSession() }

    // MARK: - Libellés

    static func libelle(_ regle: FenetreDeParole.Regle) -> String {
        switch regle {
        case .fenetreDeParole: "fenêtre de parole"
        case .debordement: "débordement"
        case .gesteGlobal: "geste global"
        case .aucuneFenetre: "aucune fenêtre"
        }
    }

    static func mmss(_ t: SessionTime) -> String {
        let s = max(0, t.seconds)
        return String(format: "%02d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}
