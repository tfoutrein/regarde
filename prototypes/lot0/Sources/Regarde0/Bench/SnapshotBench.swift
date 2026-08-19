import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers
import os

// ─────────────────────────────────────────────────────────────────────────────
// T0.9 — Banc C11 : appariement marque ↔ frame
//
// Ce que le plan § 4.5 dit clairement : **au lot 0, c'est l'etalonnage du banc, pas
// le verdict**. Il n'y a pas encore de flux continu ; l'appariement de l'ADR-0008
// n'existera qu'au lot 3. Ce qu'on mesure ici est la latence propre du chemin
// `SCScreenshotManager.captureImage` — utile a connaitre pour le mode eclair du lot 2,
// et indispensable pour que le banc soit deja rode quand C11 rendra son verdict.
//
// Protocole : le temoin 1 en mode compteur affiche son numero de frame en tres gros.
// On declenche une capture au mouseDown, on lit le numero GRAVE DANS L'IMAGE, et on
// le compare a celui que la page a journalise au meme instant hote.
// Tolerance : une frame a 60 fps, soit 16 ms.
// ─────────────────────────────────────────────────────────────────────────────

actor SnapshotBench {
    static let shared = SnapshotBench()

    private let log = Logger(subsystem: logSubsystem, category: "bench")

    private var enabled = false
    private var outputDirectory: URL?
    private var shots: [Shot] = []

    /// Contenu partageable mis en cache.
    ///
    /// `SCShareableContent.current` est couteux et surtout, c'est lui qui declenche la
    /// verification TCC. L'appeler au moment du geste ferait exactement ce que le lot 1
    /// interdit : une prise de contact TCC dans le chemin d'une session. On le rafraichit
    /// au lancement et sur changement d'ecrans, jamais au clic.
    private var cachedContent: SCShareableContent?
    private var contentFetchedAt: Date?

    struct Shot: Sendable {
        let index: Int
        let sessionTime: SessionTime
        let requestedAtTicks: UInt64
        let capturedAtTicks: UInt64
        let displayID: CGDirectDisplayID
        let path: URL?
        let error: String?

        /// Delai entre la decision (mouseDown) et l'image effectivement obtenue.
        var latencyMs: Double { SessionClock.millis(from: requestedAtTicks, to: capturedAtTicks) }
    }

    // MARK: - Configuration

    func enable(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        outputDirectory = directory
        enabled = true
        log.notice("banc C11 actif → \(directory.path, privacy: .public)")
    }

    func disable() { enabled = false }
    var isEnabled: Bool { enabled }

    /// Prise de contact TCC, hors de tout chemin de geste.
    func warmUp() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            cachedContent = content
            contentFetchedAt = Date()
            log.notice("contenu partageable en cache : \(content.displays.count) ecran(s)")
        } catch {
            // Echec attendu si Enregistrement de l'ecran n'est pas accorde. Ce n'est pas
            // bloquant : le geste, lui, n'en a pas besoin.
            log.notice("contenu partageable indisponible : \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Capture

    /// Declenche une capture pour un `mouseDown`. Sans effet si le banc est inactif.
    func capture(at sessionTime: SessionTime, eventLocation: CGPoint, requestedAtTicks: UInt64) async {
        guard enabled, let dir = outputDirectory else { return }

        let index = shots.count + 1
        // `NSScreen` n'est pas Sendable : on ne le fait jamais franchir la frontiere
        // d'isolation. Seul l'identifiant sort, et c'est le seul dont on ait besoin.
        let displayID = await MainActor.run { () -> CGDirectDisplayID in
            let screen = Coordinates.screen(containingEventLocation: eventLocation)
            return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value ?? CGMainDisplayID()
        }

        do {
            let image = try await captureImage(displayID: displayID)
            let done = SessionClock.hostTicksNow()
            let url = dir.appendingPathComponent(
                String(format: "c11-%03d-t%.3f.png", index, sessionTime.seconds)
            )
            try write(image, to: url)
            shots.append(Shot(index: index, sessionTime: sessionTime,
                              requestedAtTicks: requestedAtTicks, capturedAtTicks: done,
                              displayID: displayID, path: url, error: nil))
            log.info("C11 #\(index) — \(url.lastPathComponent, privacy: .public)")
        } catch {
            shots.append(Shot(index: index, sessionTime: sessionTime,
                              requestedAtTicks: requestedAtTicks,
                              capturedAtTicks: SessionClock.hostTicksNow(),
                              displayID: displayID, path: nil,
                              error: error.localizedDescription))
            log.error("C11 #\(index) a echoue : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureImage(displayID: CGDirectDisplayID) async throws -> CGImage {
        // Rafraichir le cache s'il est vieux : un ecran a pu etre branche entre-temps.
        if cachedContent == nil || (contentFetchedAt.map { Date().timeIntervalSince($0) > 30 } ?? true) {
            await warmUp()
        }
        guard let content = cachedContent else { throw BenchError.noShareableContent }
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else { throw BenchError.displayNotFound(displayID) }

        // S'exclure soi-meme du filtre. `sharingType = .none` sur le panneau ne suffit
        // pas : il est ignore par ScreenCaptureKit depuis macOS 15.4 (§ 4.1). C'est
        // l'exclusion par application qui fait le travail, et elle couvre aussi les
        // fenetres creees apres coup — le critere R12.
        let selfBundleID = Bundle.main.bundleIdentifier
        let ourApps = content.applications.filter { $0.bundleIdentifier == selfBundleID }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ourApps,
                                     exceptingWindows: [])

        let cfg = SCStreamConfiguration()
        // Resolution native : sans width/height explicites, la capture sort en 1920×1080
        // et le numero du compteur devient illisible — la mesure serait perdue (§ 5.2).
        //
        // `pointPixelScale` est un Float, `contentRect` est en CGFloat : la conversion est
        // explicite pour que personne n'aille supposer un facteur entier de 2. Sur un
        // ecran externe non-Retina il vaut 1,0, et le lot 3 devra le lire par frame.
        let scale = CGFloat(filter.pointPixelScale)
        cfg.width = Int(filter.contentRect.width * scale)
        cfg.height = Int(filter.contentRect.height * scale)
        cfg.captureResolution = .best
        cfg.scalesToFit = false
        cfg.showsCursor = false
        cfg.colorSpaceName = CGColorSpace.sRGB

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    private func write(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw BenchError.encodingFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw BenchError.encodingFailed }
    }

    // MARK: - Rapport

    func report() -> String {
        guard !shots.isEmpty else {
            return "Banc C11 : aucune capture. Active le banc, passe le temoin 1 en mode compteur, et trace."
        }
        let ok = shots.filter { $0.error == nil }
        let lat = ok.map(\.latencyMs).sorted()
        let p50 = lat.isEmpty ? 0 : lat[lat.count / 2]
        let worst = lat.last ?? 0

        var lines = [
            "┌─ Banc C11 — etalonnage (T0.9) ───────────────────────────────────┐",
            String(format: "│ captures %d  reussies %d  echouees %d                        │",
                   shots.count, ok.count, shots.count - ok.count),
            String(format: "│ latence mouseDown → image : mediane %.1f ms  pire %.1f ms   │", p50, worst),
            "│                                                                  │",
            "│ Verdict C11 : NON RENDU au lot 0 — voir plan § 4.5.              │",
            "│ Comparer a la main le numero grave dans chaque PNG au journal du  │",
            "│ temoin 1, avec l'alignement d'horloge. Tolerance 16 ms.           │",
            "└──────────────────────────────────────────────────────────────────┘",
        ]
        if let dir = outputDirectory { lines.append("Images : \(dir.path)") }
        return lines.joined(separator: "\n")
    }

    func shotsJSON() -> String {
        let rows = shots.map { s in
            """
              { "index": \(s.index), "sessionTimeS": \(String(format: "%.3f", s.sessionTime.seconds)), \
            "latenceMs": \(String(format: "%.1f", s.latencyMs)), \
            "display": \(s.displayID), \
            "fichier": \(s.path.map { "\"\($0.lastPathComponent)\"" } ?? "null"), \
            "erreur": \(s.error.map { "\"\($0)\"" } ?? "null") }
            """
        }
        return "[\n" + rows.joined(separator: ",\n") + "\n]"
    }

    enum BenchError: LocalizedError {
        case noShareableContent
        case displayNotFound(CGDirectDisplayID)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .noShareableContent:
                "Contenu partageable indisponible — Enregistrement de l'ecran probablement refuse."
            case .displayNotFound(let id):
                "Ecran \(id) absent du contenu partageable."
            case .encodingFailed:
                "Encodage PNG impossible."
            }
        }
    }
}
