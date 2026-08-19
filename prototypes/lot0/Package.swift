// swift-tools-version: 6.2
import PackageDescription

// Prototype de reduction de risque du lot 0.
// Ce n'est PAS le squelette de l'application de production : il valide le geste
// (tap arbitre, calque au-dessus de l'app testee, focus jamais vole) et rien d'autre.
// Voir ../../docs/PLAN-DE-DEVELOPPEMENT.md § 4.

let package = Package(
    name: "Regarde0",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Regarde0",
            path: "Sources/Regarde0",
            swiftSettings: [
                // Le callback du tap tourne sur son propre thread avec sa run loop :
                // on assume explicitement les franchissements d'isolation qu'il impose.
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
