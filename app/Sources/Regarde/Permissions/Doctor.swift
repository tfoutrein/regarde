import AppKit
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le doctor — orchestration des lignes de diagnostic (S11)
//
// Deux règles héritées du lot 0 :
//
//   1. Le verdict global se compose des lignes REQUISES uniquement. Une ligne
//      facultative en avertissement ne doit pas faire croire que rien ne marche.
//
//   2. La ligne « arbitrage des événements » est calculée à partir des deux
//      autorisations qu'elle exige, et non testée directement — créer un tap
//      consommateur non drainé pour le vérifier retiendrait les événements de
//      l'utilisateur. C'est la correction du défaut du lot 0.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class Doctor {
    static let shared = Doctor()

    struct Row: Identifiable, Sendable {
        let id: String
        let title: String
        let isRequired: Bool
        let settingsURL: URL?
        var result: CheckResult?
        var isRunning: Bool = false
    }

    private(set) var rows: [Row] = []
    private(set) var lastRun: Date?
    private(set) var isRunning = false

    /// Verdict global, sur les seules lignes requises.
    var verdict: CheckResult.Status {
        let required = rows.filter(\.isRequired).compactMap(\.result)
        guard required.count == rows.filter(\.isRequired).count else { return .skipped }
        if required.contains(where: { $0.status == .failed }) { return .failed }
        if required.contains(where: { $0.status == .warning }) { return .warning }
        return .ok
    }

    var needsRelaunch: Bool {
        rows.compactMap(\.result).contains { $0.needsRelaunch }
    }

    private init() {
        rows = Self.baseChecks.map {
            Row(id: $0.id, title: $0.title, isRequired: $0.isRequired, settingsURL: $0.settingsURL)
        }
        // La ligne du tap se compose des deux précédentes : sa place est réservée ici,
        // son résultat calculé à la fin de chaque passe.
        rows.insert(Row(id: "tap", title: "Arbitrage des événements (le geste)",
                        isRequired: true, settingsURL: nil),
                    at: 3)
    }

    private static let baseChecks: [any DoctorCheck] = [
        ScreenRecordingCheck(),
        InputMonitoringCheck(),
        AccessibilityCheck(),
        MicrophoneCheck(),
        SecureInputCheck(),
        DisplaysCheck(),
        AudioDevicesCheck(),
        WorkspaceCheck(),
        ExclusionsCheck(),
    ]

    // MARK: - Exécution

    /// Rejoue toutes les lignes. Le bouton « Tout relancer » l'appelle telle quelle :
    /// aucune ligne ne conserve d'état entre deux passes.
    func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        for check in Self.baseChecks {
            await run(check)
        }
        await composeTapRow()

        lastRun = Date()
        Journal.section("Diagnostic", describe())
    }

    /// Rejoue une seule ligne. La ligne du tap se recompose, elle ne s'exécute pas.
    func run(id: String) async {
        if id == "tap" {
            await composeTapRow()
            return
        }
        guard let check = Self.baseChecks.first(where: { $0.id == id }) else { return }
        await run(check)
        // Les deux autorisations du tap ont pu changer : recomposer plutôt que de
        // laisser une ligne dérivée devenir périmée.
        if check.id == "input" || check.id == "ax" { await composeTapRow() }
        lastRun = Date()
    }

    private func run(_ check: any DoctorCheck) async {
        setRunning(check.id, true)
        let result = await check.run()
        apply(check.id, result)
    }

    private func composeTapRow() async {
        setRunning("tap", true)
        let inputOK = result(for: "input")?.status == .ok
        let axOK = result(for: "ax")?.status == .ok
        let result = await TapCreationCheck(inputOK: inputOK, axOK: axOK).run()
        apply("tap", result)
    }

    private func setRunning(_ id: String, _ value: Bool) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].isRunning = value
    }

    private func apply(_ id: String, _ result: CheckResult) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].result = result
        rows[i].isRunning = false
    }

    func result(for id: String) -> CheckResult? {
        rows.first { $0.id == id }?.result
    }

    // MARK: - Actions

    func openSettings(for row: Row) {
        guard let url = row.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Relance l'application. Nécessaire quand macOS n'accorde une autorisation qu'au
    /// prochain lancement — l'utilisateur ne doit pas avoir à le deviner.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    // MARK: - Diagnostic textuel

    func describe() -> [String] {
        var lines: [String] = []
        for row in rows {
            guard let r = row.result else {
                lines.append("· \(row.title) — non exécutée")
                continue
            }
            let tag = row.isRequired ? "" : "  (facultatif)"
            lines.append("\(r.status.symbol) \(row.title) — \(r.summary)\(tag)")
            for d in r.detail { lines.append("    \(d)") }
            if let remedy = r.remedy { lines.append("    → \(remedy)") }
            if r.needsRelaunch { lines.append("    → relance nécessaire pour rafraîchir cet état") }
        }
        lines.append("")
        lines.append("verdict : \(verdict.symbol) \(verdictLabel)")
        return lines
    }

    var verdictLabel: String {
        switch verdict {
        case .ok: "tout est en place"
        case .warning: "utilisable, avec des réserves"
        case .failed: "une autorisation requise manque"
        case .skipped: "diagnostic incomplet"
        }
    }
}
