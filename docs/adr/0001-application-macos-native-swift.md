---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: —
---

# ADR-0001 — Regarde est une application macOS native écrite en Swift/SwiftUI

## Contexte

Pendant qu'une autre application tourne et garde le focus, Regarde doit simultanément :
intercepter les événements souris et décider par événement s'ils passent, capturer l'écran en
continu à 15 fps en résolution native, dessiner un calque au-dessus de tout avec une latence p95
sous 33 ms, transcrire la parole hors ligne, et lire l'état des processus voisins. Le choix de la
pile décide si ces cinq briques sont possibles, pas seulement si elles sont agréables à écrire.

L'auteur travaille en React/TypeScript. Il n'a écrit ni Swift, ni AppKit, ni de callback C
CoreGraphics. La spécification chiffre ce handicap au lieu de l'ignorer (§ 11.1) : ×1,2 sur
SwiftUI, ×1,8 sur AppKit, ×2,0 à ×2,5 sur le tap `CGEvent` et les callbacks C, ×2,0 sur
ScreenCaptureKit et `CMTime`, ×1,5 transverse sur la concurrence Swift 6 stricte, ×2,0 sur la
signature et TCC. Total MVP : 40 journées-homme, soit 4 à 5 mois de soirées. C'est ce chiffre,
pas une préférence esthétique, qui rend la question ouverte.

## Décision

Regarde est une application macOS native en Swift : SwiftUI pour le HUD, la revue et les
réglages, AppKit pour les fenêtres de calque et la barre de menus. Aucun moteur web, aucun
runtime tiers dans le bundle. Cible macOS 26.0+ sur Apple Silicon, bundle
`dev.tfoutrein.regarde`, binaires `Regarde.app` et sidecar `regarde-mcp`.

## Options envisagées

### Option A — Swift/SwiftUI natif (retenue)
- **Pour** : accès direct à `CGEventTap`, `SCStream`, `AVAssetWriter`, `SpeechAnalyzer`,
  `NSPanel` et `CAShapeLayer` sans couche intermédiaire ; les frames `CVPixelBuffer` ne
  traversent jamais de frontière ; un seul processus, une seule identité de signature.
- **Contre** : pile totalement inconnue de l'auteur, tous les multiplicateurs du § 11.1
  s'appliquent, pas de hot reload, aucune réutilisation du savoir-faire existant.

### Option B — Tauri v2 (noyau Rust, interface WKWebView)
- **Pour** : interface en React, empreinte mémoire très inférieure à Electron, outillage de
  signature intégré.
- **Contre** : `SpeechAnalyzer`, `SpeechTranscriber` et `SpeechDetector` sont exposés en Swift
  seulement (types `async` et `AsyncSequence`, pas de façade C ni Objective-C) : il faut de
  toute façon un module Swift compagnon. Le tap, ScreenCaptureKit et `AVAssetWriter`
  s'atteignent par des liaisons `objc2` non officielles, sur lesquelles la moindre régression
  se débogue sans symboles. Les multiplicateurs ×2,0 à ×2,5 ne disparaissent pas : ils se
  paient en Rust, augmentés d'une couche FFI. Option B converge mécaniquement vers l'option D.

### Option C — Electron
- **Pour** : la pile la plus familière, écosystème mûr.
- **Contre** : `desktopCapturer` ne rend pas de `CMSampleBuffer` — ni PTS, ni contrôle du GOP,
  ni `dirtyRect`, donc ni l'appariement marque ↔ frame ni `assetTime()` du § 3.2. Aucun accès au
  tap sans module natif, c'est-à-dire sans réécrire le callback C dans un troisième environnement.
  Le lot 3 fixe le RSS de session à moins de 200 MiB anneau de frames compris (≈ 120 MiB) : il
  reste 80 MiB, budget qu'aucun runtime Chromium ne tient. Et une `BrowserWindow` transparente
  permanente est la couche de composition que le § 4.1 écarte et que C3b plafonne à 5 % de
  dégradation.

### Option D — Daemon Swift + interface web
- **Pour** : la seule option hybride honnête ; le noyau reste natif, l'interface réutilise le
  savoir-faire React.
- **Contre** : la frontière IPC tombe au mauvais endroit. Le badge suit le curseur, dessiné par
  un `CAShapeLayer` alimenté par display link sous le budget C7 (< 33 ms p95) ; la revue affiche
  des vignettes de frames, donc des images à faire traverser la frontière. Ce que l'option
  décharge réellement, ce sont les réglages et l'onboarding, soit la ligne ×1,2 du calibrage,
  la moins chère. Elle ajoute en échange deux chaînes d'outillage, un protocole à maintenir et
  un second runtime à durcir et notariser (voir [ADR-0002](0002-hors-sandbox-developer-id.md)).

## Justification

Le noyau du produit est natif dans les quatre options : aucune ne supprime le tap, la capture
ScreenCaptureKit, l'encodage HEVC ni la transcription locale. Ce qui varie, c'est uniquement le
chrome d'interface — une icône de barre de menus, un HUD de quelques lignes, un panneau de revue
et des réglages. Une pile web achète donc une remise sur la plus petite ligne du calibrage et
paie un supplément FFI ou IPC sur les plus grosses.

Le second argument est un mode d'échec, pas un coût. Le § 11.1 décrit un débogage aveugle :
`tapCreate` renvoie `nil` sans exception, la capture sort noire sans erreur, une re-signature
désactive le tap silencieusement. Une panne muette traversée par FFI reste muette, avec un étage
d'ignorance de plus.

## Conséquences

- **Positives** : un seul processus propriétaire des `CVPixelBuffer`, ce dont dépendent
  l'appariement sur la file d'encodage ([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md))
  et l'arbitrage par événement ([ADR-0005](0005-cgeventtap-arbitre-unique.md)) ; une seule identité
  de signature face à TCC ; les budgets CPU, RSS et latence du lot 3 restent atteignables.
- **Négatives** — le prix à payer, assumé : aucun hot reload, 20 à 40 s par itération sur le
  calque contre 2 s en React, sur les 11,5 j des lots 2 et 5 qui sont précisément les lots
  d'interface ; la concurrence Swift 6 stricte refuse à la compilation ce qu'un développeur
  JavaScript écrit par réflexe, d'où le ×1,5 transverse ; l'apprentissage se fait sur le chemin
  critique, sans filet, et alimente directement le risque R15 (enlisement), désigné comme le
  mode d'échec le plus probable du projet.
- **Ce que ça ferme** : aucune contribution extérieure sans Swift ; aucun composant partagé avec
  les autres projets de l'auteur ; un portage Windows ou Linux reste une réécriture — perte
  surtout nominale, puisque les API du noyau sont macOS-only dans toutes les options.

## Signal de révision

Le suivi d'effort réel par lot. Si le chrome d'interface (HUD, revue, réglages, onboarding)
dépasse 30 % de l'effort cumulé constaté des lots 1 à 5, l'hypothèse « l'interface est la petite
partie » est fausse et l'option D redevient défendable pour le panneau de revue et les réglages.
Second signal, plus brutal : si un second développeur devient nécessaire et qu'aucun candidat de
l'entourage n'écrit Swift, le coût de cette décision passe de lent à bloquant.

## Références

- Spécification § 4.1, § 5.2 (budgets mesurés), § 11.1 (calibrage), § 11.2 (C3b, C7), § 14.
- [ADR-0002](0002-hors-sandbox-developer-id.md), [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0005](0005-cgeventtap-arbitre-unique.md), [ADR-0012](0012-speechanalyzer-avec-speechdetector.md).
