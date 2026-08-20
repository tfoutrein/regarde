import AVFoundation
import Carbon.HIToolbox
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

// ─────────────────────────────────────────────────────────────────────────────
// Les lignes du diagnostic — S11
//
// Chacune tente l'opération réelle. Quand l'opération réelle est dangereuse, on le dit
// explicitement plutôt que de la contourner en silence : voir `TapCreationCheck`.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Enregistrement de l'écran

/// Opération réelle : demander le contenu partageable.
///
/// `CGPreflightScreenCaptureAccess` ne suffit pas — il répond sur l'état enregistré par
/// TCC, alors que l'autorisation expire environ tous les mois et que l'échec ne se
/// manifeste qu'à l'appel effectif.
struct ScreenRecordingCheck: DoctorCheck {
    let id = "screen"
    let title = "Enregistrement de l'écran"
    let isRequired = true
    var settingsURL: URL? { SettingsPane.screenRecording }

    func run() async -> CheckResult {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            let displays = content.displays.map { d in
                "display \(d.displayID) — \(d.width)×\(d.height) px"
            }
            return .ok("\(content.displays.count) écran(s) accessibles", detail: displays)
        } catch {
            return .failed(
                "contenu partageable refusé",
                detail: [error.localizedDescription],
                remedy: "Autorise Regarde dans Enregistrement de l'écran, puis relance l'application.",
                needsRelaunch: true
            )
        }
    }
}

// MARK: - Surveillance de la saisie

/// Opération réelle : créer un tap en lecture seule, puis l'invalider aussitôt.
///
/// Volontairement `.listenOnly` : un tap consommateur armé en tête de chaîne HID que
/// personne ne draine retiendrait les événements de l'utilisateur le temps de son
/// existence. Le risque a été relevé par la revue du lot 0 et n'est pas pris ici.
/// La capacité de consommer est vérifiée séparément, par `TapCreationCheck`.
struct InputMonitoringCheck: DoctorCheck {
    let id = "input"
    let title = "Surveillance de la saisie"
    let isRequired = true
    var settingsURL: URL? { SettingsPane.inputMonitoring }

    func run() async -> CheckResult {
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        guard let probe = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return .failed(
                "création d'un tap en lecture impossible",
                remedy: "Autorise Regarde dans Surveillance de la saisie, puis relance l'application.",
                needsRelaunch: true
            )
        }
        CFMachPortInvalidate(probe)
        return .ok("un tap en lecture a pu être créé")
    }
}

// MARK: - Accessibilité

/// Opération réelle : lire un attribut d'accessibilité d'une AUTRE application.
///
/// `AXIsProcessTrusted()` est un préflight : il consulte l'état enregistré. Lire un
/// attribut d'un processus voisin échoue réellement quand l'autorisation manque, ce qui
/// est le seul verdict qui compte. Opération en lecture pure, sans effet de bord.
struct AccessibilityCheck: DoctorCheck {
    let id = "ax"
    let title = "Accessibilité"
    let isRequired = true
    var settingsURL: URL? { SettingsPane.accessibility }

    func run() async -> CheckResult {
        let trusted = AXIsProcessTrusted()

        // Chercher une cible autre que soi : interroger sa propre application réussit
        // toujours et ne prouverait rien.
        let target = await MainActor.run {
            NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }?.processIdentifier
        }

        guard let pid = target else {
            return .warning(
                trusted ? "autorisée (aucune application témoin pour le vérifier)"
                        : "non accordée (aucune application témoin pour le vérifier)",
                remedy: trusted ? nil : "Autorise Regarde dans Accessibilité, puis relance l'application."
            )
        }

        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)

        switch status {
        case .success, .noValue, .attributeUnsupported:
            // L'appel a abouti : l'accès est accordé, même si l'attribut est vide.
            return .ok("lecture d'un attribut d'une autre application réussie")
        case .apiDisabled, .notImplemented, .cannotComplete:
            return .failed(
                "lecture refusée par le système (AXError \(status.rawValue))",
                detail: trusted ? ["AXIsProcessTrusted() répond pourtant « autorisé » — état enregistré périmé"] : [],
                remedy: "Autorise Regarde dans Accessibilité, puis relance l'application.",
                needsRelaunch: true
            )
        default:
            return .warning("réponse inattendue du système (AXError \(status.rawValue))")
        }
    }
}

// MARK: - Création effective du tap

/// La ligne qui compte : le produit repose sur un tap qui CONSOMME des événements,
/// et celui-là exige Surveillance de la saisie **et** Accessibilité.
///
/// On ne crée pas de `.defaultTap` pour le vérifier — un tap consommateur non drainé
/// retiendrait les événements de l'utilisateur. Le verdict est donc composé à partir des
/// deux lignes précédentes, et le dit franchement plutôt que d'annoncer un test qui n'a
/// pas eu lieu. C'est la correction du défaut du lot 0, où une sonde en lecture seule
/// annonçait « possible » pour un tap qui échouait.
struct TapCreationCheck: DoctorCheck {
    let id = "tap"
    let title = "Arbitrage des événements (le geste)"
    let isRequired = true

    let inputOK: Bool
    let axOK: Bool

    func run() async -> CheckResult {
        switch (inputOK, axOK) {
        case (true, true):
            return .ok(
                "les deux autorisations du tap consommateur sont réunies",
                detail: ["Vérifié par composition : un tap .defaultTap non drainé retiendrait les événements, on ne le crée pas pour tester."]
            )
        case (false, true):
            return .failed("Surveillance de la saisie manquante",
                           remedy: "Le tap ne pourra pas être créé.")
        case (true, false):
            return .failed(
                "Accessibilité manquante",
                detail: ["Un tap en lecture fonctionne, mais le produit doit CONSOMMER les événements — ce qui exige l'Accessibilité en plus."],
                remedy: "C'est le cas exact qui a fait échouer le prototype du lot 0."
            )
        case (false, false):
            return .failed("les deux autorisations manquent",
                           remedy: "Accorde Surveillance de la saisie et Accessibilité.")
        }
    }
}

// MARK: - Micro

/// Le statut suffit ici : ouvrir réellement le micro allumerait l'indicateur orange et
/// demanderait l'autorisation, ce qui n'a pas sa place dans un diagnostic. Le micro
/// n'est utilisé qu'au lot 5 ; sa ligne sert à connaître l'état, pas à l'exercer.
struct MicrophoneCheck: DoctorCheck {
    let id = "mic"
    let title = "Microphone"
    let isRequired = false
    var settingsURL: URL? { SettingsPane.microphone }

    func run() async -> CheckResult {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .ok("accordé", detail: ["Utilisé à partir du lot 5."])
        case .notDetermined:
            return .warning("jamais demandé", detail: ["Sera demandé au lot 5, pas avant."])
        case .denied, .restricted:
            return .warning("refusé",
                            remedy: "Sans micro, seuls la palette d'intentions et le clavier resteront (lot 5).")
        @unknown default:
            return .warning("état inconnu")
        }
    }
}

// MARK: - Saisie sécurisée

/// `IsSecureEventInputEnabled()` : vrai quand un champ de mot de passe a le focus.
/// Les événements souris continuent de passer, mais l'état doit être connu — le § 6.3
/// impose de fermer la fenêtre de parole quand il bascule.
struct SecureInputCheck: DoctorCheck {
    let id = "secure"
    let title = "Saisie sécurisée"
    let isRequired = false

    func run() async -> CheckResult {
        IsSecureEventInputEnabled()
            ? .warning("active — un champ de mot de passe a le focus",
                       detail: ["Les événements souris passent malgré tout ; la fenêtre de parole se fermera d'office (§ 6.3)."])
            : .ok("inactive")
    }
}

// MARK: - Écrans

/// Énumère les écrans avec leur échelle et leur position. Les origines négatives et les
/// échelles mixtes sont la source des décalages de coordonnées du § 3.3 : les voir ici
/// évite de les diagnostiquer à l'aveugle plus tard.
struct DisplaysCheck: DoctorCheck {
    let id = "displays"
    let title = "Écrans"
    let isRequired = false

    func run() async -> CheckResult {
        let lines = await MainActor.run {
            NSScreen.screens.map { s -> String in
                let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                let negative = s.frame.minX < 0 || s.frame.minY < 0 ? "  ← origine négative" : ""
                return String(format: "display %u — %.0f×%.0f pt @%.0f× à (%.0f, %.0f)%@",
                              id, s.frame.width, s.frame.height, s.backingScaleFactor,
                              s.frame.minX, s.frame.minY, negative)
            }
        }
        let scales = await MainActor.run { Set(NSScreen.screens.map(\.backingScaleFactor)) }
        var detail = lines
        if scales.count > 1 {
            detail.append("Échelles mixtes : ne jamais supposer un facteur global (§ 3.3).")
        }
        return .ok("\(lines.count) écran(s)", detail: detail)
    }
}

// MARK: - Périphériques audio

/// Repère les pilotes de boucle. Sur la machine de développement, l'entrée par défaut
/// peut être « Microsoft Teams Audio » : une session transcrirait alors une
/// visioconférence au lieu de la voix de l'utilisateur (§ 7.2).
struct AudioDevicesCheck: DoctorCheck {
    let id = "audio"
    let title = "Périphériques d'entrée audio"
    let isRequired = false

    private static let loopbackMarkers = [
        "loopback", "blackhole", "soundflower", "vb-cable", "teams", "zoom",
        "aggregate", "multi-output", "virtual",
    ]

    func run() async -> CheckResult {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        guard !session.devices.isEmpty else {
            return .warning("aucun périphérique d'entrée détecté")
        }

        var detail: [String] = []
        var loopbacks: [String] = []
        for device in session.devices {
            let name = device.localizedName
            let isLoopback = Self.loopbackMarkers.contains { name.lowercased().contains($0) }
            if isLoopback { loopbacks.append(name) }
            detail.append("\(name)\(isLoopback ? "  ← pilote de boucle, à exclure" : "")")
        }

        if loopbacks.isEmpty {
            return .ok("\(session.devices.count) périphérique(s)", detail: detail)
        }
        return .warning(
            "\(loopbacks.count) pilote(s) de boucle détecté(s)",
            detail: detail,
            remedy: "Le lot 5 les exclura de la sélection : capturer l'un d'eux transcrirait une visioconférence."
        )
    }
}

// MARK: - Confidentialité du répertoire de travail

/// Opération réelle : créer un répertoire de session, y écrire un fichier, relire ses
/// permissions. Vérifier `0700` sur un répertoire qu'on n'a pas créé ne prouverait rien.
///
/// Cette ligne existe parce que le fichier vidéo intermédiaire est le seul artefact du
/// produit dont la fuite serait un incident plutôt qu'un bug (§ 10.2).
struct WorkspaceCheck: DoctorCheck {
    let id = "workspace"
    let title = "Répertoire de travail sécurisé"
    let isRequired = false

    func run() async -> CheckResult {
        do {
            let dir = try SecureWorkspace.beginSession()
            let probe = dir.appendingPathComponent("probe")
            let handle = try SecureWorkspace.createFile(at: probe)
            try handle.write(contentsOf: Data("témoin".utf8))
            try handle.close()

            let fm = FileManager.default
            let dirPerms = (try fm.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber)?.intValue
            let filePerms = (try fm.attributesOfItem(atPath: probe.path)[.posixPermissions] as? NSNumber)?.intValue

            var detail = SecureWorkspace.audit()
            detail.append("répertoire créé en \(String(dirPerms ?? 0, radix: 8))")
            detail.append("fichier créé en \(String(filePerms ?? 0, radix: 8))")

            // `O_EXCL` doit refuser une seconde création au même chemin.
            var exclusiveHeld = false
            do { _ = try SecureWorkspace.createFile(at: probe) }
            catch { exclusiveHeld = true }
            detail.append(exclusiveHeld
                ? "O_EXCL refuse bien une seconde création"
                : "⚠ O_EXCL n'a pas refusé la seconde création")

            guard dirPerms == 0o700, filePerms == 0o600, exclusiveHeld else {
                return .warning("permissions inattendues", detail: detail,
                                remedy: "Le fichier vidéo intermédiaire contient tout l'écran.")
            }
            return .ok("0700 / 0600 / O_EXCL vérifiés sur un fichier réel", detail: detail)
        } catch {
            return .warning("impossible de préparer un répertoire de session",
                            detail: [error.localizedDescription])
        }
    }
}

/// Vérifie ce qui sera exclu de la capture, en confrontant la liste noire aux
/// applications réellement en cours d'exécution.
struct ExclusionsCheck: DoctorCheck {
    let id = "exclusions"
    let title = "Applications exclues de la capture"
    let isRequired = false

    func run() async -> CheckResult {
        let (blocked, ownID) = await MainActor.run {
            (Set(CaptureExclusions.shared.bundleIDs), Bundle.main.bundleIdentifier)
        }
        let lines = await TCCContact.shared.auditExclusions(blocked: blocked, ownBundleID: ownID)
        let hasWarning = lines.contains { $0.hasPrefix("⚠") }
        return hasWarning
            ? .warning(lines.first ?? "", detail: Array(lines.dropFirst()))
            : .ok(lines.first ?? "", detail: Array(lines.dropFirst()))
    }
}
