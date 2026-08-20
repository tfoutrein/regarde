// swift-tools-version: 6.2
import PackageDescription

// Application de production. Distincte de `prototypes/lot0/`, dont le code est un
// prototype de risque destine a etre jete : ce qui en est repris l'est deliberement,
// module par module, apres avoir ete valide par la campagne de mesure du lot 0.

let package = Package(
    name: "Regarde",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Regarde",
            path: "Sources/Regarde",
            swiftSettings: [
                // Le callback du tap tourne sur son propre thread avec sa run loop, et
                // les rappels Carbon sont des callbacks C : on assume explicitement les
                // franchissements d'isolation qu'ils imposent, plutot que de les subir.
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
