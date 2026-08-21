import CoreGraphics
import Foundation
import os
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// Banc C11 — S31
//
// C11 est le critère « appariement marque ↔ frame ». Il a été ÉTALONNÉ au lot 0
// et son verdict tombe en S39, sur la chaîne continue. Ce banc-ci fait le travail
// intermédiaire, et il est important de dire ce qu'il ne fait pas :
//
//   IL NE REND PAS DE VERDICT C11. La chaîne du lot 2 capture par
//   `SCScreenshotManager` dans une tâche détachée au relâchement, et le lot 0 lui
//   a mesuré 49,1 ms de médiane, 120,9 ms au pire. Elle est structurellement hors
//   de la tolérance visée. Lui faire rendre un PASS serait mentir ; lui faire
//   rendre un FAIL serait accuser la mauvaise chose. Elle publie donc une LIGNE
//   DE BASE, et le verdict attend l'instrument qui peut le soutenir.
//
// CE QU'IL FAIT :
//
//   1. le PONT D'HORLOGE. Un clic nu est horodaté aux deux bouts — par la page
//      (`performance.now()` et son numéro de frame) et par nous (l'horodatage
//      matériel de l'événement). Plusieurs clics donnent plusieurs estimations du
//      même décalage ; leur DISPERSION dit si le pont vaut quelque chose.
//
//   2. le SEUIL, écrit AVANT toute mesure. Voir `seuilEcrit`.
//
//   3. la LIGNE DE BASE : par marque, l'instant du `mouseDown` et celui où son
//      image est arrivée. La différence est la latence propre du chemin ponctuel.
//
// Le reste — la corrélation avec le journal de la page, les quatre refus, le
// verdict — se fait dans `app/Tools/lot3-c11.sh`, où c'est lisible et modifiable
// sans recompiler.
// ─────────────────────────────────────────────────────────────────────────────

/// Le seuil d'acceptation de C11, écrit ici, AVANT la première mesure.
///
/// Il est en UNITÉS DE COMPTEUR du témoin, et pas en millisecondes, et ce n'est
/// pas un détail de présentation.
///
/// Le § 4.5 du plan fixait la tolérance à « une frame à 60 fps, soit 16 ms ». Ce
/// chiffre a été écrit pour un `captureImage` ponctuel. Il ne se transpose pas au
/// flux continu du lot 3, qui tourne à `minimumFrameInterval = 1/15`, soit
/// **66,7 ms entre deux frames encodées** : aucune extraction ne peut être plus
/// fine que cet intervalle, et un seuil de 16 ms rendrait C11 infaisable par
/// construction plutôt que difficile.
///
/// Le critère se dit donc ainsi : **le numéro gravé dans l'image doit tomber dans
/// l'intervalle des numéros que la page a rendus entre la frame encodée précédant
/// le `mouseDown` et la suivante.** L'écart se publie dans les deux unités, frames
/// de compteur et millisecondes.
///
/// Écrit avant la première mesure, et repris mot pour mot en S39. Un seuil écrit
/// après coup est un seuil ajusté au résultat.
enum SeuilC11 {
    static let enonce = """
        Le numéro gravé dans l'image doit tomber dans l'intervalle des numéros rendus \
        par la page entre la frame encodée précédant le mouseDown et la suivante. \
        Sur la chaîne PONCTUELLE du lot 2, il n'y a pas de frame encodée : le banc \
        publie l'écart en frames de compteur comme LIGNE DE BASE, et ne rend aucun \
        verdict.
        """
    /// Cadence du flux continu, qui borne la finesse d'extraction (§ 5.2).
    static let fluxFps = 15.0
    /// Ce que vaut un intervalle entre deux frames encodées, en millisecondes.
    static var intervalleEncodeMs: Double { 1000.0 / fluxFps }
    /// La tolérance du § 4.5, conservée pour mémoire — et pour dire qu'elle ne
    /// s'applique PAS ici.
    static let toleranceLot0Ms = 16.0
    /// Dispersion maximale du pont d'horloge au-delà de laquelle le banc REFUSE
    /// de conclure. Un pont plus flou que la grandeur mesurée ne mesure rien.
    static let dispersionMaxMs = 16.0
}

/// Observation faite depuis le thread du tap.
///
/// Une seule chose y est faite, et elle est choisie pour cela : **deux écritures
/// atomiques derrière un drapeau**. Aucune allocation, aucun verrou, aucun appel
/// AppKit. Le chemin de retour de l'événement n'est pas touché — le clic repart
/// exactement comme avant, donc C1, C2 et C5 ne sont pas concernés.
final class C11Tap: @unchecked Sendable {
    static let shared = C11Tap()
    private let arme = Atomic<Bool>(false)
    private let ticks = Atomic<UInt64>(0)
    private let sequence = Atomic<UInt64>(0)

    var estArme: Bool { arme.load(ordering: .relaxed) }
    func armer(_ v: Bool) { arme.store(v, ordering: .relaxed) }

    /// Appelé depuis le thread du tap, sur le chemin de PASSE-PLAT d'un clic nu.
    @inline(__always)
    func noterClicNu(_ hostTicks: UInt64) {
        guard arme.load(ordering: .relaxed) else { return }
        ticks.store(hostTicks, ordering: .relaxed)
        sequence.wrappingAdd(1, ordering: .releasing)
    }

    /// Lu depuis l'acteur principal. Rend le dernier clic et son numéro d'ordre.
    func dernier() -> (sequence: UInt64, ticks: UInt64) {
        (sequence.load(ordering: .acquiring), ticks.load(ordering: .relaxed))
    }
}

@MainActor
final class C11Bench {
    static let shared = C11Bench()

    private let log = Logger(subsystem: logSubsystem, category: "c11")

    /// Un point du pont d'horloge : un clic nu, vu de notre côté.
    struct Pont: Codable {
        let sequence: UInt64
        /// Instant du clic sur la timeline de session.
        let t: Double
        /// Horodatage matériel brut, pour recouper avec la page si besoin.
        let hostTicks: UInt64
        let origine: String
    }

    /// Une marque et le chemin de son image.
    struct Releve: Codable {
        let numero: Int
        /// `SessionTime` du `mouseDown`.
        let t: Double
        let origine: String
        /// `SessionTime` de l'arrivée du recadrage. La différence est la latence
        /// propre du chemin ponctuel — celle que le lot 0 a mesurée à 49,1 ms de
        /// médiane et 120,9 ms au pire.
        let arrivee: Double
        var latenceMs: Double { (arrivee - t) * 1000 }
    }

    private var ponts: [Pont] = []
    private var releves: [Releve] = []
    private var derniereSequence: UInt64 = 0
    private var minuteur: Timer?

    var actif: Bool { minuteur != nil }

    // MARK: - Cycle

    func demarrer() {
        guard minuteur == nil else { return }
        ponts.removeAll(); releves.removeAll()
        derniereSequence = C11Tap.shared.dernier().sequence
        C11Tap.shared.armer(true)

        // Interrogation à 50 Hz plutôt qu'une notification depuis le tap.
        //
        // Le thread du tap ne réveille personne : c'est la règle du lot 0, et B2 en
        // est la version dure. Un banc n'a aucune raison de l'assouplir — il tourne
        // une fois, pendant qu'on le regarde, et vingt millisecondes de retard sur
        // la LECTURE d'un horodatage ne changent rien, puisque l'horodatage lui-même
        // a été pris dans le tap.
        minuteur = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            MainActor.assumeIsolated { self.relever() }
        }
        Journal.event(.system, "banc C11 armé — clics nus horodatés aux deux bouts")
    }

    func arreter() {
        C11Tap.shared.armer(false)
        minuteur?.invalidate(); minuteur = nil
        Journal.event(.system, "banc C11 arrêté — \(ponts.count) pont(s), \(releves.count) relevé(s)")
    }

    private func relever() {
        let (seq, ticks) = C11Tap.shared.dernier()
        guard seq != derniereSequence else { return }
        derniereSequence = seq
        let stamped = SessionClock.shared.stamp(hostTicks: ticks)
        ponts.append(Pont(sequence: seq, t: stamped.time.seconds,
                          hostTicks: ticks, origine: stamped.origin.rawValue))
    }

    /// Enregistre l'arrivée de l'image d'une marque. Appelé par `MarkCapture`.
    func noterArrivee(numero: Int, t: SessionTime, origine: TimestampOrigin) {
        releves.append(Releve(numero: numero, t: t.seconds, origine: origine.rawValue,
                              arrivee: SessionClock.shared.now().seconds))
    }

    // MARK: - Écriture

    /// Ce que le banc dépose à côté des images.
    struct Rapport: Codable {
        // Déclarés SANS valeur par défaut : un `let` initialisé dans un type
        // `Codable` ne se décode pas, et le compilateur le dit. On les renseigne à
        // la construction.
        let outil: String
        let protocole: Int
        /// LE SEUIL, écrit avant toute mesure.
        let seuil: String
        let intervalleEncodeMs: Double
        let toleranceLot0Ms: Double
        let dispersionMaxMs: Double
        let rendVerdict: Bool
        let pourquoi: String
        let captureVisible: Bool
        let fallbackCountDebut: Int
        let fallbackCountFin: Int
        let ponts: [Pont]
        let releves: [Releve]
    }

    private var fallbackDebut = 0
    func marquerDebut() { fallbackDebut = SessionClock.shared.fallbackCount }

    func ecrire(dans dossier: URL) throws {
        let rapport = Rapport(
            outil: "regarde-c11-bench", protocole: 1,
            seuil: SeuilC11.enonce,
            intervalleEncodeMs: SeuilC11.intervalleEncodeMs,
            toleranceLot0Ms: SeuilC11.toleranceLot0Ms,
            dispersionMaxMs: SeuilC11.dispersionMaxMs,
            // Le banc ne rend PAS de verdict sur cette chaîne, et il l'écrit dans
            // son propre fichier plutôt que de laisser le lecteur le déduire.
            rendVerdict: false,
            pourquoi: "chaîne ponctuelle du lot 2 — latence propre 40 à 130 ms mesurée au "
                    + "lot 0, structurellement hors tolérance. Verdict en S39.",
            captureVisible: TestFlags.visibleCapture,
            fallbackCountDebut: fallbackDebut,
            fallbackCountFin: SessionClock.shared.fallbackCount,
            ponts: ponts, releves: releves)

        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = dossier.appendingPathComponent("c11.json")
        try encodeur.encode(rapport).write(to: url, options: .atomic)
        log.notice("rapport C11 → \(url.lastPathComponent, privacy: .public)")
    }
}
