import CoreMedia
import CoreVideo
import Foundation
import Synchronization
import os

// ─────────────────────────────────────────────────────────────────────────────
// La frontière B2 — S37, spécification § 5.3
//
// « La règle est absolue et ne souffre aucune exception d'optimisation : LE THREAD
// DU TAP NE TOUCHE JAMAIS UN CVPixelBuffer. » (plan, second piège du lot 3)
//
// Il pousse un triplet dans un anneau lock-free, point final. L'appariement se
// fait sur `encodeQueue`, seule propriétaire des frames. Un `EXC_BAD_ACCESS`
// intermittent dans `CVPixelBufferRelease`, dont la fréquence dépend de l'activité
// de l'écran, coûte des soirées entières à diagnostiquer parce qu'il n'est pas
// reproductible à la demande.
//
// POURQUOI LA DEMANDE PART AU `mouseDown` ET NON AU RELÂCHEMENT — c'est le point
// que la conception ne dit pas, et il commande tout ce fichier :
//
//   l'anneau tient QUATRE frames, soit 0,27 s à 15 fps. Un geste de tracé dure une
//   à deux secondes. Si l'on attendait le `mouseUp` pour aller chercher la frame
//   du `mouseDown`, elle aurait quitté l'anneau depuis longtemps — et l'on
//   apparierait sur ce qui reste, c'est-à-dire sur l'écran d'APRÈS. Le bug B1,
//   reconstitué par un autre chemin.
//
//   Le tap dépose donc sa demande à la PRESSION, `encodeQueue` la sert dans la
//   foulée, et le relâchement ne fait que réclamer un instantané déjà pris.
//
// LA DOUBLE GARDE. Copier chaque frame dans l'anneau brûle 440 MiB/s de bande
// passante mémoire en permanence, avec la pollution de cache qui va avec — ce
// n'est PAS dans les 1,5 % de CPU, qui ne mesurent que l'encodage. On ne copie
// donc que si l'anneau est ARMÉ — première tenue de ⌥⌘ de la session — et si
// l'écran a BOUGÉ. Les deux, pas l'un ou l'autre.
// ─────────────────────────────────────────────────────────────────────────────

/// L'anneau lock-free du tap vers `encodeQueue`.
///
/// Écrit depuis le thread du tap, lu depuis `encodeQueue`. Aucune allocation,
/// aucun verrou, aucun appel Objective-C : seulement des écritures atomiques sur
/// un tampon de capacité fixe.
final class SnapshotRing: @unchecked Sendable {
    static let shared = SnapshotRing()

    /// Puissance de deux : masque au lieu de modulo dans le chemin du tap.
    private static let capacite = 32

    private let sequences: UnsafeMutableBufferPointer<UInt64>
    private let ticks: UnsafeMutableBufferPointer<UInt64>
    private let ecrites = Atomic<UInt64>(0)
    private let lues = Atomic<UInt64>(0)
    /// L'anneau est-il entretenu ? Lu depuis le thread du tap, hors du main actor.
    private let arme = Atomic<Bool>(false)

    init() {
        sequences = .allocate(capacity: Self.capacite)
        ticks = .allocate(capacity: Self.capacite)
        sequences.initialize(repeating: 0)
        ticks.initialize(repeating: 0)
    }

    var estArme: Bool { arme.load(ordering: .relaxed) }
    func armer(_ v: Bool) { arme.store(v, ordering: .relaxed) }

    /// Déposé par le thread du tap, à la PRESSION. Rend le numéro de la demande.
    ///
    /// Quatre opérations, toutes atomiques ou des écritures dans un tampon déjà
    /// alloué. Rien d'autre n'est permis ici.
    @inline(__always)
    @discardableResult
    func demander(hostTicks: UInt64) -> UInt64 {
        guard arme.load(ordering: .relaxed) else { return 0 }
        let n = ecrites.wrappingAdd(1, ordering: .relaxed).newValue
        let i = Int(n) & (Self.capacite - 1)
        sequences[i] = n
        ticks[i] = hostTicks
        return n
    }

    /// Drainé par `encodeQueue`. Rend les demandes non encore servies.
    func drainer() -> [(sequence: UInt64, hostTicks: UInt64)] {
        let fin = ecrites.load(ordering: .acquiring)
        var debut = lues.load(ordering: .relaxed)
        guard fin > debut else { return [] }
        // Si le producteur a débordé l'anneau, on repart de ce qui est encore là
        // plutôt que de rendre des entrées écrasées.
        if fin - debut > UInt64(Self.capacite) { debut = fin - UInt64(Self.capacite) }
        var sortie: [(UInt64, UInt64)] = []
        var n = debut + 1
        while n <= fin {
            let i = Int(n) & (Self.capacite - 1)
            if sequences[i] == n { sortie.append((n, ticks[i])) }
            n += 1
        }
        lues.store(fin, ordering: .releasing)
        return sortie
    }
}

/// Une frame retenue, avec de quoi la situer.
struct FrameSnapshot: @unchecked Sendable {
    let sequence: UInt64
    let pixels: CVPixelBuffer
    let ref: FrameRef
    let t: SessionTime
    let motion: MotionSample
}

/// L'anneau de frames. **Vit sur `encodeQueue`, et nulle part ailleurs.**
final class FrameRing: @unchecked Sendable {

    private let log = Logger(subsystem: logSubsystem, category: "anneau")
    private let queue: DispatchQueue
    private let segmentID: CaptureSegmentID

    /// Quatre frames, soit 0,27 s à 15 fps. Le dimensionner pour couvrir 4 s
    /// demanderait 60 frames, soit 1,77 GiB à pleine résolution — la même
    /// arithmétique qui a écarté le ring buffer RAM (ADR-0003).
    private static let profondeur = 4
    private var frames: [(pixels: CVPixelBuffer, pts: CMTime, ref: FrameRef, t: SessionTime)] = []

    /// Instantanés pris et pas encore réclamés, par numéro de demande.
    private var pris: [UInt64: FrameSnapshot] = [:]
    private let verrouPris = OSAllocatedUnfairLock(initialState: [UInt64: FrameSnapshot]())

    // Comptes de diagnostic — c'est ce qui remplace un test qu'on ne peut pas écrire.
    private(set) var copiesFaites = 0
    private(set) var copiesEvitees = 0
    private(set) var apparieesSansFrame = 0

    // Mouvement de la seconde écoulée.
    private var fenetre: [(t: Double, dirty: Double)] = []
    private var motion = MotionSample()

    init(queue: DispatchQueue, segmentID: CaptureSegmentID) {
        self.queue = queue
        self.segmentID = segmentID
    }

    /// Appelé pour CHAQUE frame complète, sur `encodeQueue`.
    func accueillir(_ sample: CMSampleBuffer, ref: FrameRef, dirtyRatio: Double) {
        // La garde qui rend la règle vérifiable au lieu d'être une intention.
        dispatchPrecondition(condition: .onQueue(queue))

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let t = SessionClock.shared.fromStream(pts) ?? SessionClock.shared.now()

        // Métriques de mouvement sur une fenêtre glissante d'une seconde.
        let maintenant = t.seconds
        fenetre.append((maintenant, dirtyRatio))
        fenetre.removeAll { maintenant - $0.t > 1.0 }
        motion = MotionSample(completeFramesLastSecond: fenetre.count,
                              dirtyRatioLastSecond: fenetre.map(\.dirty).reduce(0, +))

        // LA DOUBLE GARDE. Armé ET l'écran a bougé — pas l'un ou l'autre.
        //
        // Sans elle, on copie 440 MiB/s en permanence, y compris pendant les
        // minutes où l'utilisateur lit son écran sans rien annoter. Ce coût
        // n'apparaît pas dans la mesure de CPU, qui ne regarde que l'encodage :
        // il se voit en bande passante mémoire et en pollution de cache, et il
        // fausserait C3b sans qu'on sache pourquoi.
        guard SnapshotRing.shared.estArme, dirtyRatio > 0 else {
            copiesEvitees += 1
            servirDemandes(pts: pts, ref: ref, t: t, sample: nil)
            return
        }
        guard let pixels = CMSampleBufferGetImageBuffer(sample) else { return }

        frames.append((pixels, pts, ref, t))
        if frames.count > Self.profondeur { frames.removeFirst() }
        copiesFaites += 1

        servirDemandes(pts: pts, ref: ref, t: t, sample: sample)
    }

    /// Sert les demandes déposées par le tap depuis la dernière frame.
    ///
    /// L'appariement retient la frame dont le PTS est le plus proche PAR VALEUR
    /// INFÉRIEURE. C'est la sémantique voulue : l'utilisateur désigne ce qu'il
    /// VOIT, donc la dernière image affichée avant sa pression — pas celle qui
    /// arrive après, où l'infobulle s'est déjà refermée.
    private func servirDemandes(pts: CMTime, ref: FrameRef, t: SessionTime, sample: CMSampleBuffer?) {
        let demandes = SnapshotRing.shared.drainer()
        guard !demandes.isEmpty else { return }

        for (sequence, ticks) in demandes {
            let stamped = SessionClock.shared.stamp(hostTicks: ticks)
            guard let candidate = frames.last(where: { $0.t.seconds <= stamped.time.seconds })
                                    ?? frames.last else {
                // Aucune frame en réserve : l'anneau vient d'être armé, ou l'écran
                // était figé. Ce n'est pas une erreur — le filet RAM prendra le
                // relais — mais c'est compté, parce qu'un compte qui monte veut
                // dire que la double garde est trop serrée.
                apparieesSansFrame += 1
                continue
            }
            let snap = FrameSnapshot(sequence: sequence, pixels: candidate.pixels,
                                     ref: candidate.ref, t: candidate.t, motion: motion)
            verrouPris.withLock { $0[sequence] = snap }
        }
    }

    /// Réclamé depuis n'importe où, au relâchement. Rend l'instantané pris à la
    /// PRESSION, et le retire.
    func reclamer(_ sequence: UInt64) -> FrameSnapshot? {
        verrouPris.withLock { $0.removeValue(forKey: sequence) }
    }

    /// Le mouvement de la dernière seconde, pour le plan de burst.
    func mouvement() -> MotionSample {
        dispatchPrecondition(condition: .onQueue(queue))
        return motion
    }

    func vider() {
        dispatchPrecondition(condition: .onQueue(queue))
        frames.removeAll()
        verrouPris.withLock { $0.removeAll() }
    }

    /// Ce que le journal imprime en fin de session.
    var bilan: [(String, String)] {
        [("copies faites", "\(copiesFaites)"),
         ("copies évitées", "\(copiesEvitees) — double garde"),
         ("appariements sans frame", "\(apparieesSansFrame)")]
    }
}
