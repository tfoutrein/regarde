import Carbon.HIToolbox
import Foundation
import Synchronization

// ─────────────────────────────────────────────────────────────────────────────
// Correspondance caractère → code de touche, selon la disposition courante
//
// Repris du lot 0, où le défaut a été trouvé à l'usage et non par la revue : ⌥⌘Z se
// déclenchait sur la touche `W` d'un clavier AZERTY, parce que le code de touche
// désigne un EMPLACEMENT et non le caractère imprimé dessus.
//
// Le lot 1 le rend plus nécessaire encore. Les quatre raccourcis sont ⌃⌥S, ⌃⌥F, ⌃⌥M,
// ⌃⌥L, et sur un clavier français trois d'entre eux tombent juste par hasard :
//
//     AZERTY   a z e r t y u i o p        QWERTY   q w e r t y u i o p
//              q s d f g h j k l m                 a s d f g h j k l ;
//              w x c v b n                         z x c v b n m
//
// `S`, `F` et `L` occupent la même position dans les deux dispositions — mais **`M`
// non** : il est en fin de rangée médiane en AZERTY, à l'emplacement du `;` QWERTY.
// Coder son code en dur ferait répondre ⌃⌥M sur la touche `,` d'un clavier français.
//
// Règle du projet, établie au lot 0 et inscrite au § 6.6bis de la spécification :
//   • lettre           → résoudre par le CARACTÈRE
//   • rangée numérique → résoudre par le CODE PHYSIQUE (sur AZERTY, `1` n'existe
//                        sans modificateur que sur le pavé numérique, code 83)
//   • sans caractère   → code physique, identique partout
// ─────────────────────────────────────────────────────────────────────────────

final class KeyboardLayout: @unchecked Sendable {
    static let shared = KeyboardLayout()

    /// Codes résolus, indexés par caractère. Publié d'un bloc pour que les lecteurs
    /// ne voient jamais une table à moitié reconstruite.
    private let table = Mutex<[Character: Int64]>([:])

    /// Codes physiques des touches sans caractère : stables sur toutes les dispositions.
    enum Physical {
        static let escape: Int64 = 53
        static let delete: Int64 = 51
    }

    private init() {}

    /// Résout les caractères demandés et s'abonne aux changements de disposition.
    func start(resolving characters: [Character]) {
        resolve(characters)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // Un développeur bilingue bascule QWERTY/AZERTY plusieurs fois par jour :
            // les raccourcis doivent suivre.
            self?.resolve(characters)
            NotificationCenter.default.post(name: .keyboardLayoutChanged, object: nil)
        }
    }

    private func resolve(_ characters: [Character]) {
        var resolved: [Character: Int64] = [:]
        for c in characters {
            if let code = Self.keyCode(for: c) { resolved[c] = code }
        }
        table.withLock { $0 = resolved }
    }

    /// Code de touche produisant `character`, ou `nil` si la disposition ne le permet pas.
    ///
    /// Le `nil` est significatif : mieux vaut un raccourci désactivé qu'un raccourci qui
    /// atterrit silencieusement sur la mauvaise touche.
    func code(for character: Character) -> Int64? {
        table.withLock { $0[character] }
    }

    /// Balaye les codes physiques et traduit chacun sans modificateur.
    ///
    /// Coûteux — quelques centaines de microsecondes — donc appelé au démarrage et au
    /// changement de disposition, jamais par événement.
    static func keyCode(for character: Character) -> Int64? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = String(character).lowercased()
        let kbdType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> Int64? in
            guard let base = buffer.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)

                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, kbdType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length).lowercased() == target {
                    return Int64(code)
                }
            }
            return nil
        }
    }

    /// Nom lisible de la disposition, pour le diagnostic.
    static var currentName: String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
        else { return "inconnue" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    /// Table résolue, pour le journal.
    func describe() -> [String] {
        let t = table.withLock { $0 }
        var lines = ["disposition  \(Self.currentName)"]
        for (c, code) in t.sorted(by: { $0.key < $1.key }) {
            let qwerty = Self.qwertyCode(for: c)
            let note = (qwerty != nil && qwerty != code) ? "  (≠ \(qwerty!) en QWERTY)" : ""
            lines.append("  « \(c) » → code \(code)\(note)")
        }
        for c in "sfml" where t[c] == nil {
            lines.append("  ⚠ « \(c) » introuvable — le raccourci correspondant est désactivé")
        }
        return lines
    }

    /// Codes QWERTY de référence, pour signaler dans le journal les touches dont la
    /// position diffère. Sert au diagnostic, jamais à la résolution.
    private static func qwertyCode(for c: Character) -> Int64? {
        switch c {
        case "a": 0;  case "s": 1;  case "d": 2;  case "f": 3
        case "h": 4;  case "g": 5;  case "z": 6;  case "x": 7
        case "c": 8;  case "v": 9;  case "b": 11; case "q": 12
        case "w": 13; case "e": 14; case "r": 15; case "y": 16
        case "t": 17; case "o": 31; case "u": 32; case "i": 34
        case "p": 35; case "l": 37; case "j": 38; case "k": 40
        case "n": 45; case "m": 46
        default: nil
        }
    }
}

extension Notification.Name {
    static let keyboardLayoutChanged = Notification.Name("dev.tfoutrein.regarde.keyboardLayoutChanged")
}
