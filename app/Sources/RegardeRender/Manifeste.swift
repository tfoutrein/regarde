import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Le manifeste — S48, spécification § 9.5, `schemaVersion 1.1`
//
// `manifest.json` est LA source ; tout le reste — `report.md`, `paste-web.md`,
// les réponses du sidecar — en est un rendu (§ 9.1, P4 ; § 9.3). Ces types sont
// donc le CONTRAT entre l'application, le disque et le sidecar du lot 6 : les
// noms de propriétés sont les clés JSON du § 9.5, en anglais, sans couche de
// traduction — le format est le contrat, les identifiants suivent le format.
//
// AUCUN type du modèle applicatif n'apparaît ici, et la cible ne dépend de rien
// d'autre que Foundation : c'est ce qui permet au sidecar de la lier sans
// embarquer l'application. L'application TRADUIT ses `Mark`, `CaptureSegment`
// et compagnie vers ces types au moment de publier — la traduction est le mur.
//
// LES RÉSERVATIONS DE 1.1. Deux clés existent dès maintenant pour que S58
// n'ait PAS à toucher au schéma : `budget.framesTokens.full_hires`, et le rôle
// de frame `full_hires`. Les ajouter plus tard serait un 1.2 ; les réserver
// aujourd'hui coûte deux lignes. Le décodage IGNORE les clés inconnues — un
// manifeste 1.2 futur restera lisible par un lecteur 1.1 pour tout ce que 1.1
// connaît.
// ─────────────────────────────────────────────────────────────────────────────

public enum Manifeste {

    public static let schemaVersionCourante = "1.1"

    // MARK: - Racine

    public struct Racine: Codable, Sendable {
        public var schemaVersion: String
        public var session: Session
        public var marks: [Mark]
        public var frames: [Frame]
        public var budget: Budget

        public init(schemaVersion: String = Manifeste.schemaVersionCourante,
                    session: Session, marks: [Mark], frames: [Frame], budget: Budget) {
            self.schemaVersion = schemaVersion
            self.session = session
            self.marks = marks
            self.frames = frames
            self.budget = budget
        }
    }

    // MARK: - Session

    public struct Session: Codable, Sendable {
        public var number: Int
        public var uuid: String
        public var id: String
        public var startedAt: String            // ISO 8601 avec fuseau, § 9.5
        public var durationSeconds: Double
        public var wallDurationSeconds: Double
        public var tool: Tool
        public var locale: String
        public var captureSegments: [CaptureSegment]
        /// Latence d'entrée audio compensée (§ 3.6) — diagnostic : le § 9.4 ne
        /// la rend pas, elle vit ici pour qui relit un ancrage douteux.
        public var audioInputLatencyMs: Int?
        /// Les commentaires GÉNÉRAUX — ceux qui ne visent aucune marque (S67).
        /// Même forme que `marks[].voice[]`, sans `attachedTo` : un seul
        /// vocabulaire pour la parole, où qu'elle aille.
        public var voice: [Voice]?
        /// Le contexte que le rendu affiche tel quel — sept lignes, chacune avec
        /// son producteur (S53). Optionnel : une session éclair n'en a pas tous.
        public var context: Context?

        public init(number: Int, uuid: String, id: String, startedAt: String,
                    durationSeconds: Double, wallDurationSeconds: Double,
                    tool: Tool, locale: String,
                    captureSegments: [CaptureSegment], context: Context?,
                    audioInputLatencyMs: Int? = nil, voice: [Voice]? = nil) {
            self.number = number; self.uuid = uuid; self.id = id
            self.startedAt = startedAt
            self.durationSeconds = durationSeconds
            self.wallDurationSeconds = wallDurationSeconds
            self.tool = tool; self.locale = locale
            self.captureSegments = captureSegments; self.context = context
            self.audioInputLatencyMs = audioInputLatencyMs
            self.voice = voice
        }
    }

    public struct Tool: Codable, Sendable {
        public var name: String
        public var version: String
        public var os: String
        public var build: String
        public init(name: String, version: String, os: String, build: String) {
            self.name = name; self.version = version; self.os = os; self.build = build
        }
    }

    public struct CaptureSegment: Codable, Sendable {
        public var index: Int
        public var displayID: UInt32
        public var codec: String
        public var fps: Int
        public var firstSamplePTSSeconds: Double?
        public var lastSamplePTSSeconds: Double?
        public var pixelSize: Dimensions
        public var deleted: Bool
        public init(index: Int, displayID: UInt32, codec: String, fps: Int,
                    firstSamplePTSSeconds: Double?, lastSamplePTSSeconds: Double?,
                    pixelSize: Dimensions, deleted: Bool) {
            self.index = index; self.displayID = displayID
            self.codec = codec; self.fps = fps
            self.firstSamplePTSSeconds = firstSamplePTSSeconds
            self.lastSamplePTSSeconds = lastSamplePTSSeconds
            self.pixelSize = pixelSize; self.deleted = deleted
        }
    }

    /// Les lignes de la table « Contexte » du rapport (S53 les produira).
    public struct Context: Codable, Sendable {
        public var project: String?
        public var detection: String?           // la phrase complète, verdict compris
        public var git: String?
        public var application: String?
        public var screen: String?
        public var interruptions: String?
        public var status: String?
        public init(project: String?, detection: String?, git: String?,
                    application: String?, screen: String?,
                    interruptions: String?, status: String?) {
            self.project = project; self.detection = detection; self.git = git
            self.application = application; self.screen = screen
            self.interruptions = interruptions; self.status = status
        }
    }

    // MARK: - Marques

    /// Un segment de parole rattaché — § 9.5, membre OPTIONNEL du schéma 1.1 :
    /// un manifeste sans voix est identique à l'octet à ce qu'il était au lot 4.
    public struct Voice: Codable, Sendable {
        public struct Attachment: Codable, Sendable {
            /// `fenetreDeParole` · `debordement` · `gesteGlobal` · `aucuneFenetre`
            public var rule: String
            /// `false` quand l'utilisateur a réaffecté à la main (§ 6.7).
            public var auto: Bool
            /// `true` quand le texte a été corrigé en revue — `rawText` dit l'avant.
            public var editedByUser: Bool
            public init(rule: String, auto: Bool, editedByUser: Bool) {
                self.rule = rule; self.auto = auto; self.editedByUser = editedByUser
            }
        }
        /// Une correction proposée par le lexique (S68) — les DEUX versions sont
        /// au rapport, la relecture tranche.
        public struct LexiconSuggestion: Codable, Sendable {
            public var heard: String
            public var suggested: String
            public var confidence: Double
            public var at: Double
            public init(heard: String, suggested: String, confidence: Double, at: Double) {
                self.heard = heard; self.suggested = suggested
                self.confidence = confidence; self.at = at
            }
        }
        public var id: String                   // "v-002"
        /// Le numéro de marque, absent pour un commentaire général.
        public var attachedTo: Int?
        public var attachment: Attachment
        public var onset: Double
        public var end: Double
        /// Le texte affiché — éditable en revue, marqué par le lexique.
        public var text: String
        /// Le brut, JAMAIS modifié : c'est lui que `transcript.txt` porte.
        public var rawText: String
        public var lexiconSuggestions: [LexiconSuggestion]

        public init(id: String, attachedTo: Int?, attachment: Attachment,
                    onset: Double, end: Double, text: String, rawText: String,
                    lexiconSuggestions: [LexiconSuggestion] = []) {
            self.id = id; self.attachedTo = attachedTo; self.attachment = attachment
            self.onset = onset; self.end = end
            self.text = text; self.rawText = rawText
            self.lexiconSuggestions = lexiconSuggestions
        }
    }

    public struct Mark: Codable, Sendable {
        public var number: Int
        public var kind: String                 // rect · arrow · point · highlight
        public var sessionTime: Double
        public var captureSegment: Int?
        public var isRetroactive: Bool
        public var intents: [String]
        public var geometry: Geometry
        public var frames: MarkFrames?
        public var screenWasMoving: Bool
        /// Nombre de frames de contexte du burst réellement disponibles (0 à 2).
        public var contextFramesAvailable: Int?
        /// Décrit la zone en français, à la suite du rectangle. Optionnelle et
        /// vide dans le MVP — l'absence est silencieuse (P5) ; le lot 5 la
        /// remplira depuis la voix.
        public var zoneNote: String?
        /// Ce qui a été dit pendant la fenêtre de parole de cette marque (S67).
        public var voice: [Voice]?
        /// Le texte d'une note écrite au clavier — `kind` vaut alors « text »
        /// (S70, § 7.4, mode silencieux).
        public var text: String?

        public init(number: Int, kind: String, sessionTime: Double,
                    captureSegment: Int?, isRetroactive: Bool, intents: [String],
                    geometry: Geometry, frames: MarkFrames?, screenWasMoving: Bool,
                    contextFramesAvailable: Int?, zoneNote: String?,
                    voice: [Voice]? = nil, text: String? = nil) {
            self.number = number; self.kind = kind; self.sessionTime = sessionTime
            self.captureSegment = captureSegment; self.isRetroactive = isRetroactive
            self.intents = intents; self.geometry = geometry; self.frames = frames
            self.screenWasMoving = screenWasMoving
            self.contextFramesAvailable = contextFramesAvailable
            self.zoneNote = zoneNote
            self.voice = voice
            self.text = text
        }
    }

    public struct Geometry: Codable, Sendable {
        public var points: Rectangle
        public var pixels: Rectangle
        public var normalized: RectangleNormalise
        public var frameContentRect: Rectangle
        public var frameScaleFactor: Double
        public init(points: Rectangle, pixels: Rectangle,
                    normalized: RectangleNormalise,
                    frameContentRect: Rectangle, frameScaleFactor: Double) {
            self.points = points; self.pixels = pixels; self.normalized = normalized
            self.frameContentRect = frameContentRect
            self.frameScaleFactor = frameScaleFactor
        }
    }

    public struct Rectangle: Codable, Sendable {
        public var x: Double, y: Double, w: Double, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    public struct RectangleNormalise: Codable, Sendable {
        public var x: Double, y: Double, w: Double, h: Double
        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    public struct MarkFrames: Codable, Sendable {
        public var crop: String?
        public var full: String?
        public init(crop: String?, full: String?) { self.crop = crop; self.full = full }
    }

    // MARK: - Frames publiées

    public struct Frame: Codable, Sendable {
        public var id: String
        /// `crop` · `full` · `full_hires` (RÉSERVÉ — S58) · `ensemble`.
        public var role: String
        public var absolutePath: String
        public var size: Dimensions
        public var visualTokens: Int
        public var visualTokensNote: String?
        public var bytes: Int?
        public var marks: [Int]
        public var engravedMarks: [Int]?

        public init(id: String, role: String, absolutePath: String,
                    size: Dimensions, visualTokens: Int, visualTokensNote: String?,
                    bytes: Int?, marks: [Int], engravedMarks: [Int]?) {
            self.id = id; self.role = role; self.absolutePath = absolutePath
            self.size = size; self.visualTokens = visualTokens
            self.visualTokensNote = visualTokensNote; self.bytes = bytes
            self.marks = marks; self.engravedMarks = engravedMarks
        }
    }

    public struct Dimensions: Codable, Sendable {
        public var w: Int, h: Int
        public init(w: Int, h: Int) { self.w = w; self.h = h }
    }

    // MARK: - Budget

    public struct Budget: Codable, Sendable {
        public var reportTokensEstimate: Int
        public var estimateMethod: String
        public var framesTokens: FramesTokens
        public var mcpHardLimit: Int
        public init(reportTokensEstimate: Int, estimateMethod: String,
                    framesTokens: FramesTokens, mcpHardLimit: Int) {
            self.reportTokensEstimate = reportTokensEstimate
            self.estimateMethod = estimateMethod
            self.framesTokens = framesTokens
            self.mcpHardLimit = mcpHardLimit
        }
    }

    public struct FramesTokens: Codable, Sendable {
        public var crop: Int
        public var full: Int
        /// RÉSERVÉ (S58) : présent dans le schéma dès 1.1, renseigné quand
        /// `include_hires` s'active. Nil tant qu'aucune image haute résolution
        /// n'existe — jamais 0, qui affirmerait un coût mesuré.
        public var full_hires: Int?
        public init(crop: Int, full: Int, full_hires: Int?) {
            self.crop = crop; self.full = full; self.full_hires = full_hires
        }
    }

    // MARK: - Lecture

    /// Décode un manifeste. Les clés inconnues sont ignorées (compatibilité
    /// ascendante) ; une `schemaVersion` de MAJEURE différente est refusée
    /// nommément — la mineure passe, c'est sa raison d'être.
    public static func decoder(_ data: Data) throws -> Racine {
        let racine = try JSONDecoder().decode(Racine.self, from: data)
        let majeure = racine.schemaVersion.split(separator: ".").first.map(String.init)
        let attendue = schemaVersionCourante.split(separator: ".").first.map(String.init)
        guard majeure == attendue else {
            throw ErreurLecture.majeureInconnue(lue: racine.schemaVersion,
                                                attendue: schemaVersionCourante)
        }
        return racine
    }

    public enum ErreurLecture: Error, CustomStringConvertible {
        case majeureInconnue(lue: String, attendue: String)
        public var description: String {
            switch self {
            case .majeureInconnue(let l, let a):
                "schemaVersion \(l) — majeure inconnue, ce lecteur parle \(a)"
            }
        }
    }
}
