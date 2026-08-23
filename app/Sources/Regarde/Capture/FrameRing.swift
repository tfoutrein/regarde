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
// LA DOUBLE GARDE. Elle protégeait à l'origine contre les 440 MiB/s de bande
// passante mémoire que coûtait la copie de chaque frame — un coût qui n'est PAS
// dans les 1,5 % de CPU, lesquels ne mesurent que l'encodage. L'anneau ne copie
// plus rien (voir `FrameSnapshot`), mais la garde reste : elle évite d'accumuler
// des descripteurs pour personne, et elle donne au plan de burst sa mesure de
// mouvement. On ne retient donc que si l'anneau est ARMÉ — première tenue de ⌥⌘ —
// et si l'écran a BOUGÉ. Les deux, pas l'un ou l'autre.
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
    /// Il n'y a PLUS de curseur de lecture partagé ici, et c'est le correctif de
    /// S43 quater.
    ///
    /// Il y en avait un, et `drainer()` l'avançait jusqu'à `ecrites`. Or
    /// `servirDemandes` est appelé par le flux de CHAQUE écran, chacun sur sa
    /// propre `encodeQueue` : les écrans couraient après la même file. Celui qui
    /// drainait le premier rangeait l'instantané dans SON anneau, et la marque,
    /// qui le cherche dans l'anneau de son écran, ne trouvait rien une fois sur
    /// deux.
    ///
    /// Le symptôme était trompeur : `0 frame(s)/s · 0.000 de surface`, qui se lit
    /// « l'écran était figé » alors qu'il fallait lire « l'instantané a été volé
    /// par l'autre écran ». Il ne s'est vu qu'à deux écrans TOUS DEUX actifs —
    /// quand l'un des deux était au repos, il ne drainait presque jamais et
    /// l'autre gagnait toutes les courses.
    ///
    /// Chaque lecteur porte désormais son propre curseur. Une pression est un
    /// INSTANT, pas un écran : chaque écran enregistre indépendamment ce qu'il
    /// montrait à cet instant-là, et le consommateur prend celui dont il a besoin.
    /// Le tap reste inchangé — lui demander de résoudre l'écran coûterait un appel
    /// système là où la règle de B2 n'autorise que trois écritures.
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

    /// Où en est le producteur — pour qu'un lecteur qui arrive se place à la fin
    /// plutôt que de rejouer les demandes des sessions précédentes.
    var curseurActuel: UInt64 { ecrites.load(ordering: .acquiring) }

    /// Drainé par `encodeQueue`, avec le curseur PROPRE à l'appelant.
    ///
    /// Ne mute rien : l'avancement du curseur appartient au lecteur. C'est ce qui
    /// rend la structure sûre à N lecteurs sans verrou ni coordination.
    func drainer(depuis debut0: UInt64) -> (demandes: [(sequence: UInt64, hostTicks: UInt64)],
                                            fin: UInt64) {
        let fin = ecrites.load(ordering: .acquiring)
        var debut = debut0
        guard fin > debut else { return ([], fin) }
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
        return (sortie, fin)
    }
}

/// Une frame retenue, avec de quoi la situer.
///
/// **Elle ne porte PAS les pixels**, et c'est la correction la plus importante de ce
/// fichier.
///
/// L'anneau retenait jusqu'à quatre `CVPixelBuffer` de ScreenCaptureKit. Avec
/// `queueDepth = 6`, il en immobilisait les deux tiers : la pool s'épuisait et le
/// flux CESSAIT DE LIVRER. Le journal du 23 août le montre au chiffre près — 55
/// frames complètes sur 265 théoriques, soit 3,67 s de contenu, et la dernière
/// marque servie par le fichier datait de 3,679 s. Tout ce qui suivait tombait
/// « hors des bornes du segment ».
///
/// Le symptôme était d'autant plus trompeur que l'anneau s'arme à la PREMIÈRE tenue
/// de ⌥⌘ : les premières secondes marchaient, et la panne commençait au moment
/// exact où l'utilisateur se mettait à annoter.
///
/// Et personne ne lisait ces pixels. La spécification demandait une COPIE (§ 5.3),
/// précisément pour rendre l'original à la pool ; ici la copie n'a même pas lieu
/// d'être — l'image vient du fichier encodé (S39), et le filet vient de
/// `SCScreenshotManager`. L'anneau n'a besoin que du TEMPS et de la GÉOMÉTRIE.
struct FrameSnapshot: Sendable {
    let sequence: UInt64
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
    /// Des DESCRIPTEURS, pas des tampons. Retenir les tampons épuisait la pool de
    /// ScreenCaptureKit et arrêtait la livraison — voir `FrameSnapshot`.
    private var frames: [(pts: CMTime, ref: FrameRef, t: SessionTime)] = []

    /// Instantanés pris et pas encore réclamés, par numéro de demande.
    private var pris: [UInt64: FrameSnapshot] = [:]
    private let verrouPris = OSAllocatedUnfairLock(initialState: [UInt64: FrameSnapshot]())

    // Comptes de diagnostic — c'est ce qui remplace un test qu'on ne peut pas écrire.
    /// Descripteurs retenus, et descripteurs évités par la double garde. Le nom
    /// parlait de « copies » quand l'anneau retenait des tampons ; il n'en retient
    /// plus, et le compte a changé de sens en même temps que la chose comptée.
    private(set) var copiesFaites = 0
    private(set) var copiesEvitees = 0
    private(set) var apparieesSansFrame = 0

    // Mouvement de la seconde écoulée.
    private var fenetre: [(t: Double, dirty: Double)] = []
    private var motion = MotionSample()

    /// Curseur de lecture des demandes, propre à CET anneau. Touché uniquement
    /// sur `queue`, donc sans verrou.
    private var curseurDemandes: UInt64

    init(queue: DispatchQueue, segmentID: CaptureSegmentID) {
        self.queue = queue
        self.segmentID = segmentID
        // Placé à la fin de ce qui existe déjà : un anneau qui s'ouvre ne doit pas
        // rejouer les pressions d'avant son ouverture.
        self.curseurDemandes = SnapshotRing.shared.curseurActuel
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
        // La MOYENNE, et non la somme. Une somme vaut `fréquence × surface
        // moyenne` : elle fait entrer la fréquence dans l'axe surface et détruit
        // l'indépendance dont le double critère du § 5.4 dépend entièrement. Un
        // spinner de 86×86 px à 15 fps y cumulait 0,0225 et franchissait le seuil
        // de 0,02 — précisément le cas que ce critère existe pour écarter.
        // Elle rendait aussi la ligne du journal illisible : « 14.083 de surface »
        // pour un écran couvert à 94 %.
        motion = MotionSample(
            completeFramesLastSecond: fenetre.count,
            dirtyRatioLastSecond: fenetre.isEmpty ? 0
                : fenetre.map(\.dirty).reduce(0, +) / Double(fenetre.count))

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
        frames.append((pts, ref, t))
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
        let (demandes, fin) = SnapshotRing.shared.drainer(depuis: curseurDemandes)
        curseurDemandes = fin
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
            let snap = FrameSnapshot(sequence: sequence,
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
        [("descripteurs retenus", "\(copiesFaites)"),
         ("évités", "\(copiesEvitees) — double garde"),
         ("appariements sans frame", "\(apparieesSansFrame)")]
    }
}
