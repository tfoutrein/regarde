# Décisions d'architecture — Regarde

Une décision par fichier, numérotée, jamais réécrite. Quand une décision change, on écrit
un nouvel ADR qui remplace le précédent et on passe l'ancien au statut `remplacé par`.
L'historique des choix vaut autant que les choix eux-mêmes : il évite de refaire trois fois
le même débat.

Format : [`0000-template.md`](0000-template.md).

## Statuts

| Statut | Signification |
|---|---|
| `proposé` | Rédigé, pas encore tranché |
| `accepté` | Tranché, fait foi pour le développement |
| `rejeté` | Étudié puis écarté — conservé pour la trace |
| `remplacé par ADR-XXXX` | Dépassé par une décision ultérieure |
| `obsolète` | Le contexte a disparu, la décision n'a plus d'objet |

## Index

Vingt décisions, toutes au statut `accepté` à la date du 19 août 2026. La colonne « Lot »
renvoie au découpage du [plan de développement](../PLAN-DE-DEVELOPPEMENT.md) ; `—` signale une
décision transverse, qui ne s'incarne dans aucun lot en particulier.

### Plateforme et distribution

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0001](0001-application-macos-native-swift.md) | Regarde est une application macOS native écrite en Swift/SwiftUI | — | accepté |
| [0002](0002-hors-sandbox-developer-id.md) | Regarde est distribuée hors App Sandbox, signée Developer ID et notarisée | 1 et 8 | accepté |

### Entrée et calque

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0005](0005-cgeventtap-arbitre-unique.md) | Le `CGEventTap` est l'arbitre unique des événements souris | 0 | accepté |
| [0006](0006-modificateur-option-commande.md) | Le mode annotation s'arme par ⌥⌘ maintenu, configurable, sans double-appui | 2 | accepté |
| [0010](0010-calque-ordonne-pendant-le-trace-seulement.md) | Le calque d'annotation n'est ordonné à l'écran que pendant le tracé | 0 | accepté |
| [0021](0021-desambiguisation-option-commande-chiffre.md) | `⌥⌘ + chiffre` est désambiguïsé par la présence d'une marque attachée | 2 | accepté |

### Capture, temps et géométrie

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md) | Encoder la capture en HEVC continu sur disque plutôt que conserver un ring buffer de frames en RAM | 3 | accepté |
| [0004](0004-preroll-opt-in.md) | Maintenir un pré-roll permanent en mode économe, activé par consentement explicite | 3 | accepté |
| [0007](0007-horloge-maitresse-unique.md) | `CMClockGetHostTimeClock()` est l'horloge maîtresse unique de la session | 3 et 5 | accepté |
| [0008](0008-temps-asset-distinct-du-temps-session.md) | Le temps de l'asset n'est pas le temps de session : `firstSamplePTS` et `assetTime()` | 3 | accepté |
| [0009](0009-geometrie-normalisee-sur-contentrect-de-frame.md) | La géométrie normalisée est relative au `contentRect` de la frame retenue | 3 | accepté |

### Voix et transcription

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0011](0011-micro-par-fenetre-de-parole.md) | Le micro est ouvert par fenêtre de parole liée au geste, jamais en continu | 5 | accepté |
| [0012](0012-speechanalyzer-avec-speechdetector.md) | La transcription repose sur SpeechAnalyzer avec SpeechDetector obligatoire, 100 % local | 5 | accepté |

### Modèle de données

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0013](0013-numerotation-definitive-au-mousedown.md) | Le numéro d'une marque est attribué au `mouseDown` et n'est jamais renuméroté | 2 | accepté |
| [0014](0014-journal-append-only.md) | Une session est un journal d'événements append-only, projeté en une structure `Session` | 4 | accepté |

### Artefacts et intégration avec l'agent

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) | Le disque est la source de vérité, un sidecar MCP stdio n'en est qu'une vue | 6 | accepté |
| [0016](0016-aucune-image-via-mcp.md) | Aucune image dans le chemin nominal MCP : le canal principal est le texte et le chemin absolu | 4 et 6 | accepté |
| [0017](0017-detection-projet-trois-etats.md) | Le projet cible est détecté à trois états et tranché à l'ouverture de session | 4 | accepté |
| [0018](0018-presse-papiers-et-injection-best-effort.md) | La livraison passe par une phrase au presse-papiers restaurable, doublée d'une injection best-effort | 4 | accepté |

### Périmètre et confidentialité

| N° | Décision | Lot | Statut |
|---|---|---|---|
| [0019](0019-providers-hors-mvp-protocole-fige.md) | Aucun provider contextuel dans le MVP, protocole `ContextProvider` figé dès maintenant | — | accepté |
| [0020](0020-confidentialite-capture-continue.md) | Cinq mesures de confidentialité pour une capture continue de l'écran entier | 1 et 4 | accepté |
