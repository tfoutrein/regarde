import Foundation
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// Ring lock-free a producteur unique et consommateur unique — specification § 6.4
//
// Producteur   : le thread du CGEventTap, dans le callback C.
// Consommateur : le thread principal, appele par le display link.
//
// Contrainte du § 6.2 : le callback du tap n'a le droit ni d'allouer, ni d'appeler
// AppKit, ni de prendre un verrou bloquant. Un depassement de son budget declenche
// kCGEventTapDisabledByTimeout et la bascule cesse en silence — le risque R9.
//
// C'est pour cela qu'on n'utilise PAS DispatchQueue.main.async par point : a 1000 Hz
// sur une souris gamer, c'est mille allocations et mille reveils du thread principal
// par seconde. Le § 6.4 l'interdit explicitement.
// ─────────────────────────────────────────────────────────────────────────────

/// Un evenement d'encre, tel que pousse par le tap. Type trivial, copiable sans allocation.
struct InkEvent: Sendable {
    enum Kind: UInt8, Sendable {
        case down = 0
        case drag = 1
        case up = 2
    }

    /// Coordonnees globales, origine haut-gauche de l'ecran principal (espace `CGEvent.location`).
    var x: Double
    var y: Double
    var kind: UInt8
    /// `CGEvent.timestamp` brut, converti plus tard hors du callback (ADR-0007).
    var hostTicks: UInt64
    /// Instant d'entree dans le callback, pour mesurer la latence de bout en bout (T0.7).
    var enqueuedTicks: UInt64
    /// Numero de la demande d'instantane deposee a la PRESSION (S37).
    ///
    /// Zero hors `mouseDown`, et zero quand l'anneau n'est pas arme. Il voyage avec
    /// l'evenement parce que c'est le seul moyen de relier, au relachement, la
    /// marque a la frame prise une seconde plus tot — l'anneau ne tient que 0,27 s,
    /// la chercher au relachement reviendrait a prendre l'ecran d'APRES.
    var snapshot: UInt64 = 0

    var eventKind: Kind { Kind(rawValue: kind) ?? .drag }
    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// File circulaire a capacite fixe, sans verrou, sans allocation apres l'initialisation.
///
/// Dimensionnement : 8192 entrees. Une souris haute frequence emet a 1000 Hz au plus ;
/// un display link a 60 Hz laisse donc une vingtaine d'evenements par cycle. La marge
/// est de trois ordres de grandeur, ce qui rend le debordement theorique plutot que reel —
/// mais il est compte quand meme, parce qu'un compteur silencieux est un bug invisible.
final class InkRing: @unchecked Sendable {
    static let shared = InkRing()

    private let capacity: Int
    private let mask: UInt64
    private let buffer: UnsafeMutablePointer<InkEvent>

    /// Ecrit par le producteur seul, lu par le consommateur.
    private let head = Atomic<UInt64>(0)
    /// Ecrit par le consommateur seul, lu par le producteur.
    private let tail = Atomic<UInt64>(0)
    /// Debordements. Le producteur incremente, n'importe qui lit.
    private let dropped = Atomic<UInt64>(0)

    init(capacity: Int = 8192) {
        precondition(capacity > 0 && (capacity & (capacity - 1)) == 0,
                     "la capacite doit etre une puissance de deux : le masque remplace un modulo")
        self.capacity = capacity
        self.mask = UInt64(capacity - 1)
        self.buffer = .allocate(capacity: capacity)
        self.buffer.initialize(repeating: InkEvent(x: 0, y: 0, kind: 0, hostTicks: 0, enqueuedTicks: 0, snapshot: 0),
                               count: capacity)
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    // MARK: - Producteur (thread du tap, chemin critique)

    /// Publie un evenement. Aucune allocation, aucun verrou, aucun appel systeme.
    ///
    /// - Returns: `false` si la file est pleine ; l'evenement est alors perdu.
    @inline(__always)
    @discardableResult
    func push(_ event: InkEvent) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)

        guard h &- t < UInt64(capacity) else {
            dropped.wrappingAdd(1, ordering: .relaxed)
            return false
        }

        buffer[Int(h & mask)] = event
        // `releasing` publie l'ecriture ci-dessus : le consommateur qui voit ce head
        // voit forcement la donnee complete.
        head.store(h &+ 1, ordering: .releasing)
        return true
    }

    // MARK: - Consommateur (thread principal, display link)

    /// Vide la file dans `sink`. Retourne le nombre d'evenements consommes.
    ///
    /// On draine en une passe plutot que point par point : le rendu applique ensuite
    /// une seule transaction Core Animation pour tout le lot (§ 6.4).
    @discardableResult
    func drain(into sink: (InkEvent) -> Void) -> Int {
        var t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        var count = 0

        while t != h {
            sink(buffer[Int(t & mask)])
            t &+= 1
            count += 1
        }

        if count > 0 { tail.store(t, ordering: .releasing) }
        return count
    }

    /// Nombre d'evenements perdus par debordement depuis le demarrage.
    var droppedCount: UInt64 { dropped.load(ordering: .relaxed) }

    /// Occupation instantanee, pour le diagnostic.
    var pending: Int {
        Int(head.load(ordering: .relaxed) &- tail.load(ordering: .relaxed))
    }

    func reset() {
        // Reservé au demarrage : il n'y a pas de synchronisation entre les deux cotes ici.
        head.store(0, ordering: .relaxed)
        tail.store(0, ordering: .relaxed)
        dropped.store(0, ordering: .relaxed)
    }
}
