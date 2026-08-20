import AppKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Interface du diagnostic — S12
//
// Critère de fin : trois clics maximum de la ligne rouge à la ligne verte.
// D'où la disposition : chaque ligne en échec porte SON bouton de réglages et SON
// bouton de relance, plutôt qu'un bouton global qui obligerait à chercher quelle
// ligne il concerne.
//
//   clic 1 — « Réglages… » ouvre le bon volet, déjà déroulé sur la bonne section
//   clic 2 — l'utilisateur coche la case dans les Réglages
//   clic 3 — « Relancer » (ou « Relancer l'application » si le système l'exige)
// ─────────────────────────────────────────────────────────────────────────────

struct DoctorView: View {
    @State private var doctor = Doctor.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(doctor.rows) { row in
                        DoctorRowView(row: row)
                        Divider().opacity(0.4)
                    }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 460)
        .task { if doctor.rows.allSatisfy({ $0.result == nil }) { await doctor.runAll() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: verdictSymbol)
                .font(.system(size: 26))
                .foregroundStyle(verdictColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(doctor.verdictLabel)
                    .font(.headline)
                Text("Chaque ligne exécute l'opération réelle, pas son préflight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if doctor.isRunning { ProgressView().controlSize(.small) }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if doctor.needsRelaunch {
                // Mis en avant seulement quand le système l'exige : un bouton de relance
                // toujours visible inciterait à relancer pour rien.
                Button("Relancer l'application") { doctor.relaunch() }
                    .buttonStyle(.borderedProminent)
                Text("macOS n'appliquera pas l'autorisation avant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let last = doctor.lastRun {
                Text("dernière passe \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("Tout relancer") { Task { await doctor.runAll() } }
                .disabled(doctor.isRunning)
        }
        .padding(12)
    }

    private var verdictSymbol: String {
        switch doctor.verdict {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "clock"
        }
    }

    private var verdictColor: Color {
        switch doctor.verdict {
        case .ok: .green
        case .warning: .orange
        case .failed: .red
        case .skipped: .secondary
        }
    }
}

private struct DoctorRowView: View {
    let row: Doctor.Row
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                statusIcon
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title).fontWeight(.medium)
                        if !row.isRequired {
                            Text("facultatif")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    Text(row.result?.summary ?? "en attente")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Les actions ne s'affichent que sur les lignes qui en ont besoin :
                // un bouton par ligne verte ferait chercher lequel compte.
                if let result = row.result, result.status != .ok {
                    if row.settingsURL != nil {
                        Button("Réglages…") { Doctor.shared.openSettings(for: row) }
                    }
                    Button("Relancer") { Task { await Doctor.shared.run(id: row.id) } }
                        .disabled(row.isRunning)
                }
            }

            if let result = row.result {
                if let remedy = result.remedy {
                    Text(remedy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
                if result.needsRelaunch {
                    Label("Relance nécessaire pour rafraîchir cet état.", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 28)
                }
                if !result.detail.isEmpty {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(result.detail, id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.top, 2)
                    } label: {
                        Text("\(result.detail.count) détail(s)").font(.caption)
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(row.isRunning ? 0.5 : 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if row.isRunning {
            ProgressView().controlSize(.small)
        } else {
            switch row.result?.status {
            case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .failed:  Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            case nil:      Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            }
        }
    }
}
