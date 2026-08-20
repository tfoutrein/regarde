import CoreMedia
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Horloge maitresse — ADR-0007, specification § 3.1
//
// Version lot 0 : reduite a ce dont le prototype a besoin. Il n'y a pas encore de
// SCStream, donc pas de conversion depuis synchronizationClock ; il reste les deux
// choses qui comptent ici, et qui sont deja les pieges du § 3.1 :
//
//   1. CGEvent.timestamp est en unites mach absolues, PAS en secondes.
//   2. CGEvent.timestamp peut valoir 0 sur les evenements synthetiques (Karabiner,
//      BetterTouchTool, pilotes Logitech/Razer, Universal Control, partage d'ecran).
//      Sans validation, une marque posee avec un de ces outils est rejetee en
//      silence — c'est le critere C12.
// ─────────────────────────────────────────────────────────────────────────────

/// Instant relatif au demarrage de la session, en secondes.
struct SessionTime: Hashable, Comparable, CustomStringConvertible, Sendable {
    static let scale: CMTimeScale = 90_000
    let raw: CMTime

    init(seconds: Double) { raw = CMTime(seconds: seconds, preferredTimescale: Self.scale) }
    init(_ t: CMTime) { raw = CMTimeConvertScale(t, timescale: Self.scale, method: .roundHalfAwayFromZero) }

    var seconds: Double { raw.seconds }
    var milliseconds: Double { raw.seconds * 1000 }

    static func < (a: Self, b: Self) -> Bool { a.raw < b.raw }
    var description: String { String(format: "%.3fs", seconds) }
}

/// Origine de l'horodatage d'un evenement, journalisee pour le diagnostic.
enum TimestampOrigin: String, Sendable {
    /// `CGEvent.timestamp` valide, converti depuis la base hote.
    case hardware
    /// Timestamp aberrant ou nul : repli sur l'instant de traitement.
    /// C'est le chemin qu'empruntent les evenements synthetiques (C12).
    case fallbackNow
}

struct StampedTime: Sendable {
    let time: SessionTime
    let origin: TimestampOrigin
}

final class SessionClock: @unchecked Sendable {
    static let shared = SessionClock()

    private let master = CMClockGetHostTimeClock()
    private let origin: CMTime
    private let log = Logger(subsystem: logSubsystem, category: "clock")

    /// Compteurs de diagnostic — lus par le rapport de fin de run.
    private let _fallbacks = OSAllocatedUnfairLock(initialState: 0)

    init() {
        origin = CMClockGetTime(master)
    }

    /// Instant courant sur la timeline de session.
    func now() -> SessionTime {
        SessionTime(CMTimeSubtract(CMClockGetTime(master), origin))
    }

    /// Convertit un `CGEvent.timestamp` (unites mach absolues) vers la timeline de session.
    ///
    /// Retourne toujours un instant utilisable : le prototype ne doit jamais perdre une
    /// marque a cause d'un horodatage aberrant. L'origine dit s'il est fiable.
    func stamp(hostTicks: UInt64) -> StampedTime {
        guard hostTicks != 0 else { return fallback(reason: "timestamp nul") }

        let converted = SessionTime(CMTimeSubtract(CMClockMakeHostTimeFromSystemUnits(hostTicks), origin))
        let current = now().seconds

        // Fenetre de validite : [t0, maintenant + 50 ms]. Un evenement ne peut pas
        // preceder l'ouverture de la session ni venir d'un futur non trivial.
        guard converted.seconds >= -0.001, converted.seconds <= current + 0.050 else {
            return fallback(reason: String(format: "hors fenetre (%.3fs vs %.3fs)", converted.seconds, current))
        }
        return StampedTime(time: converted, origin: .hardware)
    }

    private func fallback(reason: String) -> StampedTime {
        let n = _fallbacks.withLock { (c: inout Int) -> Int in c += 1; return c }
        // Journaliser les premiers seulement : avec un pilote tiers, ils arrivent en rafale.
        if n <= 5 || n % 500 == 0 {
            log.notice("timestamp materiel inutilisable (\(reason, privacy: .public)) — repli, occurrence \(n)")
        }
        return StampedTime(time: now(), origin: .fallbackNow)
    }

    var fallbackCount: Int { _fallbacks.withLock { $0 } }

    /// Instant courant en unites mach absolues, pour horodater sans passer par CMTime
    /// dans un chemin ou l'allocation est proscrite.
    static func hostTicksNow() -> UInt64 { mach_absolute_time() }

    /// Duree en millisecondes entre deux mesures en unites mach absolues.
    static func millis(from a: UInt64, to b: UInt64) -> Double {
        guard b > a else { return 0 }
        return Double(b - a) * Self.tickToNanos / 1_000_000.0
    }

    private static let tickToNanos: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()
}
