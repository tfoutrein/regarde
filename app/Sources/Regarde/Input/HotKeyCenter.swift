import AppKit
import Carbon.HIToolbox
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// S10 — Raccourcis globaux par RegisterEventHotKey (Carbon)
//
// Pourquoi Carbon et pas `NSEvent.addGlobalMonitorForEvents` : **les raccourcis Carbon
// ne demandent aucune permission TCC**, là où un moniteur global exige la Surveillance
// de la saisie. C'est ce qui rend le diagnostic atteignable au clavier même quand
// aucune permission n'est accordée — exactement la situation où l'utilisateur en a le
// plus besoin, et celle où le lot 0 s'est retrouvé sans aucun moyen d'action.
//
// L'API est dépréciée depuis longtemps et n'a jamais été remplacée pour cet usage.
// C'est un choix assumé, pas un oubli.
//
// Les codes de touches sont résolus par CARACTÈRE (voir `KeyboardLayout`) : sur un
// clavier AZERTY, `M` n'est pas à l'emplacement du `M` QWERTY, et ⌃⌥M répondrait sur
// la touche `,`.
// ─────────────────────────────────────────────────────────────────────────────

/// Identité stable d'un raccourci, indépendante de la touche qui le déclenche.
enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case openSession = 1
    case endSession = 2
    case toggleMicrophoneLock = 3
    case toggleAnnotationLock = 4

    /// Caractère de la touche, résolu selon la disposition courante.
    var character: Character {
        switch self {
        case .openSession: "s"
        case .endSession: "f"
        case .toggleMicrophoneLock: "m"
        case .toggleAnnotationLock: "l"
        }
    }

    var label: String {
        switch self {
        case .openSession: "⌃⌥S — ouvrir une session"
        case .endSession: "⌃⌥F — terminer la session"
        case .toggleMicrophoneLock: "⌃⌥M — verrou du micro"
        case .toggleAnnotationLock: "⌃⌥L — mode annotation verrouillé"
        }
    }
}

/// Le rappel Carbon est une fonction C : il ne peut rien capturer, et transite par
/// `userData`. On passe le centre lui-même.
private func hotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    // Le gestionnaire est installé sur `GetApplicationEventTarget()`, donc distribué par
    // la boucle d'événements principale : ce rappel arrive sur le thread principal.
    // On l'affirme plutôt que de repasser par un `async`, qui décalerait le raccourci
    // d'un tour de boucle sans rien garantir de plus.
    MainActor.assumeIsolated { center.fire(id: hotKeyID.id) }
    return noErr
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private(set) var failures: [HotKeyAction: String] = [:]

    /// Appelé sur le thread principal quand un raccourci se déclenche.
    var onAction: ((HotKeyAction) -> Void)?

    /// Modificateurs communs aux quatre raccourcis : ⌃⌥.
    ///
    /// Choisis pour ne heurter aucun raccourci système courant, et distincts du ⌥⌘ qui
    /// arme le tracé (ADR-0006) : un raccourci de session ne doit pas pouvoir se
    /// déclencher pendant qu'on trace.
    private static let modifiers = UInt32(controlKey | optionKey)

    func install() {
        installHandlerIfNeeded()
        registerAll()

        // Une bascule de disposition doit ré-enregistrer : sinon ⌃⌥M continuerait de
        // répondre sur l'ancienne touche.
        NotificationCenter.default.addObserver(
            forName: .keyboardLayoutChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                HotKeyCenter.shared.unregisterAll()
                HotKeyCenter.shared.registerAll()
                Journal.section("Raccourcis — disposition changée", HotKeyCenter.shared.describe())
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    private func registerAll() {
        failures = [:]
        for action in HotKeyAction.allCases {
            guard let code = KeyboardLayout.shared.code(for: action.character) else {
                // Pas de repli sur un code par défaut : un raccourci qui atterrit en
                // silence sur la mauvaise touche coûte plus cher qu'un raccourci absent.
                failures[action] = "touche « \(action.character) » introuvable dans la disposition"
                continue
            }

            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x52474445 /* 'RGDE' */), id: action.rawValue)
            let status = RegisterEventHotKey(
                UInt32(code), Self.modifiers, id, GetApplicationEventTarget(), 0, &ref
            )

            if status == noErr, let ref {
                registered[action.rawValue] = ref
            } else {
                // `eventHotKeyExistsErr` (−9878) : une autre application détient déjà ce
                // raccourci. C'est un conflit réel, pas un bug, et l'utilisateur doit
                // pouvoir le lire dans le diagnostic.
                failures[action] = status == -9878
                    ? "déjà pris par une autre application"
                    : "échec de l'enregistrement (OSStatus \(status))"
            }
        }
    }

    private func unregisterAll() {
        for (_, ref) in registered { UnregisterEventHotKey(ref) }
        registered = [:]
    }

    fileprivate func fire(id: UInt32) {
        guard let action = HotKeyAction(rawValue: id) else { return }
        Journal.event(.key, action.label)
        onAction?(action)
    }

    // MARK: - Diagnostic

    var allRegistered: Bool { failures.isEmpty && registered.count == HotKeyAction.allCases.count }

    func describe() -> [String] {
        var lines: [String] = []
        for action in HotKeyAction.allCases {
            if let reason = failures[action] {
                lines.append("✗ \(action.label) — \(reason)")
            } else if let code = KeyboardLayout.shared.code(for: action.character) {
                lines.append("✓ \(action.label)  (code \(code))")
            }
        }
        return lines
    }
}
