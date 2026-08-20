import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// T0.3 — Preflights des quatre permissions
//
// Fini quand : on revoque une permission dans Reglages, on relance, et le journal
// NOMME la permission manquante.
//
// C'est la tache la plus rentable du lot 0. Le § 2.2 du plan est explicite : le
// debogage TCC est aveugle — tapCreate renvoie nil, la capture sort noire, aucune
// exception n'est levee. Sans ce diagnostic, chaque panne coute une soiree.
//
// Regle absolue : ces appels sont TOUS des `preflight`, jamais des `request`. Un
// appel qui demande une permission ouvre une invite systeme et vole le focus. Au
// lot 0 on veut savoir, pas demander.
// ─────────────────────────────────────────────────────────────────────────────

enum PermissionState: String, Sendable {
    case granted = "accordee"
    case denied = "refusee"
    case undetermined = "jamais demandee"

    var symbol: String {
        switch self {
        case .granted: "✓"
        case .denied: "✗"
        case .undetermined: "?"
        }
    }
}

struct PermissionCheck: Sendable {
    let name: String
    let state: PermissionState
    let required: Bool
    /// Chemin exact dans Reglages, parce que le retrouver soi-meme coute une minute
    /// a chaque fois et qu'on le fera des dizaines de fois.
    let settingsPath: String
    let note: String?
}

enum Preflight {
    private static let log = Logger(subsystem: logSubsystem, category: "preflight")

    static func runAll() -> [PermissionCheck] {
        [inputMonitoring(), accessibility(), screenRecording(), microphone()]
    }

    /// Surveillance de la saisie. Necessaire pour creer le tap.
    static func inputMonitoring() -> PermissionCheck {
        // CGPreflightListenEventAccess ne declenche aucune invite, contrairement a
        // CGRequestListenEventAccess.
        let ok = CGPreflightListenEventAccess()
        return PermissionCheck(
            name: "Surveillance de la saisie",
            state: ok ? .granted : .denied,
            required: true,
            settingsPath: "Reglages > Confidentialite et securite > Surveillance de la saisie",
            note: ok ? nil : "Sans elle, CGEvent.tapCreate renvoie nil — sans erreur ni exception."
        )
    }

    /// Accessibilite. Requise EN PLUS de la surveillance de la saisie des lors que
    /// le tap *consomme* des evenements (specification § 4.2). La lecture pure s'en
    /// passerait ; nous, non.
    static func accessibility() -> PermissionCheck {
        // Le dictionnaire d'options est omis : passer kAXTrustedCheckOptionPrompt a true
        // ouvrirait une invite.
        let ok = AXIsProcessTrusted()
        return PermissionCheck(
            name: "Accessibilite",
            // `AXIsProcessTrusted` ne distingue pas « refusee » de « jamais accordee » :
            // il repond faux dans les deux cas. Annoncer « refusee » envoie chercher une
            // case a decocher qui n'existe peut-etre pas encore dans la liste.
            state: ok ? .granted : .undetermined,
            required: true,
            settingsPath: "Reglages > Confidentialite et securite > Accessibilite",
            note: ok ? nil : "Requise parce que le tap CONSOMME des evenements, pas seulement les lit. "
                          + "Surveillance de la saisie seule ne suffit pas."
        )
    }

    /// Enregistrement de l'ecran. Pas necessaire au geste, mais le banc C11 (T0.9)
    /// en depend, et la ré-autorisation mensuelle est le risque R1.
    static func screenRecording() -> PermissionCheck {
        let ok = CGPreflightScreenCaptureAccess()
        return PermissionCheck(
            name: "Enregistrement de l'ecran",
            state: ok ? .granted : .denied,
            required: false,
            settingsPath: "Reglages > Confidentialite et securite > Enregistrement de l'ecran",
            note: ok ? nil : "Necessaire au banc C11 seulement. Le geste fonctionne sans."
        )
    }

    /// Micro. Inutilise au lot 0 : verifie pour que l'etat soit connu avant le lot 5.
    static func microphone() -> PermissionCheck {
        let state: PermissionState = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
        return PermissionCheck(
            name: "Microphone",
            state: state,
            required: false,
            settingsPath: "Reglages > Confidentialite et securite > Microphone",
            note: "Inutilise au lot 0."
        )
    }

    /// Verifie qu'un tap peut REELLEMENT etre cree, au-dela de ce que le preflight annonce.
    ///
    /// Les deux ne coincident pas toujours : apres une re-signature, le preflight peut
    /// repondre vrai alors que `tapCreate` echoue. C'est exactement le cas que le § 4.2
    /// decrit et la premiere chose a verifier avant de soupconner le code.
    ///
    /// La sonde est creee en `.listenOnly` DELIBEREMENT : un tap consommateur arme en tete
    /// de chaine HID que personne ne draine retiendrait la souris de l'utilisateur a chaque
    /// lancement. Mais un tap en lecture seule ne demande QUE Surveillance de la saisie,
    /// alors que le vrai tap est `.defaultTap` et exige aussi l'Accessibilite : la sonde
    /// seule repondrait « possible » sur une machine ou le demarrage echoue — un doctor
    /// qui ment est pire qu'un doctor absent. D'ou le croisement avec `AXIsProcessTrusted`.
    static func canActuallyCreateTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        guard let probe = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(probe)
        return true
    }

    /// Rapport lisible, imprime au lancement et rejouable a la demande.
    ///
    /// Sans cadre ASCII : `%-28@` n'applique pas de largeur a une `NSString` de facon
    /// fiable, et une bordure droite fausse est pire qu'une absence de bordure.
    static func report() -> String {
        let checks = runAll()
        var out = ["", "Permissions", "───────────"]

        for c in checks {
            let tag = c.required ? "requis" : "option"
            let name = c.name.padding(toLength: 28, withPad: " ", startingAt: 0)
            let state = c.state.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)
            out.append("  \(c.state.symbol) \(name)\(state)\(tag)")
        }

        let tapOK = canActuallyCreateTap()
        out.append("")
        out.append("  \(tapOK ? "✓" : "✗") \("Creation effective du tap".padding(toLength: 28, withPad: " ", startingAt: 0))\(tapOK ? "possible" : "IMPOSSIBLE")")

        // Le detail ne s'affiche que pour ce qui manque : un rapport toujours verbeux
        // finit par ne plus etre lu.
        let problems = checks.filter { $0.required && $0.state != .granted }
        if !problems.isEmpty {
            out.append("")
            out.append("⚠  \(problems.count) permission(s) requise(s) manquante(s) :")
            for p in problems {
                out.append("   • \(p.name) — \(p.state.rawValue)")
                out.append("     \(p.settingsPath)")
                if let n = p.note { out.append("     \(n)") }
            }
        }

        // La discordance ne se signale que si TOUTES les permissions requises sont
        // accordees et que le tap echoue quand meme. Sinon le conseil serait faux : un
        // tap impossible faute d'Accessibilite n'a rien d'une discordance, et envoyer
        // l'utilisateur retoucher Surveillance de la saisie lui ferait perdre son temps
        // sur la mauvaise permission.
        if problems.isEmpty && !tapOK {
            out.append("")
            out.append("⚠  Toutes les permissions requises sont accordees et le tap echoue quand meme.")
            out.append("   C'est la signature du probleme decrit au § 4.2 : retirer puis remettre")
            out.append("   l'entree dans Surveillance de la saisie, et relancer.")
        }

        out.append("")
        return out.joined(separator: "\n")
    }

    static func logReport() {
        let text = report()
        // Passe par `emit` pour atterrir AUSSI dans le journal sur disque : lancee par
        // `open`, l'application n'a pas de stderr observable, et c'est precisement dans
        // ce mode qu'elle porte sa vraie identite TCC — donc le seul ou ce rapport dit
        // la verite sur ses permissions.
        StatusItemController.emit(text)
        for line in text.split(separator: "\n") where !line.isEmpty {
            log.info("\(String(line), privacy: .public)")
        }
    }
}

private extension PermissionState {
    var isGranted: Bool { self == .granted }
}
