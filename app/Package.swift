// swift-tools-version: 6.2
import PackageDescription

// Application de production. Distincte de `prototypes/lot0/`, dont le code est un
// prototype de risque destine a etre jete : ce qui en est repris l'est deliberement,
// module par module, apres avoir ete valide par la campagne de mesure du lot 0.

let package = Package(
    name: "Regarde",
    platforms: [.macOS(.v26)],
    targets: [
        // La bibliothèque de rendu — S48/S49, spécification § 9.3.
        //
        // Cible SÉPARÉE parce que le § 9.3 l'exige structurellement : le sidecar
        // MCP du lot 6 rend les mêmes rapports, application fermée. Un rendu
        // écrit dans l'application serait réécrit là-bas — 1,5 jour chiffré au
        // § 9.3. La frontière est le manifeste : AUCUN type du modèle applicatif
        // ne traverse — l'application TRADUIT ses types vers ceux du manifeste,
        // et le rendu ne connaît que lui. S37 a montré qu'une frontière posée à
        // moitié ne tient pas ; celle-ci est un mur de l'éditeur de liens.
        .target(
            name: "RegardeRender",
            path: "Sources/RegardeRender",
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .executableTarget(
            name: "Regarde",
            dependencies: ["RegardeRender"],
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
