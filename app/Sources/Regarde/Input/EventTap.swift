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

    // ── Ressources du tap. Touchees uniquement sur le thread du tap, sans exception.
    //
    // `machPort` est un `var CFMachPort?` : le lire depuis un autre thread emet un
    // retain pendant que le thread du tap emet le release en le remplacant — course sur
    // le compteur de references, avec un retain qui peut porter sur un objet deja libere.
    // C'est pourquoi ni le watchdog ni la barre de menus ne les touchent : ils passent
    // par `armedFlag`, et le watchdog s'execute sur la run loop du tap. ───────────────
    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?
    /// Source factice qui garde la run loop vivante meme sans tap installe.
    ///
    /// `CFRunLoopRun()` retourne des que la run loop n'a plus aucune source. Sans cette
    /// source, une reinstallation ratee ferait sortir le thread definitivement : plus
    /// aucun bloc poste ne s'executerait, et `start()` ne pourrait pas relancer puisque
    /// `thread` n'est plus nil. Redonner la permission ne suffirait pas, il faudrait
    /// relancer l'application — precisement le quotidien du lot 0.
    private var keepAlive: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    // ── Observabilite. Le compteur d'evenements est le TEMOIN PERMANENT du § 4.2 :
    //    il reste en place pour toute la duree du lot 0 et s'interroge avant de
    //    soupconner quoi que ce soit d'autre. ──────────────────────────────────
    private let seenCount = Atomic<UInt64>(0)
    private let lastEventTicks = Atomic<UInt64>(0)
    private let reArmCount = Atomic<UInt64>(0)
    /// Reconstructions completes du tap. Distinct des re-armements : C10 se mesurerait
    /// sinon sur un tap qui a pu etre detruit et recree sans que rien ne le dise.
    private let rebuildCount = Atomic<UInt64>(0)
    private let installed = Atomic<Bool>(false)
    /// Etat d'armement, ecrit uniquement sur le thread du tap. C'est ce que lisent la
    /// barre de menus et le rapport, a la place de `CGEvent.tapIsEnabled(tap: machPort)`.
    private let armedFlag = Atomic<Bool>(false)
    /// Pire duree observee dans le callback, en unites mach. Sert a verifier qu'on
    /// reste trois ordres de grandeur sous le seuil de timeout du systeme.
    private let worstCallbackTicks = Atomic<UInt64>(0)

    /// Appelee sur le thread du tap a chaque `keyDown` pertinent. Le lot 0 s'en sert
    /// pour Échap et ⌘Z (§ 6.3).
    var onControlKey: (@Sendable (ControlKey) -> Void)?

    enum ControlKey: Sendable {
        case escape
        case undo
        case selectTool(MarkTool)
        case intention(Intention)
        case mutedDigit(Int)
    }

    // Les codes de touches ne sont plus ecrits en dur : voir `KeyboardLayout`.
    // `kCGKeyboardEventKeycode` designe un EMPLACEMENT physique, pas un caractere —
    // le code 6 porte `Z` en QWERTY et `W` en AZERTY.

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

            // La source factice est ajoutee AVANT toute tentative d'installation : la
            // run loop ne doit jamais etre vide, sinon le thread sort et ne revient pas.
            var ctx = CFRunLoopSourceContext()
            let alive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), alive, .commonModes)
            self.keepAlive = alive

            _ = self.install()
            ready.signal()
            // Tourne jusqu'a l'arret du processus, meme si l'installation a echoue :
            // le watchdog pourra reessayer quand la permission sera accordee.
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

    /// Masque des evenements ecoutes.
    ///
    /// Le bouton droit y figure pour une seule raison : annuler le tracé en cours, geste
    /// plus direct qu'`Échap` quand la main est deja sur la souris. Il n'est consomme
    /// QUE pendant un tracé actif, et son relachement l'est aussi — un `rightMouseUp`
    /// sans `rightMouseDown` serait le meme defaut que C6 interdit pour le bouton gauche.
    /// Hors tracé, le menu contextuel de l'application testee est intact.
    ///
    /// La molette et les boutons auxiliaires restent dehors : ils n'ont aucun role, et
    /// tout ajout ici se paie sur chaque evenement du systeme.
    /// Construit par reduction plutot qu'en chainant des `|` : au-dela de quelques
    /// termes, l'inference de types de Swift renonce sur cette expression.
    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .mouseMoved, .flagsChanged, .keyDown,
        ]
        return types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }()

    /// Cree un port arme, sans toucher a l'etat de l'objet. Thread du tap uniquement.
    private func makePort() -> (CFMachPort, CFRunLoopSource)? {
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,              // au niveau HID : avant toute application
            place: .headInsertEventTap,       // en tete de chaine
            options: .defaultTap,             // peut CONSOMMER — d'ou l'exigence d'Accessibilite
            eventsOfInterest: Self.eventMask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return nil }

        guard let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            // Sans source, le port ne recevrait jamais rien : l'invalider plutot que
            // de laisser un tap arme que personne ne draine — la souris de l'utilisateur
            // pourrait y etre retenue.
            CFMachPortInvalidate(port)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return (port, src)
    }

    /// Cree le port, la source, et arme le tap. Thread du tap uniquement.
    private func install() -> Bool {
        guard let (port, src) = makePort() else {
            log.error("CGEvent.tapCreate a renvoye nil — permission manquante, pas un bug de code")
            installed.store(false, ordering: .releasing)
            armedFlag.store(false, ordering: .releasing)
            return false
        }

        machPort = port
        source = src
        installed.store(true, ordering: .releasing)
        armedFlag.store(true, ordering: .releasing)
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
        armedFlag.store(false, ordering: .releasing)
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
            armedFlag.store(true, ordering: .releasing)
            reArmCount.wrappingAdd(1, ordering: .relaxed)
            // Le verrou n'est PAS remis a plat : il doit tenir jusqu'au `mouseUp`, sinon
            // le milieu d'un clic dont l'application n'a pas vu le debut lui serait rendu
            // — c'est C6. Rester « bloque en capture » ne dure de toute facon que jusqu'au
            // prochain `leftMouseDown`, seul point de decision d'entree (§ 6.2).
            //
            // Le depassement de budget est le scenario NOMINAL de T0.8, provoque expres :
            // ce chemin est emprunte a chaque passage du test.
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

        case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            switch OptionGate.shared.decide(type: type, flags: flags, location: location) {
            case .pass:
                // Le banc C11 observe ici, et seulement ici : le PONT D'HORLOGE se
                // construit sur des clics NUS, ceux que la porte laisse passer.
                //
                // Deux écritures atomiques derrière un drapeau, et rien d'autre :
                // aucune allocation, aucun verrou, aucun appel AppKit, et surtout
                // le chemin de retour est inchangé — l'événement repart exactement
                // comme avant. C1, C2 et C5 ne sont pas concernés, et le budget de
                // latence du § C7 non plus.
                if type == .leftMouseDown { C11Tap.shared.noterClicNu(event.timestamp) }
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

        // Échap n'a pas de caractere : son code physique est stable sur toutes les
        // dispositions et peut rester en dur.
        if code == KeyboardLayout.Physical.escape, OptionGate.shared.isStroking {
            OptionGate.shared.cancelStroke()
            onControlKey?(.escape)
            return nil
        }

        // Le code de « z » est resolu selon la disposition courante, hors du callback :
        // ici on ne fait que comparer deux entiers. Vaut −1 si la resolution a echoue,
        // auquel cas aucun code reel ne peut correspondre et le raccourci est inerte —
        // preferable a un raccourci qui atterrit sur la mauvaise touche.
        let undo = KeyboardLayout.shared.code(for: "z")
        if let undo, code == undo, !flags.contains(.maskShift),
           OptionGate.shared.acceptsControlKeys(flags: flags) {
            // ⌥⌘Z, jamais ⌘Z nu. Sans le modificateur d'armement dans les flags de la
            // frappe, l'annulation appartient a l'application testee — et la lui voler
            // serait la pire regression possible pour un outil qui promet de ne rien
            // casser.
            onControlKey?(.undo)
            return nil
        }

        // Changement d'outil, pendant que ⌥⌘ est tenu et que la cible est l'application
        // active. Hors de cet état, ⌥⌘F ou ⌥⌘C appartiennent à l'application testée et
        // les lui voler serait inacceptable.
        if OptionGate.shared.acceptsControlKeys(flags: flags),
           let tool = ToolKeyCache.shared.tool(forCode: code) {
            onControlKey?(.selectTool(tool))
            return nil
        }

        // Palette d'intentions, ⌥⌘ + 1..6 — codes PHYSIQUES (ADR-0021). Resoudre le
        // caractere « 1 » renverrait le pave numerique sur un clavier AZERTY, absent de
        // tout MacBook.
        //
        // Comme le changement d'outil, la regle suit l'application ACTIVE et non le
        // curseur : une fleche tracee vers le bord laisse le pointeur dehors, et exiger
        // qu'il soit dedans perdait l'intention frappee juste apres.
        if OptionGate.shared.acceptsControlKeys(flags: flags) {
            if let intention = Intention.forKeyCode(code) {
                onControlKey?(.intention(intention))
                return nil
            }
            // 7 a 9 sont AVALES sans effet, et non laisses passer : envoyer ⌥⌘7 a
            // l'application testee en plein trace serait pire que de ne rien faire. Le
            // HUD dit pourquoi, sans quoi l'absence d'effet passerait pour une panne.
            if let rank = MuteDigit.rank(of: code) {
                onControlKey?(.mutedDigit(rank))
                return nil
            }
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

    /// Inactivite reelle de la session, tous peripheriques confondus.
    ///
    /// Sans ce croisement, le watchdog confond « l'utilisateur ne bouge pas » et « le tap
    /// est mort » : le masque ne contient que des entrees utilisateur, il n'existe aucune
    /// source periodique. Lire son ecran trente secondes — ou executer le protocole C10,
    /// qui demande justement de laisser tourner — declencherait une reconstruction, et
    /// chaque reconstruction ouvre une fenetre de quelques millisecondes sans tap pendant
    /// laquelle un ⌥⌘-glisser passe integralement a l'application testee. Le mecanisme
    /// cense proteger de la panne la provoquerait, et ferait echouer C2 au passage.
    private func systemIdleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged,
                                    .keyDown, .flagsChanged, .scrollWheel]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? .infinity
    }

    /// Nombre de detections consecutives de silence anormal. Thread du tap uniquement.
    private var silentStreak = 0

    /// Toute la verification s'execute sur la run loop du tap : `machPort` et `source`
    /// lui appartiennent, et les lire depuis le thread principal etait une course sur
    /// leur compteur de references.
    private func checkHealth() {
        guard let rl = tapRunLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.checkHealthOnTapThread()
        }
        CFRunLoopWakeUp(rl)
    }

    private func checkHealthOnTapThread() {
        guard let port = machPort else {
            log.error("watchdog : aucun port — tentative de reinstallation")
            reinstallHere()
            return
        }

        let enabled = CGEvent.tapIsEnabled(tap: port)
        armedFlag.store(enabled, ordering: .releasing)

        if !enabled {
            log.error("watchdog : tap desarme — re-armement")
            CGEvent.tapEnable(tap: port, enable: true)
            armedFlag.store(true, ordering: .releasing)
            reArmCount.wrappingAdd(1, ordering: .relaxed)
            silentStreak = 0
            return
        }

        let idleMs = SessionClock.millis(from: lastEventTicks.load(ordering: .relaxed),
                                         to: SessionClock.hostTicksNow())

        // Le silence du tap n'est un symptome que si le systeme, lui, voit du trafic.
        guard idleMs > 30_000, systemIdleSeconds() < 5.0 else {
            silentStreak = 0
            return
        }

        silentStreak += 1
        if silentStreak == 1 {
            // Geste non destructif d'abord : la reconstruction est le dernier recours.
            log.error("watchdog : muet alors que le systeme voit du trafic — re-armement simple")
            CGEvent.tapEnable(tap: port, enable: true)
            reArmCount.wrappingAdd(1, ordering: .relaxed)
            return
        }

        silentStreak = 0
        log.error("watchdog : toujours muet a la seconde detection — reinstallation complete")
        reinstallHere()
    }

    /// Reconstruit le tap. Thread du tap uniquement.
    ///
    /// L'ordre compte : on cree le NOUVEAU port avant de retirer l'ancien. Detruire
    /// d'abord viderait la run loop si la creation echoue — permission revoquee en cours
    /// de session, autorisation perdue apres une re-signature — et `CFRunLoopRun()`
    /// retournerait, tuant le thread definitivement. La source factice couvre deja ce
    /// cas, mais un tap conserve vaut mieux qu'un tap absent : sur echec, on garde
    /// l'existant plutot que de se retrouver sans rien.
    private func reinstallHere() {
        guard let (newPort, newSrc) = makePort() else {
            log.error("reinstallation impossible — l'ancien tap est conserve, verifier Surveillance de la saisie")
            return
        }
        uninstall()                                   // apres l'ajout de la nouvelle source
        machPort = newPort
        source = newSrc
        installed.store(true, ordering: .releasing)
        armedFlag.store(true, ordering: .releasing)
        lastEventTicks.store(SessionClock.hostTicksNow(), ordering: .relaxed)
        rebuildCount.wrappingAdd(1, ordering: .relaxed)
        log.notice("tap reinstalle par le watchdog")
    }

    // MARK: - Diagnostic

    var isInstalled: Bool { installed.load(ordering: .acquiring) }
    /// Lu depuis le drapeau atomique, jamais depuis `machPort` : ce dernier appartient
    /// au thread du tap et le lire ailleurs etait une course sur son compteur de references.
    var isEnabled: Bool { armedFlag.load(ordering: .acquiring) }
    var eventsSeen: UInt64 { seenCount.load(ordering: .relaxed) }
    var reArms: UInt64 { reArmCount.load(ordering: .relaxed) }
    var rebuilds: UInt64 { rebuildCount.load(ordering: .relaxed) }
    var idleSeconds: Double {
        SessionClock.millis(from: lastEventTicks.load(ordering: .relaxed),
                            to: SessionClock.hostTicksNow()) / 1000.0
    }
    var worstCallbackMs: Double {
        Double(worstCallbackTicks.load(ordering: .relaxed)) * SessionClock.tickToNanosPublic / 1_000_000.0
    }

    /// Le temoin permanent du § 4.2, en une ligne.
    func healthLine() -> String {
        String(format: "tap %@ · %llu evts · inactif %.1fs · re-arm %llu · reconstr %llu · pire callback %.3f ms · perdus %llu",
               isEnabled ? "actif" : "INACTIF",
               eventsSeen, idleSeconds, reArms, rebuilds, worstCallbackMs, InkRing.shared.droppedCount)
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
