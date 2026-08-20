import Foundation
import ScreenCaptureKit
import os

// ─────────────────────────────────────────────────────────────────────────────
// Liste noire d'applications — ADR-0020, spécification § 10.3
//
// `SCContentFilter(display:excludingApplications:)` accepte déjà une liste, puisqu'on
// s'en sert pour s'exclure soi-même. L'étendre à des applications sensibles coûte une
// ligne et supprime une classe entière d'incidents : un gestionnaire de mots de passe
// ouvert derrière la fenêtre testée n'est jamais enregistré, même par accident.
//
// L'argument comportemental compte autant que l'argument technique. La première fois
// qu'un développeur voit une notification privée dans une capture partie chez un tiers,
// il ferme tout avant chaque session — ou n'utilise plus l'outil.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CaptureExclusions {
    static let shared = CaptureExclusions()

    private let log = Logger(subsystem: logSubsystem, category: "exclusions")
    private let defaultsKey = "captureExclusions.bundleIDs"

    /// Applications exclues par défaut. Choisies parce que leur contenu est
    /// systématiquement sensible, pas parce qu'il pourrait l'être.
    static let defaults: [String] = [
        "com.1password.1password",       // 1Password 8
        "com.agilebits.onepassword7",    // 1Password 7
        "com.apple.keychainaccess",      // Trousseau d'accès
        "com.apple.MobileSMS",           // Messages
        "com.apple.mail",                // Mail
        "org.whispersystems.signal-desktop",
        "desktop.WhatsApp",
        "com.tinyspeck.slackmacgap",     // Slack — messages professionnels
    ]

    private init() {}

    /// Identifiants exclus, réglage utilisateur compris.
    var bundleIDs: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: defaultsKey) ?? Self.defaults
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Applications à passer à `SCContentFilter`, en s'incluant soi-même.
    ///
    /// L'auto-exclusion est la plus importante des deux : sans elle, le calque et ses
    /// tracés se retrouveraient gravés dans les pixels capturés, et l'agent recevrait
    /// des numéros en double (risque R12).
    ///
    /// `sharingType = .none` sur les panneaux est une seconde ligne de défense, et le
    /// lot 0 a montré qu'elle fonctionne réellement sur macOS 26.1 — un trait existant
    /// n'apparaissait ni dans `screencapture` ni dans ScreenCaptureKit — alors que la
    /// spécification la donnait pour ignorée depuis macOS 15.4. On ne s'y fie pas pour
    /// autant : l'exclusion par application couvre aussi les fenêtres créées après coup.
    func applicationsToExclude(from content: SCShareableContent) -> [SCRunningApplication] {
        let blocked = excludedBundleIDs
        return content.applications.filter { blocked.contains($0.bundleIdentifier) }
    }

    /// La même liste, réduite à des chaînes.
    ///
    /// `SCRunningApplication` n'est pas `Sendable` : le filtrage ne peut donc pas
    /// traverser une frontière d'isolation. Ce sont les identifiants qui voyagent, et le
    /// filtre se refait de l'autre côté sur le contenu local.
    var excludedBundleIDs: Set<String> {
        var ids = Set(bundleIDs)
        if let own = Bundle.main.bundleIdentifier { ids.insert(own) }
        return ids
    }

}
