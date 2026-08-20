import Carbon.HIToolbox
import Foundation
import Synchronization
import os

// ─────────────────────────────────────────────────────────────────────────────
// Correspondance caractere → code de touche, selon la disposition courante
//
// `kCGKeyboardEventKeycode` est un code PHYSIQUE : il designe un emplacement sur le
// clavier, pas le caractere imprime dessus. Le code 6 est la touche en bas a gauche —
// `Z` en QWERTY, `W` en AZERTY. Coder en dur « 6 » pour ⌘Z fait donc migrer le
// raccourci sur la touche `W` d'un clavier francais.
//
// L'ADR-0006 ecarte deja le double-appui sur Option a cause de l'AZERTY ; la meme
// erreur s'etait glissee ici. La regle, pour tout le projet : un raccourci qui designe
// une LETTRE se resout par le caractere, jamais par le code physique. Les touches sans
// caractere — Échap, les fleches, Tab — gardent leur code physique, qui est stable.
//
// La resolution se fait au demarrage et a chaque changement de disposition, jamais dans
// le callback du tap : celui-ci ne peut ni allouer, ni appeler AppKit, ni interroger
// Text Input Services (§ 6.2). Il ne fait que comparer deux entiers.
// ─────────────────────────────────────────────────────────────────────────────

final class KeyboardLayout: @unchecked Sendable {
    static let shared = KeyboardLayout()

    private let log = Logger(subsystem: logSubsystem, category: "layout")

    /// Code de la touche produisant « z » dans la disposition courante.
    /// −1 tant qu'elle n'a pas pu etre resolue.
    private let zKeyCode = Atomic<Int64>(-1)

    /// Codes physiques des touches sans caractere : identiques sur toutes les dispositions.
    enum Physical {
        static let escape: Int64 = 53
    }

    private init() {}

    var undoKeyCode: Int64 { zKeyCode.load(ordering: .acquiring) }

    /// Resout la correspondance et s'abonne aux changements de disposition.
    func start() {
        resolve()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // Changer de disposition en cours de session est rare mais legitime : un
            // developpeur bilingue bascule QWERTY/AZERTY plusieurs fois par jour.
            self?.resolve()
        }
    }

    private func resolve() {
        guard let code = Self.keyCode(for: "z") else {
            // Sans resolution, on ne retombe PAS sur le code physique 6 : cela
            // reintroduirait exactement le defaut, en silence. Le raccourci est
            // desactive et le journal le dit.
            zKeyCode.store(-1, ordering: .releasing)
            log.error("disposition clavier non resolue — ⌥⌘Z desactive")
            return
        }
        let previous = zKeyCode.exchange(code, ordering: .acquiringAndReleasing)
        if previous != code {
            log.notice("disposition clavier : « z » est le code \(code)")
        }
    }

    /// Cherche le code de touche produisant `character` dans la disposition courante.
    ///
    /// Balaye les codes physiques et traduit chacun sans modificateur. Couteux — quelques
    /// centaines de microsecondes — donc appele au demarrage et au changement de
    /// disposition, jamais par evenement.
    static func keyCode(for character: Character) -> Int64? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = String(character)
        let kbdType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> Int64? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)

                let status = UCKeyTranslate(
                    layout,
                    UInt16(code),
                    UInt16(kUCKeyActionDisplay),
                    0,                                   // aucun modificateur
                    kbdType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )

                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length) == target {
                    return Int64(code)
                }
            }
            return nil
        }
    }

    /// Description lisible, pour le rapport de demarrage.
    static func describe() -> String {
        let z = shared.undoKeyCode
        var lines = ["", "Clavier", "───────"]

        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            let name = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            lines.append("  disposition      \(name)")
        }

        if z < 0 {
            lines.append("  ⚠ « z » non resolu — ⌥⌘Z est desactive")
        } else {
            lines.append("  ⌥⌘Z → code \(z)\(z == 6 ? "  (identique a QWERTY)" : "  (≠ 6 : disposition non-QWERTY correctement prise en compte)")")
        }
        lines.append("  Échap → code \(Physical.escape)  (touche sans caractere, code stable)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
