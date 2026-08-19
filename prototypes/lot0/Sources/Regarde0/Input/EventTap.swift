import CoreGraphics
import Foundation
import Synchronization
import os

// ─────────────────────────────────────────────────────────────────────────────
// T0.4 — Le tap sur son propre thread, avec sa propre run loop
// T0.8 — Re-armement et watchdog
//
// Pourquoi un thread dedie plutot que la run loop principale : le callback doit
// repondre en quelques dizaines de microsecondes. Sur le thread principal, il
// attendrait derriere le layout AppKit, le rendu SwiftUI et tout ce que la boucle
// principale traite. Un depassement declenche kCGEventTapDisabledByTimeout et la
// bascule cesse — en silence. C'est le risque R9.
//
// Budget du callback (§ 6.2) : zero allocation, zero appel AppKit, zero I/O, zero
// verrou bloquant. Tout ce qui suit respecte cette regle, y compris les compteurs.
// ─────────────────────────────────────────────────────────────────────────────

/// Callback C. Ne capture rien : le contexte transite par `userInfo`.
private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

final class EventTap: @unchecked Sendable {
    static let shared = EventTap()

    private let log = Logger(subsystem: logSubsystem, category: "tap")

    // ── Ressources du tap. Touchees uniquement sur le thread du tap. ──────────
    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    // ── Observabilite. Le compteur d'evenements est le TEMOIN PERMANENT du § 4.2 :
    //    il reste en place pour toute la duree du lot 0 et s'interroge avant de
    //    soupconner quoi que ce soit d'autre. ──────────────────────────────────
    private let seenCount = Atomic<UInt64>(0)
    private let lastEventTicks = Atomic<UInt64>(0)
    private let reArmCount = Atomic<UInt64>(0)
    private let installed = Atomic<Bool>(false)
    /// Pire duree observee dans le callback, en unites mach. Sert a verifier qu'on
    /// reste trois ordres de grandeur sous le seuil de timeout du systeme.
    private let worstCallbackTicks = Atomic<UInt64>(0)

    /// Appelee sur le thread du tap a chaque `keyDown` pertinent. Le lot 0 s'en sert
    /// pour Échap et ⌘Z (§ 6.3).
    var onControlKey: (@Sendable (ControlKey) -> Void)?

    enum ControlKey: Sendable {
        case escape
        case undo
    }

    private enum KeyCode {
        static let escape: Int64 = 53
        static let z: Int64 = 6
    }

    // MARK: - Cycle de vie

    /// Demarre le thread du tap. Retourne `false` si le tap n'a pas pu etre cree —
    /// dans ce cas, la cause est presque toujours une permission, jamais le code.
    @discardableResult
    func start() -> Bool {
        guard thread == nil else { return installed.load(ordering: .acquiring) }

        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            let ok = self.install()
            ready.signal()
            guard ok else { return }
            // La run loop tourne jusqu'a l'arret du processus. Sans source valide,
            // CFRunLoopRun retourne immediatement — d'ou le garde ci-dessus.
            CFRunLoopRun()
        }
        t.name = "dev.tfoutrein.regarde.lot0.tap"
        // Priorite elevee sans etre temps reel : le callback doit passer devant le
        // rendu, pas devant le pilote d'entree.
        t.qualityOfService = .userInteractive
        t.stackSize = 512 * 1024
        thread = t
        t.start()

        _ = ready.wait(timeout: .now() + 2.0)
        return installed.load(ordering: .acquiring)
    }

    /// Cree le port, la source, et arme le tap. Thread du tap uniquement.
    private func install() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,              // au niveau HID : avant toute application
            place: .headInsertEventTap,       // en tete de chaine
            options: .defaultTap,             // peut CONSOMMER — d'ou l'exigence d'Accessibilite
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("CGEvent.tapCreate a renvoye nil — permission manquante, pas un bug de code")
            installed.store(false, ordering: .releasing)
            return false
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        source = src
        installed.store(true, ordering: .releasing)
        lastEventTicks.store(SessionClock.hostTicksNow(), ordering: .relaxed)
        log.notice("tap installe")
        return true
    }

    private func uninstall() {
        if let src = source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        machPort = nil
        installed.store(false, ordering: .releasing)
    }

    // MARK: - Le callback

    /// Chemin critique. Toute ligne ajoutee ici se paie sur chaque evenement souris.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let t0 = SessionClock.hostTicksNow()
        defer {
            let dt = SessionClock.hostTicksNow() &- t0
            if dt > worstCallbackTicks.load(ordering: .relaxed) {
                worstCallbackTicks.store(dt, ordering: .relaxed)
            }
        }

        // Le systeme desarme le tap sans prevenir : sur depassement de budget
        // (timeout) ou sur saisie utilisateur privilegiee. Le re-armer ici est le
        // seul endroit ou l'on apprend que c'est arrive.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = machPort { CGEvent.tapEnable(tap: port, enable: true) }
            reArmCount.wrappingAdd(1, ordering: .relaxed)
            // Un tracé en cours au moment du desarmement n'a plus de mouseUp garanti :
            // remettre le verrou a plat evite de rester bloque en capture.
            OptionGate.shared.requestReset()
            return nil
        }

        seenCount.wrappingAdd(1, ordering: .relaxed)
        lastEventTicks.store(t0, ordering: .relaxed)

        let flags = event.flags
        let location = event.location

        switch type {
        case .flagsChanged:
            // Ne JAMAIS consommer : l'application testee doit garder une vision exacte
            // de l'etat du clavier, sans quoi elle se croit avec ⌥ enfonce indefiniment.
            OptionGate.shared.noteFlagsChanged(flags, location: location)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            return handleKeyDown(event: event, flags: flags)

        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved:
            switch OptionGate.shared.decide(type: type, flags: flags, location: location) {
            case .pass:
                return Unmanaged.passUnretained(event)
            case .swallow:
                return nil
            case .capture(let kind):
                InkRing.shared.push(InkEvent(
                    x: location.x,
                    y: location.y,
                    kind: kind.rawValue,
                    hostTicks: event.timestamp,
                    enqueuedTicks: t0
                ))
                return nil
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Échap et ⌘Z (§ 6.3). Consommes uniquement quand ils s'appliquent a nous ;
    /// sinon ils partent a l'application testee, qui en a besoin.
    @inline(__always)
    private func handleKeyDown(event: CGEvent, flags: CGEventFlags) -> Unmanaged<CGEvent>? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if code == KeyCode.escape, OptionGate.shared.isStroking {
            OptionGate.shared.cancelStroke()
            onControlKey?(.escape)
            return nil
        }

        if code == KeyCode.z, flags.contains(.maskCommand), !flags.contains(.maskShift),
           OptionGate.shared.isArmed {
            // Conditionne a `isArmed` : sans le modificateur d'armement tenu, ⌘Z
            // appartient a l'application testee et le lui voler serait inacceptable.
            onControlKey?(.undo)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Watchdog (T0.8)

    private var watchdog: Timer?

    /// Verifie toutes les 5 s que le tap est arme **et** qu'il voit passer des evenements.
    ///
    /// Verifier `tapIsEnabled` seul ne suffit pas : apres une re-signature, le port peut
    /// se declarer actif tout en ne recevant plus rien. Le seul temoin fiable est le trafic.
    func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkHealth() {
        guard let port = machPort else {
            log.error("watchdog : aucun port — tentative de reinstallation")
            reinstallOnTapThread()
            return
        }

        let enabled = CGEvent.tapIsEnabled(tap: port)
        let idleMs = SessionClock.millis(from: lastEventTicks.load(ordering: .relaxed),
                                         to: SessionClock.hostTicksNow())

        if !enabled {
            log.error("watchdog : tap desarme — re-armement")
            CGEvent.tapEnable(tap: port, enable: true)
            reArmCount.wrappingAdd(1, ordering: .relaxed)
            return
        }

        // Trente secondes sans le moindre evenement, souris comprise, alors que le
        // port se declare actif : c'est la panne silencieuse. On reconstruit tout.
        if idleMs > 30_000 {
            log.error("watchdog : actif mais muet depuis \(Int(idleMs / 1000)) s — reinstallation complete")
            reinstallOnTapThread()
        }
    }

    /// Reconstruit le tap depuis son propre thread : toucher `machPort` depuis le
    /// thread principal serait une course avec le callback.
    private func reinstallOnTapThread() {
        guard let rl = tapRunLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            self.uninstall()
            if self.install() {
                self.log.notice("tap reinstalle par le watchdog")
            } else {
                self.log.error("reinstallation impossible — verifier Surveillance de la saisie")
            }
        }
        CFRunLoopWakeUp(rl)
    }

    // MARK: - Diagnostic

    var isInstalled: Bool { installed.load(ordering: .acquiring) }
    var isEnabled: Bool { machPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var eventsSeen: UInt64 { seenCount.load(ordering: .relaxed) }
    var reArms: UInt64 { reArmCount.load(ordering: .relaxed) }
    var idleSeconds: Double {
        SessionClock.millis(from: lastEventTicks.load(ordering: .relaxed),
                            to: SessionClock.hostTicksNow()) / 1000.0
    }
    var worstCallbackMs: Double {
        Double(worstCallbackTicks.load(ordering: .relaxed)) * SessionClock.tickToNanosPublic / 1_000_000.0
    }

    /// Le temoin permanent du § 4.2, en une ligne.
    func healthLine() -> String {
        String(format: "tap %@ · %llu evts · inactif %.1fs · re-armements %llu · pire callback %.3f ms · perdus %llu",
               isEnabled ? "actif" : "INACTIF",
               eventsSeen, idleSeconds, reArms, worstCallbackMs, InkRing.shared.droppedCount)
    }
}

extension SessionClock {
    /// Exposé pour la conversion de duree hors de la classe, sans dupliquer mach_timebase.
    static var tickToNanosPublic: Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }
}
