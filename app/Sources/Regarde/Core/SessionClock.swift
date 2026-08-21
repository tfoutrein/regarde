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
struct SessionTime: Hashable, Comparable, CustomStringConvertible, Sendable, Codable {
    static let scale: CMTimeScale = 90_000
    let raw: CMTime

    init(seconds: Double) { raw = CMTime(seconds: seconds, preferredTimescale: Self.scale) }
    init(_ t: CMTime) { raw = CMTimeConvertScale(t, timescale: Self.scale, method: .roundHalfAwayFromZero) }

    var seconds: Double { raw.seconds }
    var milliseconds: Double { raw.seconds * 1000 }

    // `CMTime` n'est pas `Codable`, et l'encoder en secondes flottantes perdrait
    // la précision exacte que l'échelle de 90 000 existe pour garantir. On encode
    // le couple valeur/échelle, qui se relit au tick près.
    private enum CodingKeys: String, CodingKey { case value, timescale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raw = CMTime(value: try c.decode(CMTimeValue.self, forKey: .value),
                     timescale: try c.decode(CMTimeScale.self, forKey: .timescale))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(raw.value, forKey: .value)
        try c.encode(raw.timescale, forKey: .timescale)
    }

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
    private let log = Logger(subsystem: logSubsystem, category: "clock")

    /// Les deux origines, sous un même verrou.
    ///
    /// Elles sont MUTABLES : l'origine est posée au lancement, puis RECALÉE à
    /// l'entrée en `arming`. Sans ce recalage, une application lancée le matin
    /// donnerait à la première marque de l'après-midi un `SessionTime` de plusieurs
    /// heures — et `assetTime()` (§ 3.2) le clamperait hors bornes sans qu'aucune
    /// image ne soit jamais extraite. L'origine doit être celle de la SESSION.
    ///
    /// L'origine continue existe parce que `mach_absolute_time` S'ARRÊTE pendant la
    /// veille (§ 3.1, correction 4). Les trois producteurs restent cohérents entre
    /// eux sur l'horloge maîtresse — c'est ce qui compte pour l'appariement — mais
    /// la durée MURALE d'une session interrompue par une veille ne s'en déduit pas.
    /// Un rapport qui annoncerait « session de 4 minutes » pour une session ouverte
    /// avant le déjeuner et fermée après serait faux.
    private struct Origines { var maitresse: CMTime; var continue_: UInt64 }
    private let origines: OSAllocatedUnfairLock<Origines>

    /// Compteurs de diagnostic — lus par le rapport de fin de run.
    private let _fallbacks = OSAllocatedUnfairLock(initialState: 0)

    init() {
        origines = OSAllocatedUnfairLock(
            initialState: Origines(maitresse: CMClockGetTime(CMClockGetHostTimeClock()),
                                   continue_: mach_continuous_time()))
    }

    /// Repose les deux origines. Appelé à l'entrée en `arming`, et là seulement.
    ///
    /// Hors session, l'origine reste celle du dernier recalage — ou celle du
    /// lancement si aucune session n'a encore été ouverte. C'est exactement ce qu'il
    /// faut pour le mode éclair : ses marques tombent après l'origine, donc dans la
    /// fenêtre de validité, donc étiquetées `hardware` sans grossir `fallbackCount`.
    func rearm() {
        let t = CMClockGetTime(master), c = mach_continuous_time()
        origines.withLock { $0 = Origines(maitresse: t, continue_: c) }
        log.notice("origine recalée")
    }

    private var origin: CMTime { origines.withLock { $0.maitresse } }

    /// Instant courant sur la timeline de session.
    func now() -> SessionTime {
        SessionTime(CMTimeSubtract(CMClockGetTime(master), origin))
    }

    /// Durée MURALE depuis l'origine, veille comprise.
    ///
    /// `mach_continuous_time` avance pendant la veille là où `mach_absolute_time`
    /// s'arrête : c'est la seule des deux qui puisse dater une `Interruption`.
    func wallSeconds() -> Double {
        let depuis = origines.withLock { $0.continue_ }
        return Double(mach_continuous_time() &- depuis) * Self.tickToNanos / 1_000_000_000.0
    }

    /// Instant d'un `CGEvent.timestamp` converti vers un PTS de l'horloge maîtresse.
    ///
    /// C'est l'inverse de `now()`, et il sert à `CaptureSegment.assetTime` (S32) :
    /// demander à l'asset la frame d'un `SessionTime` suppose de savoir à quel PTS
    /// il correspond.
    func pts(for t: SessionTime) -> CMTime {
        CMTimeAdd(origin, t.raw)
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
