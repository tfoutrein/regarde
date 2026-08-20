import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// T0.7 — Instrumentation de latence
//
// Mesure : de `CGEvent.timestamp` a l'entree du callback du tap, jusqu'au commit de
// la transaction Core Animation qui porte le nouveau trait. C'est la latence que
// l'utilisateur ressent, pas celle du callback seul.
//
// Cible : p95 < 33 ms, objectif < 16 ms (critere C7).
//
// Histogramme a intervalles fixes plutot que conservation des echantillons : la
// memoire est bornee, et un quantile sur des intervalles de 0,5 ms est largement
// assez precis pour un seuil exprime en dizaines de millisecondes.
// ─────────────────────────────────────────────────────────────────────────────

final class LatencyHistogram: @unchecked Sendable {
    static let shared = LatencyHistogram()

    private static let bucketMs = 0.5
    private static let bucketCount = 400          // 0 a 200 ms
    private static let overflowIndex = bucketCount - 1

    private struct State {
        var buckets = [UInt32](repeating: 0, count: LatencyHistogram.bucketCount)
        var count: UInt64 = 0
        var sumMs: Double = 0
        var maxMs: Double = 0
        var overflow: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func record(millis: Double) {
        guard millis.isFinite, millis >= 0 else { return }
        state.withLock { s in
            let idx = Int(millis / Self.bucketMs)
            if idx >= Self.bucketCount {
                s.buckets[Self.overflowIndex] &+= 1
                s.overflow &+= 1
            } else {
                s.buckets[idx] &+= 1
            }
            s.count &+= 1
            s.sumMs += millis
            if millis > s.maxMs { s.maxMs = millis }
        }
    }

    struct Summary: Sendable {
        var count: UInt64
        var p50: Double
        var p95: Double
        var p99: Double
        var mean: Double
        var max: Double
        var overflow: UInt64

        var passesC7: Bool { count > 0 && p95 < 33.0 }
        var meetsTarget: Bool { count > 0 && p95 < 16.0 }
    }

    func summary() -> Summary {
        state.withLock { s in
            guard s.count > 0 else {
                return Summary(count: 0, p50: 0, p95: 0, p99: 0, mean: 0, max: 0, overflow: 0)
            }
            return Summary(
                count: s.count,
                p50: Self.quantile(s, 0.50),
                p95: Self.quantile(s, 0.95),
                p99: Self.quantile(s, 0.99),
                mean: s.sumMs / Double(s.count),
                max: s.maxMs,
                overflow: s.overflow
            )
        }
    }

    private static func quantile(_ s: State, _ q: Double) -> Double {
        let target = UInt64((Double(s.count) * q).rounded(.up))
        var running: UInt64 = 0
        for (i, n) in s.buckets.enumerated() where n > 0 {
            running &+= UInt64(n)
            if running >= target {
                // Milieu de l'intervalle : l'erreur est bornee a 0,25 ms.
                return (Double(i) + 0.5) * bucketMs
            }
        }
        return s.maxMs
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    /// Rapport lisible, avec le verdict C7 explicite.
    ///
    /// Pas de cadre ASCII : aligner une bordure droite sur des `%6.2f` et des `%llu` de
    /// largeur variable demande de recompter les colonnes a chaque modification, et le
    /// cadre finit toujours par etre faux. Un titre souligne ne peut pas se desaligner.
    func report() -> String {
        let s = summary()
        guard s.count > 0 else {
            return "\nLatence tap → commit (T0.7)\n"
                 + "  aucun echantillon — trace au moins un trait avant de mesurer.\n"
        }

        var lines = [
            "",
            "Latence tap → commit (T0.7)",
            "───────────────────────────",
            String(format: "  echantillons  %llu", s.count),
            String(format: "  p50 %.2f ms   p95 %.2f ms   p99 %.2f ms", s.p50, s.p95, s.p99),
            String(format: "  moyenne %.2f ms   max %.2f ms", s.mean, s.max),
        ]
        if s.overflow > 0 {
            lines.append(String(format: "  ⚠ %llu echantillon(s) au-dela de 200 ms", s.overflow))
        }
        lines.append(String(format: "  C7 (p95 < 33 ms) : %@   objectif < 16 ms : %@",
                            s.passesC7 ? "PASS" : "FAIL",
                            s.meetsTarget ? "atteint" : "non"))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Forme exportable, a coller dans RESULTATS.md.
    func json() -> String {
        let s = summary()
        return """
        {
          "echantillons": \(s.count),
          "p50Ms": \(String(format: "%.2f", s.p50)),
          "p95Ms": \(String(format: "%.2f", s.p95)),
          "p99Ms": \(String(format: "%.2f", s.p99)),
          "moyenneMs": \(String(format: "%.2f", s.mean)),
          "maxMs": \(String(format: "%.2f", s.max)),
          "c7": "\(s.passesC7 ? "PASS" : "FAIL")",
          "objectif16ms": \(s.meetsTarget)
        }
        """
    }
}
