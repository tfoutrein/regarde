// Harnais de mesure du lot 0 — injection d'evenements et sequences de criteres.
//
// Pourquoi automatiser ce qui etait prevu a la main : les criteres C1, C2, C5, C6, C6b
// et C6c se verifient en produisant des sequences d'evenements precises et en constatant
// ce que l'application testee a recu. Un humain les produit approximativement — « relacher
// ⌥⌘ avant le bouton » depend de sa coordination — la ou une injection les produit a la
// milliseconde, de facon reproductible, et permet de les repasser apres chaque modification.
//
// Ce que le harnais ne remplace PAS : le jugement visuel (le trait est-il sous le curseur ?
// la trotteuse saccade-t-elle ?) et tout ce qui touche au WindowServer (plein ecran,
// Stage Manager). Ces criteres restent manuels, et le protocole le dit.
//
// Fait etabli au lot 0 : les evenements postes par CGEventPost portent un timestamp VALIDE.
// Ils traversent donc la porte comme des evenements materiels — c'est ce qui rend ce harnais
// possible — mais ils n'exercent PAS le chemin de repli d'horodatage, donc pas C12.
//
// Compilation :  swiftc -O Tools/harness.swift -o .build/harness

import CoreGraphics
import Foundation

// MARK: - Injection

let src = CGEventSource(stateID: .hidSystemState)

func post(_ event: CGEvent?, flags: CGEventFlags = []) {
    guard let event else { return }
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func move(to p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                 mouseCursorPosition: p, mouseButton: .left), flags: flags)
}

func mouseDown(_ p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                 mouseCursorPosition: p, mouseButton: .left), flags: flags)
}

func mouseDrag(_ p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                 mouseCursorPosition: p, mouseButton: .left), flags: flags)
}

func mouseUp(_ p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                 mouseCursorPosition: p, mouseButton: .left), flags: flags)
}

func rightDown(_ p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .rightMouseDown,
                 mouseCursorPosition: p, mouseButton: .right), flags: flags)
}

func rightUp(_ p: CGPoint, flags: CGEventFlags = []) {
    post(CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,
                 mouseCursorPosition: p, mouseButton: .right), flags: flags)
}

/// `flagsChanged` doit etre poste explicitement : sans lui, la porte ne verrait jamais le
/// modificateur changer d'etat et le calque ne serait pas ordonne a l'ecran.
func flagsChanged(_ flags: CGEventFlags) {
    guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0x3A /* Option */, keyDown: true) else { return }
    e.type = .flagsChanged
    e.flags = flags
    e.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    post(CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true), flags: flags)
    usleep(8000)
    post(CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false), flags: flags)
}

let ARMED: CGEventFlags = [.maskAlternate, .maskCommand]
let ESCAPE: CGKeyCode = 53

func pause(_ ms: UInt32) { usleep(ms * 1000) }

// MARK: - Gestes composes

/// Trace un segment. `steps` points intermediaires, comme une souris reelle.
func stroke(from a: CGPoint, to b: CGPoint, steps: Int = 24,
            flags: CGEventFlags = ARMED, stepMs: UInt32 = 8) {
    mouseDown(a, flags: flags)
    pause(stepMs)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        mouseDrag(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags)
        pause(stepMs)
    }
    mouseUp(b, flags: flags)
}

func arm()   { flagsChanged(ARMED); pause(150) }
func disarm(){ flagsChanged([]);    pause(150) }

// MARK: - Scenarios

func scenarioTrace(origin: CGPoint, count: Int, width: Double, stepMs: UInt32) {
    arm()
    for i in 0..<count {
        let y = origin.y + Double(i % 12) * 18
        let a = CGPoint(x: origin.x, y: y)
        let b = CGPoint(x: origin.x + width, y: y + 12)
        move(to: a, flags: ARMED)
        pause(20)
        stroke(from: a, to: b, steps: 24, stepMs: stepMs)
        pause(60)
    }
    disarm()
}

/// C6 — le modificateur est relache EN PLEIN TRACE. L'application testee ne doit
/// recevoir ni les drags suivants, ni le mouseUp : elle n'a pas vu le mouseDown.
func scenarioReleaseMidStroke(origin: CGPoint) {
    arm()
    let a = origin
    move(to: a, flags: ARMED); pause(20)
    mouseDown(a, flags: ARMED); pause(20)
    for i in 1...8 {
        mouseDrag(CGPoint(x: a.x + Double(i) * 14, y: a.y + Double(i) * 4), flags: ARMED)
        pause(12)
    }
    flagsChanged([])                       // ⌥⌘ relache, bouton toujours enfonce
    pause(40)
    for i in 9...20 {
        mouseDrag(CGPoint(x: a.x + Double(i) * 14, y: a.y + Double(i) * 4), flags: [])
        pause(12)
    }
    mouseUp(CGPoint(x: a.x + 280, y: a.y + 80), flags: [])
    pause(120)
}

/// C6b — `Échap` pendant le trace, bouton toujours enfonce.
func scenarioEscapeMidStroke(origin: CGPoint) {
    arm()
    let a = origin
    move(to: a, flags: ARMED); pause(20)
    mouseDown(a, flags: ARMED); pause(20)
    for i in 1...8 {
        mouseDrag(CGPoint(x: a.x + Double(i) * 14, y: a.y + Double(i) * 4), flags: ARMED)
        pause(12)
    }
    key(ESCAPE, flags: ARMED)              // annulation, bouton toujours enfonce
    pause(40)
    for i in 9...20 {
        mouseDrag(CGPoint(x: a.x + Double(i) * 14, y: a.y + Double(i) * 4), flags: ARMED)
        pause(12)
    }
    mouseUp(CGPoint(x: a.x + 280, y: a.y + 80), flags: ARMED)
    disarm()
    pause(120)
}

/// C6c — clic droit pendant le trace, puis clic droit HORS trace.
func scenarioRightClick(origin: CGPoint) {
    arm()
    let a = origin
    move(to: a, flags: ARMED); pause(20)
    mouseDown(a, flags: ARMED); pause(20)
    for i in 1...8 {
        mouseDrag(CGPoint(x: a.x + Double(i) * 14, y: a.y + Double(i) * 4), flags: ARMED)
        pause(12)
    }
    rightDown(CGPoint(x: a.x + 112, y: a.y + 32), flags: ARMED)   // annule le trace
    pause(40)
    rightUp(CGPoint(x: a.x + 112, y: a.y + 32), flags: ARMED)
    pause(40)
    mouseUp(CGPoint(x: a.x + 112, y: a.y + 32), flags: ARMED)
    disarm()
    pause(200)
}

/// Le menu contextuel doit rester intact hors trace. Poste sans modificateur.
func scenarioRightClickIdle(origin: CGPoint) {
    move(to: origin); pause(30)
    rightDown(origin); pause(60)
    rightUp(origin); pause(200)
    key(ESCAPE)                            // referme un eventuel menu contextuel
    pause(150)
}

/// C1 — clics et glissements ordinaires, sans modificateur.
func scenarioPlainDrag(from a: CGPoint, to b: CGPoint) {
    move(to: a); pause(30)
    stroke(from: a, to: b, steps: 20, flags: [], stepMs: 10)
    pause(150)
}

// MARK: - Entree

let args = CommandLine.arguments
func value(_ name: String, _ def: Double) -> Double {
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return def }
    return Double(args[i + 1]) ?? def
}
func flag(_ name: String) -> Bool { args.contains("--\(name)") }

let x = value("x", 700)
let y = value("y", 500)
let origin = CGPoint(x: x, y: y)
let count = Int(value("count", 20))
let stepMs = UInt32(value("step-ms", 8))

guard args.count > 1 else {
    print("""
    harness — injection d'evenements pour les criteres du lot 0

      trace          --x --y --count --step-ms   traces armes ⌥⌘ (C2, C5, C7)
      plain          --x --y                     glissement ordinaire (C1)
      release        --x --y                     ⌥⌘ relache en plein trace (C6)
      escape         --x --y                     Échap en plein trace (C6b)
      rightclick     --x --y                     clic droit pendant le trace (C6c)
      rightidle      --x --y                     clic droit hors trace (C6c)
      continuous     --x --y --count             trace continu, pour C3b

    Le curseur revient a sa position initiale a la fin.
    """)
    exit(0)
}

let restore = CGEvent(source: nil)?.location ?? .zero
pause(400)   // laisser le temps de lacher la souris

switch args[1] {
case "trace":      scenarioTrace(origin: origin, count: count, width: 260, stepMs: stepMs)
case "plain":      scenarioPlainDrag(from: origin, to: CGPoint(x: x + 240, y: y))
case "release":    scenarioReleaseMidStroke(origin: origin)
case "escape":     scenarioEscapeMidStroke(origin: origin)
case "rightclick": scenarioRightClick(origin: origin)
case "rightidle":  scenarioRightClickIdle(origin: origin)
case "continuous": scenarioTrace(origin: origin, count: count, width: 320, stepMs: 6)
default:
    FileHandle.standardError.write(Data("scenario inconnu : \(args[1])\n".utf8))
    exit(2)
}

pause(200)
move(to: restore)
print("ok")
