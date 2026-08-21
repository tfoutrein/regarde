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
// MARK: - Scenario du lot 2 : les quatre outils et la palette d'intentions

/// Codes PHYSIQUES. Les lettres sont resolues sur la disposition COURANTE cote
/// application ; ici on injecte des emplacements, donc on donne les codes AZERTY de
/// l'auteur — c'est exactement l'asymetrie que l'ADR-0021 decrit.
let TOOL_KEYS: [String: CGKeyCode] = [
    "fleche": 3,     // F
    "cadre": 8,      // C
    "point": 35,     // P
    "surlignage": 1, // S
]
let DIGIT_KEYS: [CGKeyCode] = [18, 19, 20, 21, 23, 22]   // 1 2 3 4 5 6 — 5 et 6 inverses

func selectTool(_ name: String) {
    guard let code = TOOL_KEYS[name] else { return }
    key(code, flags: ARMED)
    pause(120)
}

func applyIntention(_ rank: Int) {
    guard rank >= 1, rank <= 6 else { return }
    key(DIGIT_KEYS[rank - 1], flags: ARMED)
    pause(120)
}

/// Une marque par outil, chacune qualifiee par une intention differente.
///
/// Le scenario tient l'armement pendant TOUTE la sequence : relacher ⌥⌘ entre deux
/// marques desarmerait la porte, et le changement d'outil ne passerait plus — il est
/// conditionne a `isArmed` pour ne pas voler ⌥⌘C a l'application testee.
func scenarioLot2(origin: CGPoint) {
    arm()

    selectTool("fleche")
    stroke(from: origin, to: CGPoint(x: origin.x + 220, y: origin.y + 90))
    applyIntention(2)                                    // erreur
    pause(200)

    selectTool("cadre")
    stroke(from: CGPoint(x: origin.x, y: origin.y + 160),
           to: CGPoint(x: origin.x + 260, y: origin.y + 300))
    applyIntention(1)                                    // mal aligne
    pause(200)

    selectTool("point")
    stroke(from: CGPoint(x: origin.x + 360, y: origin.y + 60),
           to: CGPoint(x: origin.x + 360, y: origin.y + 60), steps: 2)
    applyIntention(4)                                    // lent
    pause(200)

    selectTool("surlignage")
    stroke(from: CGPoint(x: origin.x + 330, y: origin.y + 200),
           to: CGPoint(x: origin.x + 620, y: origin.y + 250))
    applyIntention(5)                                    // texte a corriger
    pause(200)

    // Un chiffre hors palette : il doit etre avale, et le HUD doit le dire.
    key(26, flags: ARMED)                                // 7
    pause(200)

    // L'armement est TENU le temps demande. Le calque est retire des le desarmement
    // (ADR-0010) : capturer apres coup ne montrerait qu'un ecran nu, ce qui est le
    // comportement voulu mais ne prouve rien sur le rendu.
    pause(UInt32(value("hold", 0)))

    disarm()
}

/// Confinement a la fenetre cible (S22).
///
/// Deux traces au MEME endroit, hors de la cible. Le premier ne doit rien poser — c'est
/// le ⌥⌘-clic dans l'IDE pendant une session. Le second, avec ⇧, doit poser une marque :
/// c'est l'echappatoire, pour les defauts qui ne sont pas dans la fenetre.
func scenarioOutside(origin: CGPoint) {
    arm()
    stroke(from: origin, to: CGPoint(x: origin.x + 180, y: origin.y + 60))
    pause(400)
    disarm()
    pause(300)

    let escaped: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift]
    flagsChanged(escaped); pause(150)
    stroke(from: CGPoint(x: origin.x, y: origin.y + 100),
           to: CGPoint(x: origin.x + 180, y: origin.y + 160), flags: escaped)
    pause(400)
    disarm()
}

/// Trois marques a un endroit donne, avec trois outils et trois intentions.
///
/// Sert au passage du livrable du lot 2 : trois sur l'ecran principal, trois sur
/// l'ecran externe, en une seule session.
func scenarioTriplet(origin: CGPoint, tools: [String], intentions: [Int]) {
    arm()
    for (i, name) in tools.enumerated() {
        selectTool(name)
        let y = origin.y + Double(i) * 130
        if name == "point" {
            stroke(from: CGPoint(x: origin.x + 80, y: y),
                   to: CGPoint(x: origin.x + 80, y: y), steps: 2)
        } else {
            stroke(from: CGPoint(x: origin.x, y: y),
                   to: CGPoint(x: origin.x + 200, y: y + 70))
        }
        if i < intentions.count { applyIntention(intentions[i]) }
        pause(250)
    }
    pause(UInt32(value("hold", 0)))
    disarm()
}

/// Trace, annule par ⌥⌘Z, retrace AILLEURS, publie.
///
/// Vérifie que l'image publiée est celle de la SECONDE marque : les deux portent le
/// numéro 1 depuis que l'annulation le rend, et seule leur identité les distingue.
func scenarioUndo(origin: CGPoint) {
    arm()
    selectTool("cadre")

    // Premier cadre, en haut.
    stroke(from: origin, to: CGPoint(x: origin.x + 260, y: origin.y + 120))
    pause(500)

    // Annulation : code 13, la touche marquée Z sur un clavier français.
    key(13, flags: ARMED)
    pause(400)

    // Second cadre, nettement plus bas : les deux images doivent être distinctes.
    stroke(from: CGPoint(x: origin.x, y: origin.y + 320),
           to: CGPoint(x: origin.x + 260, y: origin.y + 440))
    pause(400)

    disarm()
}

/// Trace sur la fenetre au premier plan, bascule sur ce qu'il y a dessous, retrace.
///
/// Reproduit ce que l'auteur a fait en changeant d'ecran : hors session la cible suit
/// l'application au premier plan, donc l'observation peut melanger deux applications.
func scenarioDrift(origin: CGPoint, elsewhere: CGPoint) {
    arm()
    stroke(from: origin, to: CGPoint(x: origin.x + 200, y: origin.y + 90))
    pause(400)

    // Un clic hors de la fenetre cible : il ne trace pas, il ACTIVE ce qu'il y a dessous.
    mouseDown(elsewhere, flags: ARMED)
    pause(60)
    mouseUp(elsewhere, flags: ARMED)
    pause(1200)   // laisser le suivi rattraper la nouvelle cible

    stroke(from: elsewhere, to: CGPoint(x: elsewhere.x + 200, y: elsewhere.y + 90))
    pause(400)
    disarm()
}

/// Trace, publie, attend, re-arme SANS tracer, et laisse l'armement tenu.
///
/// Sert a verifier ce que le calque affiche au moment du re-armement : les marques
/// publiees ne doivent PAS reapparaitre. Le controle se fait par capture d'ecran pendant
/// la pause finale.
func scenarioGhost(origin: CGPoint) {
    arm()
    stroke(from: origin, to: CGPoint(x: origin.x + 220, y: origin.y + 100))
    pause(300)
    disarm()

    // Laisser la publication eclair partir et vider le modele.
    pause(3000)

    // Re-armer, sans rien tracer, et tenir.
    arm()
    move(to: CGPoint(x: origin.x + 40, y: origin.y + 40), flags: ARMED)
    pause(UInt32(value("hold", 5000)))
    disarm()
}

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
      lot2           --x --y                     4 outils + intentions (S20 a S23)
      outside        --x --y                     hors cible, puis ⌥⌘⇧ (S22)
      triplet        --x --y --tools --marks     3 marques, 3 outils (S28)
      undo           --x --y                     trace, ⌥⌘Z, retrace, publie
      drift          --x --y --ex --ey           trace, change d'application, retrace
      ghost          --x --y --hold              trace, publie, re-arme sans tracer

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
case "lot2":       scenarioLot2(origin: origin)
case "outside":    scenarioOutside(origin: origin)
case "undo":       scenarioUndo(origin: origin)
case "ghost":      scenarioGhost(origin: origin)
case "drift":      scenarioDrift(origin: origin,
                                 elsewhere: CGPoint(x: value("ex", 1400), y: value("ey", 900)))
case "triplet":
    let names = args.firstIndex(of: "--tools").map { args[$0 + 1] } ?? "fleche,cadre,point"
    let ranks = args.firstIndex(of: "--marks").map { args[$0 + 1] } ?? "2,1,4"
    scenarioTriplet(origin: origin,
                    tools: names.split(separator: ",").map(String.init),
                    intentions: ranks.split(separator: ",").compactMap { Int($0) })
case "hotkey":
    // ⌃⌥ + une touche, pour declencher les raccourcis Carbon de l'application.
    key(CGKeyCode(value("key", 1)), flags: [.maskControl, .maskAlternate])
default:
    FileHandle.standardError.write(Data("scenario inconnu : \(args[1])\n".utf8))
    exit(2)
}

pause(200)
move(to: restore)
print("ok")
