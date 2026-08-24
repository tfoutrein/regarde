import AppKit
import ImageIO
import ApplicationServices
import CoreGraphics
import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// Point d'entrée de Regarde.
//
// Ordre de démarrage, et il compte — le lot 0 a montré ce que coûte l'inverse :
//   1. la barre de menus, pour qu'un état soit visible même si la suite échoue
//   2. l'observation de l'état système
//   3. la prise de contact TCC, hors de tout chemin de session (R1)
//
// Rien ici ne demande de permission. Une invite volerait le focus, et à ce stade
// l'application n'a encore rien à capturer.
// ─────────────────────────────────────────────────────────────────────────────

// Auto-test de la porte à verrou : 13 séquences d'événements, sans permission ni écran.
// Reprises telles quelles du lot 0, où elles ont été vérifiées comme détectant
// réellement les défauts qu'elles couvrent.
if CommandLine.arguments.contains("--selftest") {
    exit(GateSelfTest.runAll() == 0 ? 0 : 1)
}

// La table de cas de la conversion de coordonnées tourne sans écran, sans permission
// et sans interface : elle vérifie des dispositions qu'on n'a pas sous la main.
if CommandLine.arguments.contains("--geometry-test") {
    exit(GeometrySelfTest.runAll() == 0 ? 0 : 1)
}

// Les marques : numérotation, modes de peinture, ancrage des badges, codes de la palette
// et confinement à la fenêtre cible. Tourne sans écran et sans permission — ce qu'il
// vérifie est du calcul, pas de l'affichage.
// Le recadrage et la gravure : rectangles, paliers de facturation et conversions de
// repère. Aucun écran, aucune permission — ce sont des calculs.
// Le mode ENFANT du banc d'écriture — avant tout le reste : il doit sortir sans
// toucher à AppKit ni aux permissions, c'est un pur écrivain de lignes.
if let i = CommandLine.arguments.firstIndex(of: "--append-bench") {
    exit(AppendSelfTest.bench(Array(CommandLine.arguments.dropFirst(i + 1))))
}

if CommandLine.arguments.contains("--append-test") {
    exit(AppendSelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--projet-test") {
    exit(MainActor.assumeIsolated { ProjetSelfTest.run() } ? 0 : 1)
}

if let i = CommandLine.arguments.firstIndex(of: "--publier-bench") {
    exit(PublieurSelfTest.bench(Array(CommandLine.arguments.dropFirst(i + 1))))
}

if CommandLine.arguments.contains("--publier-test") {
    exit(PublieurSelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--render-test") {
    exit(RenderSelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--capture-test") {
    exit(CaptureSelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--marks-test") {
    exit(MainActor.assumeIsolated { MarksSelfTest.run() } ? 0 : 1)
}

// Le décodeur de réglette — l'instrument de C11, donc le seul instrument existant
// contre B1. Il fabrique ses propres images : un instrument dont la vérification
// exigerait l'appareil qu'il mesure ne se vérifierait jamais.
// L'icône de la barre de menus se mesure hors écran : deux corrections plausibles
// s'y sont trompées avant qu'un pixel soit compté.
if CommandLine.arguments.contains("--icone-test") {
    exit(MainActor.assumeIsolated { IconSelfTest.run() } ? 0 : 1)
}

if CommandLine.arguments.contains("--reglette-test") {
    exit(RegletteSelfTest.run() ? 0 : 1)
}

// Lecture d'un PNG déposé, pour le banc C11 et pour la recette manuelle.
//
// Le banc en a besoin : il capture, il écrit, puis il relit. Et c'est ce qui rend
// l'accord avec l'implémentation de référence Python constatable sur la MÊME
// image — deux décodeurs indépendants sur un seul fichier, ce qui vaut mieux que
// deux décodeurs sur deux fichiers.
if let i = CommandLine.arguments.firstIndex(of: "--lire-reglette") {
    guard i + 1 < CommandLine.arguments.count else {
        FileHandle.standardError.write(Data("usage : --lire-reglette <image.png>\n".utf8))
        exit(2)
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("refus  image illisible : \(url.path)")
        exit(1)
    }
    switch FrameNumberReader.lire(image) {
    case .lu(let v, let diag):
        print("V          \(v)")
        print("module     \(String(format: "%.2f", diag.module))")
        print("origine    (\(Int(diag.origine.x)), \(Int(diag.origine.y)))")
        print("contraste  \(diag.contraste)")
        print("marge      \(diag.margeMin)")
        print("faibles    \(diag.bitsFaibles)")
        exit(0)
    case .refus(let r):
        print("refus      \(r)")
        exit(1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: logSubsystem, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.reset()
        Journal.event(.system, "démarrage")

        // La disposition du clavier doit être résolue AVANT l'enregistrement des
        // raccourcis : ils s'appuient sur elle pour trouver la bonne touche.
        KeyboardLayout.shared.start(resolving:
            HotKeyAction.allCases.map(\.character) + MarkTool.allCases.map(\.key) + ["z"])
        ToolKeyCache.shared.start()
        Journal.section("Clavier", KeyboardLayout.shared.describe())

        StatusItemController.shared.setUp()
        OverlayController.shared.setUp()
        SessionCoordinator.shared.observeSystemState()

        HotKeyCenter.shared.onAction = { action in
            MainActor.assumeIsolated { AppDelegate.handle(action) }
        }
        // Le tap alimente le ring que le contrôleur draine. Sans les deux autorisations
        // d'entrée, il ne démarre pas — le doctor le dit, et ⌃⌥S reste atteignable.
        // La cible est suivie en CONTINU, et la porte s'active dès que le tap tourne.
        //
        // C'est ce que le mode éclair exige (§ 2.1) : il n'ouvre pas de session, ne
        // produit pas d'état, et doit pourtant armer sur ce que l'utilisateur regarde à
        // la seconde où il prend ⌥⌘. Une porte fermée hors session le rendrait
        // inaccessible, alors que c'est le mode majoritaire.
        //
        // Ce que le confinement à la fenêtre cible garantit reste entier : hors de cette
        // fenêtre, ⌥⌘ n'arme pas et le clic part à l'application dessous.
        OptionGate.shared.currentMode = .passthrough
        TargetWindow.shared.follow()

        if TestFlags.visibleCapture {
            Journal.warn(.system, "--visible-capture : le calque APPARAÎT dans les captures")
        }

        if EventTap.shared.start() {
            EventTap.shared.startWatchdog()
            OptionGate.shared.currentMode = .active
            Journal.event(.system, "tap démarré — ⌥⌘ + glisser trace, ⌃⌥S ouvre une session")
        } else {
            // Sans tap, rien à arbitrer : la porte reste fermée pour que le reste de
            // l'application ne se croie pas en état de tracer.
            OptionGate.shared.currentMode = .passthrough
            Journal.warn(.system, "tap non démarré — voir le diagnostic (⌃⌥S)")
        }

        HotKeyCenter.shared.install()
        Journal.section("Raccourcis", HotKeyCenter.shared.describe())

        // Vérification de bout en bout de la capture, sans passer par le tap : elle ne
        // doit dépendre d'aucune autorisation d'injection, qui n'a rien à voir avec elle.
        if CommandLine.arguments.contains("--capture-demo") {
            CaptureDemo.run()
            return
        }

        // Diagnostic complet au démarrage, sous la vraie identité de l'application.
        // Chaque ligne exécute son opération réelle — c'est tout l'objet de S11.
        Task { await Doctor.shared.runAll() }
    }

    /// Aiguillage des raccourcis. Au lot 1, seul le diagnostic a une destination
    /// réelle : les autres actions attendent les lots qui les portent.
    @MainActor
    static func handle(_ action: HotKeyAction) {
        switch action {
        case .openSession:
            // ⌃⌥S ouvre une session, et retombe sur le diagnostic quand elle ne peut pas
            // s'ouvrir. Le critère de S10 tient toujours : le raccourci répond sans
            // aucune permission, et sans permission il montre justement le diagnostic.
            SessionCoordinator.shared.openSession()
        case .endSession:
            SessionCoordinator.shared.closeSession()
        case .toggleMicrophoneLock:
            Journal.event(.key, "⌃⌥M — verrou du micro, lot 5")
        case .toggleAnnotationLock:
            Journal.event(.key, "⌃⌥L — mode annotation verrouillé, à venir")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// `.accessory` : aucune icône dans le Dock, ignoré par Stage Manager, et surtout
// incapable de devenir actif de lui-même. C'est ce qui garantit par construction que
// l'application testée ne perd jamais le focus.
app.setActivationPolicy(.accessory)
app.run()
