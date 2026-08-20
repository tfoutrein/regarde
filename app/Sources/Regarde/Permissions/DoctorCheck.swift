import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Contrat d'une ligne de diagnostic — S11
//
// La règle qui gouverne tout ce fichier, et tout le lot :
//
//     CHAQUE LIGNE EXÉCUTE L'OPÉRATION RÉELLE, PAS SON PRÉFLIGHT.
//
// Le lot 0 a payé pour l'apprendre. Sa sonde annonçait « création du tap : possible »
// parce qu'elle testait un tap `.listenOnly`, qui n'a besoin que de la Surveillance de
// la saisie — pendant que le vrai tap, `.defaultTap`, échouait faute d'Accessibilité.
// Une ligne verte a envoyé chercher le défaut ailleurs pendant un bon moment.
//
// Corollaire, écrit dans le plan : les lignes qui exigent un redémarrage du processus
// doivent le DIRE, au lieu d'afficher un état périmé.
// ─────────────────────────────────────────────────────────────────────────────

/// Ce qu'une ligne de diagnostic rapporte après avoir tenté son opération.
struct CheckResult: Sendable {
    enum Status: Sendable {
        /// L'opération réelle a réussi.
        case ok
        /// Elle a réussi, mais quelque chose mérite d'être signalé.
        case warning
        /// Elle a échoué. `remedy` dit quoi faire.
        case failed
        /// Elle n'a pas pu être tentée — dépend d'une autre ligne en échec.
        case skipped

        var symbol: String {
            switch self {
            case .ok: "✓"
            case .warning: "⚠"
            case .failed: "✗"
            case .skipped: "–"
            }
        }
    }

    let status: Status
    /// Une ligne, ce que l'opération a donné.
    let summary: String
    /// Détails facultatifs : valeurs mesurées, énumérations.
    var detail: [String] = []
    /// Ce que l'utilisateur doit faire. `nil` si rien à faire.
    var remedy: String?
    /// L'état ne peut pas être rafraîchi sans relancer le processus.
    ///
    /// macOS n'accorde certaines autorisations qu'au prochain lancement : afficher
    /// « toujours refusé » après que l'utilisateur a coché la case serait un mensonge.
    var needsRelaunch: Bool = false

    static func ok(_ summary: String, detail: [String] = []) -> CheckResult {
        CheckResult(status: .ok, summary: summary, detail: detail)
    }
    static func warning(_ summary: String, detail: [String] = [], remedy: String? = nil) -> CheckResult {
        CheckResult(status: .warning, summary: summary, detail: detail, remedy: remedy)
    }
    static func failed(_ summary: String, detail: [String] = [], remedy: String? = nil,
                       needsRelaunch: Bool = false) -> CheckResult {
        CheckResult(status: .failed, summary: summary, detail: detail,
                    remedy: remedy, needsRelaunch: needsRelaunch)
    }
}

/// Une ligne du diagnostic.
protocol DoctorCheck: Sendable {
    var id: String { get }
    var title: String { get }
    /// Sans elle, le produit ne fonctionne pas du tout.
    var isRequired: Bool { get }
    /// Volet des Réglages à ouvrir, si la ligne échoue.
    var settingsURL: URL? { get }
    /// Exécute l'opération. Doit être ré-exécutable sans effet de bord : le bouton
    /// « Relancer » l'appelle telle quelle.
    func run() async -> CheckResult
}

extension DoctorCheck {
    var settingsURL: URL? { nil }
}

/// Volets des Réglages, par leur URL directe. Ouvrir le bon volet évite de faire
/// chercher l'utilisateur dans une liste de trente entrées.
enum SettingsPane {
    static let screenRecording = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    static let inputMonitoring = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
}
