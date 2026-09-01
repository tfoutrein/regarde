import AppKit
import Foundation
import ImageIO
import RegardeRender

// ─────────────────────────────────────────────────────────────────────────────
// La boucle se ferme — S53
//
// Raccourci → marques → raccourci → le PROJET reçoit son dossier et le
// presse-papiers sa phrase. C'est la huitième session du lot sur treize, et
// c'est voulu : « la boucle ferme, même imparfaite » — un rapport sans voix ni
// contexte enrichi, mais un rapport qu'un agent peut lire ce soir.
//
// Trois pièces, la première pure :
//
//   ASSEMBLER   des données de session → un Manifeste.Racine. Fonction pure,
//               testée sur données fabriquées. C'est ici que les types du
//               modèle applicatif se TRADUISENT vers le contrat du § 9.5 —
//               la frontière de S48 se franchit dans un seul fichier.
//
//   LA PHRASE   § 9.10, au caractère : une ligne, la clause « puis applique
//               les corrections » — sans elle l'agent lit et résume quand le
//               développeur veut qu'il code — et le repli chemin absolu.
//
//   PUBLIER     copier les images, Publieur.publier, state.jsonl par la porte
//               de S47, la phrase au presse-papiers. Chaque étape journalisée.
//
// Pas de projet retenu → pas de publication projet, et le journal le DIT : le
// dossier ~/Regarde reste la sortie de secours, comme depuis le lot 2.
// ─────────────────────────────────────────────────────────────────────────────

enum BouclePublication {

    /// Ce que la session apporte à la publication — capturé AVANT que le modèle
    /// ne soit vidé et la cible relâchée.
    struct Donnees {
        struct Marque {
            let numero: Int
            let genre: String            // arrow · rect · point · highlight · text
            /// Le texte d'une note (S70) — nil pour toute autre forme.
            var note: String?
            let tempsSession: Double
            let intention: String?
            let ecranEnMouvement: Bool
            // S57, défaut D-01 — la géométrie vient de la MARQUE, pas du recadrage.
            // La boîte du recadrage porte sa marge de contexte : publier son repère
            // rendait « rectangle 0×0 pt à (0, 0) » dans chaque rapport réel.
            let boite: NormRect          // bbox de la marque — écran normalisé, origine HAUT-gauche
            let ecranPoints: CGSize      // taille de l'écran porteur, en points
            let facteurEcran: Double     // backingScaleFactor de cet écran
        }
        struct Image {
            let numero: Int
            let url: URL                 // le PNG déjà écrit sous ~/Regarde
            let taillePixels: CGSize
        }
        let uuid: UUID
        let debut: Date
        let dureeSecondes: Double
        let dureeMuraleSecondes: Double
        let cible: String                // saisie AVANT release()
        let ecran: String
        let interruptions: String
        let marques: [Marque]
        let images: [Image]
        let outilVersion: String
        let os: String
        let build: String
        /// Les segments de parole rattachés (S66) — le transcript les écrit,
        /// S67 les rend.
        var voix: [SegmentDeParole] = []
        /// La latence d'entrée compensée (§ 3.6) — diagnostic au manifeste.
        var latenceEntreeMs: Int?
    }

    // MARK: - L'assembleur, pur

    /// Traduit les données de session vers le contrat du § 9.5. Le numéro et
    /// l'id sont PROVISOIRES (0) — l'attribution de S50 les remplace.
    static func assembler(_ d: Donnees, projet: String?, detection: String,
                          git: String?, statut: String = "**nouveau**") -> Manifeste.Racine {
        let imagesParNumero = Dictionary(grouping: d.images, by: \.numero)

        // La voix, traduite vers le § 9.5. Les identifiants « v-NNN » suivent
        // l'ordre du PREMIER MOT, toutes marques confondues : c'est l'ordre
        // dans lequel les choses ont été dites, le seul qui ait un sens pour
        // qui relit. Un segment sans attachement — impossible depuis S64, mais
        // le type l'autorise — part en commentaire général plutôt qu'aux
        // oubliettes : la parole ne se jette jamais en silence.
        let ordonnes = d.voix.sorted { $0.onset < $1.onset }
        var voixParMarque: [Int: [Manifeste.Voice]] = [:]
        var voixGenerale: [Manifeste.Voice] = []
        for (i, segment) in ordonnes.enumerated() {
            let regle: String
            var marque: Int?
            switch segment.attachement {
            case .marque(let n, let r): marque = n; regle = r.rawValue
            case .global(let r): regle = r.rawValue
            case nil: regle = FenetreDeParole.Regle.aucuneFenetre.rawValue
            }
            let voix = Manifeste.Voice(
                id: String(format: "v-%03d", i + 1),
                attachedTo: marque,
                attachment: .init(rule: regle, auto: !segment.aLaMain,
                                  editedByUser: segment.texte != segment.texteBrut),
                onset: segment.onset.seconds, end: segment.fin.seconds,
                text: segment.texte, rawText: segment.texteBrut,
                lexiconSuggestions: segment.suggestions.map {
                    .init(heard: $0.entendu, suggested: $0.propose,
                          confidence: $0.confiance, at: $0.instant)
                })
            if let marque { voixParMarque[marque, default: []].append(voix) }
            else { voixGenerale.append(voix) }
        }

        var frames: [Manifeste.Frame] = []
        var marks: [Manifeste.Mark] = []
        for m in d.marques.sorted(by: { $0.numero < $1.numero }) {
            var refCrop: String?
            if let image = imagesParNumero[m.numero]?.first {
                let id = String(format: "crop-%02d", m.numero)
                refCrop = id
                let w = Int(image.taillePixels.width), h = Int(image.taillePixels.height)
                frames.append(Manifeste.Frame(
                    id: id, role: "crop",
                    absolutePath: image.url.path,   // remplacé à la copie, voir publier()
                    size: .init(w: w, h: h),
                    visualTokens: Bareme.jetonsVisuels(largeur: w, hauteur: h, palier: .standard),
                    visualTokensNote: "min(patches, plafond du palier)",
                    bytes: nil, marks: [m.numero], engravedMarks: [m.numero]))
            }
            let ecranL = Double(m.ecranPoints.width), ecranH = Double(m.ecranPoints.height)
            marks.append(Manifeste.Mark(
                number: m.numero, kind: m.genre, sessionTime: m.tempsSession,
                captureSegment: nil, isRetroactive: false,
                intents: m.intention.map { [$0] } ?? [],
                geometry: .init(
                    points: .init(x: m.boite.x * ecranL, y: m.boite.y * ecranH,
                                  w: m.boite.w * ecranL, h: m.boite.h * ecranH),
                    pixels: .init(x: m.boite.x * ecranL * m.facteurEcran,
                                  y: m.boite.y * ecranH * m.facteurEcran,
                                  w: m.boite.w * ecranL * m.facteurEcran,
                                  h: m.boite.h * ecranH * m.facteurEcran),
                    normalized: .init(x: m.boite.x, y: m.boite.y,
                                      w: m.boite.w, h: m.boite.h),
                    frameContentRect: .init(x: 0, y: 0, w: ecranL, h: ecranH),
                    frameScaleFactor: m.facteurEcran),
                frames: refCrop.map { Manifeste.MarkFrames(crop: $0, full: nil) },
                screenWasMoving: m.ecranEnMouvement,
                contextFramesAvailable: nil, zoneNote: nil,
                voice: voixParMarque[m.numero], text: m.note))
        }

        let totalCrop = frames.filter { $0.role == "crop" }.map(\.visualTokens).reduce(0, +)
        return Manifeste.Racine(
            session: .init(
                number: 0, uuid: d.uuid.uuidString, id: "provisoire",
                startedAt: isoAvecFuseau(d.debut),
                durationSeconds: d.dureeSecondes,
                wallDurationSeconds: d.dureeMuraleSecondes,
                tool: .init(name: "Regarde", version: d.outilVersion, os: d.os, build: d.build),
                locale: "fr-FR", captureSegments: [],
                context: .init(
                    project: projet, detection: detection, git: git,
                    application: d.cible, screen: d.ecran,
                    interruptions: d.interruptions, status: statut),
                audioInputLatencyMs: d.latenceEntreeMs,
                voice: voixGenerale.isEmpty ? nil : voixGenerale),
            marks: marks, frames: frames,
            budget: .init(
                reportTokensEstimate: 0,
                estimateMethod: "approximation 4 car./jeton, pas un tokeniseur",
                framesTokens: .init(crop: totalCrop, full: 0, full_hires: nil),
                mcpHardLimit: 25000))
    }

    /// La phrase du § 9.10, au caractère. Une seule ligne, jamais de retour
    /// chariot : elle se colle dans un champ de saisie d'agent.
    static func phrase(numero: Int, cheminRapport: String) -> String {
        "Lis le feedback #\(numero) avec regarde (get_feedback number=\(numero)) "
        + "puis applique les corrections. "
        + "Si l'outil n'est pas disponible, lis \(cheminRapport)"
    }

    // MARK: - La publication

    struct Resultat {
        let attribution: Publieur.Attribution
        let phrase: String
    }

    /// Publie dans le projet : images copiées, manifeste attribué, rendus
    /// écrits, `state.jsonl` alimenté. Rend la phrase à mettre au presse-papiers.
    static func publier(_ d: Donnees, brouillon: Manifeste.Racine,
                        racine: URL, slug: String?) throws -> Resultat {
        let attribution = try Publieur.attribuer(racine: racine, uuid: d.uuid,
                                                 date: d.debut, slug: slug)

        // Les images d'abord — un manifeste qui référence des fichiers pas
        // encore copiés serait faux le temps d'une course.
        let framesDir = attribution.dossier.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        var manifeste = brouillon
        for i in manifeste.frames.indices {
            let destination = framesDir.appendingPathComponent("\(manifeste.frames[i].id).png")
            let source = URL(fileURLWithPath: manifeste.frames[i].absolutePath)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            manifeste.frames[i].absolutePath = destination.path
            manifeste.frames[i].bytes = (try? FileManager.default
                .attributesOfItem(atPath: destination.path)[.size] as? Int) ?? nil
        }

        manifeste.session.number = attribution.numero
        manifeste.session.id = attribution.id
        manifeste.session.uuid = d.uuid.uuidString

        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encodeur.encode(manifeste)
            .write(to: attribution.dossier.appendingPathComponent("manifest.json"), options: .atomic)
        let rapport = Rendu.rendre(manifeste)
        try Data(rapport.utf8)
            .write(to: attribution.dossier.appendingPathComponent("report.md"), options: .atomic)
        try Data(Rendu.rendre(manifeste, options: .init(profil: .chatWeb)).utf8)
            .write(to: attribution.dossier.appendingPathComponent("paste-web.md"), options: .atomic)

        // `transcript.txt` — VERSIONNABLE (§ 9.2) : le cinquième chemin que
        // git propose, s'il y a eu de la parole. Lisible par tous : un dépôt
        // se partage.
        try Transcript.ecrire(d.voix, dans: attribution.dossier, permissions: 0o644)

        // `state.jsonl` — par LA porte (S47). Gitignoré, append-only, rejouable.
        let state = try AppendOnlyLog(
            url: racine.appendingPathComponent(".regarde/state.jsonl"))
        try state.append(ligne:
            #"{"uuid":"\#(d.uuid.uuidString)","number":\#(attribution.numero),"event":"published","at":"\#(isoAvecFuseau(Date()))"}"#)
        state.fermer()

        let chemin = attribution.dossier.appendingPathComponent("report.md").path
        return Resultat(attribution: attribution,
                        phrase: phrase(numero: attribution.numero, cheminRapport: chemin))
    }

    /// L'ISO 8601 avec le fuseau LOCAL explicite — le § 9.5 le montre ainsi, et
    /// le rendu lit le fuseau dans la chaîne, jamais dans la machine.
    static func isoAvecFuseau(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}
