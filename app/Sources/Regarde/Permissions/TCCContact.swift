import Foundation
import ScreenCaptureKit
import Synchronization
import os

// ─────────────────────────────────────────────────────────────────────────────
// Prise de contact TCC — specification § 11.3 lot 1, parade au risque R1
//
// macOS redemande l'autorisation d'enregistrement de l'ecran environ une fois par mois,
// et l'invite apparait au premier appel touchant au contenu partageable. Si cet appel
// a lieu au raccourci d'ouverture de session, l'invite vole le focus au moment precis
// ou l'utilisateur voulait capturer quelque chose — et lui fait perdre ce qu'il voulait
// montrer.
//
// D'ou la regle : `SCShareableContent` est appele au lancement, au reveil et par
// sondage horaire. JAMAIS depuis le chemin d'une session.
//
// Le resultat est mis en cache. Le lot 0 a montre qu'un TTL court annule tout le
// benefice : un rafraichissement toutes les 30 s ramenait l'appel dans le chemin du
// geste et polluait la mesure de latence de 34 ms de mediane et 486 ms au pire.
// ─────────────────────────────────────────────────────────────────────────────

actor TCCContact {
    static let shared = TCCContact()

    private let log = Logger(subsystem: logSubsystem, category: "tcc")

    private var content: SCShareableContent?
    private var lastSuccess: Date?
    private var lastFailure: String?
    private var probeTimer: Timer?

    enum Trigger: String, Sendable {
        case launch, wake, hourly, settings
    }

    /// Contenu partageable en cache. `nil` si l'autorisation manque ou a expire.
    var cachedContent: SCShareableContent? { content }
    var lastError: String? { lastFailure }
    var freshness: TimeInterval? { lastSuccess.map { Date().timeIntervalSince($0) } }

    /// Rafraichit le cache. Hors chemin de session, toujours.
    nonisolated func refresh(trigger: Trigger) {
        Task { await self.performRefresh(trigger: trigger) }
    }

    private func performRefresh(trigger: Trigger) async {
        do {
            let fresh = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            content = fresh
            lastSuccess = Date()
            lastFailure = nil
            log.notice("contenu partageable rafraîchi (\(trigger.rawValue, privacy: .public)) — \(fresh.displays.count) écran(s)")
        } catch {
            // Le cache est vide plutot que perime : mieux vaut un echec explicite qu'une
            // capture silencieuse du mauvais ecran.
            content = nil
            lastFailure = error.localizedDescription
            log.notice("contenu partageable indisponible (\(trigger.rawValue, privacy: .public)) : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sondage horaire : detecte l'expiration mensuelle avant que l'utilisateur ne la
    /// decouvre en pleine session.
    func startHourlyProbe() {
        probeTimer?.invalidate()
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            TCCContact.shared.refresh(trigger: .hourly)
        }
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer
    }
}
