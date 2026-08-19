---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 3
---

# ADR-0003 — Encoder la capture en HEVC continu sur disque plutôt que conserver un ring buffer de frames en RAM

## Contexte

Une marque doit produire l'image de l'écran **à l'instant du geste**, et même légèrement avant lui :
la sémantique retenue est la frame qui précède le `mouseDown`, celle où l'élément fautif est encore
dans l'état que l'utilisateur a vu. Il faut aussi pouvoir revenir en arrière : burst à `t − 0,8 s`,
marque rétroactive à `T − N` secondes (§ 5.4, § 5.1). L'écran de référence est un Retina 3456×2234
en `kCVPixelFormatType_32BGRA`, filmé par un `SCStream` par display.

Ce qui est déjà tranché ailleurs et qu'on ne rouvre pas : la capture passe par ScreenCaptureKit,
l'application est native et hors sandbox ([ADR-0001](0001-application-macos-native-swift.md),
[ADR-0002](0002-hors-sandbox-developer-id.md)), et le geste ne doit pas dégrader l'application testée.

## Décision

Le flux de chaque écran est encodé **en continu en HEVC sur disque** par un `AVAssetWriter` piloté par
l'application, avec `AVVideoMaxKeyFrameIntervalDurationKey = 1.0`. Les images de marque sont extraites
après coup par `generateCGImagesAsynchronously(forTimes:)`, un appel par segment finalisé. Le terme
« ring buffer » disparaît du code : il ne subsiste qu'un **anneau de 4 frames brutes**, dont l'unique
rôle est l'appariement marque ↔ frame sur la file d'encodage et le filet en cas d'échec d'extraction.

## Options envisagées

### Option A — Ring buffer RAM de N secondes de frames brutes
- **Pour** : extraction immédiate, aucune compression, aucun décodage, aucun fichier intermédiaire
  sur disque, donc aucune surface de fuite à nettoyer.
- **Contre** : une frame BGRA 3456×2234 pèse **29,45 MiB**. Dix secondes à 15 fps font **4,3 GiB** ;
  à 60 fps, **104 GiB/min**. Rien ne rend ce chiffre acceptable — ni la réduction de résolution
  (qui détruit précisément ce qu'on veut montrer, du texte d'IDE), ni la baisse de cadence
  (qui casse le burst sur écran animé). Multiplié par le nombre d'écrans branchés.

### Option B — `SCRecordingOutput` (l'enregistrement clé en main de ScreenCaptureKit)
- **Pour** : quelques lignes au lieu d'un writer complet ; pas de gestion de PTS, de session
  d'écriture ni de finalisation à écrire soi-même.
- **Contre** : **aucun contrôle du GOP**. Sans intervalle de clé forcé, le seek vers un instant
  arbitraire devient imprévisible et coûteux, ce qui est exactement l'opération centrale du produit.
  Et toute `updateConfiguration` **arrête l'enregistrement sans avertissement** : or on reconfigure
  le flux au moins une fois par session, à la bascule pré-roll → pleine résolution
  ([ADR-0004](0004-preroll-opt-in.md)), et au moindre changement de disposition d'écrans.

### Option C — Pas de capture continue : `SCScreenshotManager.captureImage` au moment de la marque
- **Pour** : c'est l'option simple, celle du lot 2 ; rien à encoder, rien à extraire, rien à purger.
- **Contre** : la capture arrive **après** le geste, avec la latence d'armement du flux (0,3 à 1,5 s).
  Sur un état transitoire — un spinner, un toast, un champ qui repasse au vert — l'image obtenue ne
  montre plus ce qui a fait lever le doigt. Ni burst, ni marque rétroactive, ni frame antérieure au
  `mouseDown` : trois fonctions du produit disparaissent. Conservée comme **filet** (une image
  synchrone au tout premier instant du raccourci), pas comme mécanisme principal.

### Option D — HEVC continu piloté par `AVAssetWriter` (retenue)
- **Pour** : 6,2 Mb/s, soit **46,7 MiB/min** et environ 470 MiB pour dix minutes ; 0,30 s de CPU pour
  20 s de capture 3456×2234 à 15 fps, soit **1,5 % d'un cœur** grâce à l'encodeur matériel ; RSS
  stable à 33 MiB hors anneau. GOP maîtrisé, donc **seek à 31 ms par frame** avec
  `before = .positiveInfinity` / `after = .zero`. Finalisation et extraction **par segment**, ce qui
  isole la perte d'un écran débranché au lieu de perdre la session entière (§ 5.5).
- **Contre** : un fichier vidéo intermédiaire existe ; l'image n'est disponible qu'après finalisation ;
  la compression est destructrice.

## Justification

L'écart entre 4,3 GiB et 470 MiB pour dix **minutes** ne se rattrape par aucun réglage : l'option A
n'est pas chère, elle est impossible sur une machine où l'application testée doit continuer à tourner
normalement. Entre les deux voies d'encodage, ce n'est pas l'ergonomie de l'API qui tranche mais le
GOP : le produit ne lit pas la vidéo, il y pointe des instants isolés et dispersés. Un GOP forcé à
1 s borne le coût de chaque extraction à 31 ms, ce que `SCRecordingOutput` ne permet pas de garantir ;
et son arrêt silencieux sur `updateConfiguration` transforme une reconfiguration bénigne en session
vide, panne que rien ne signale avant la publication.

## Conséquences

- **Positives** : le budget de la capture continue tient dans le critère du lot 3 (RSS < 200 MiB,
  CPU < 3 %, disque < 500 MiB pour 10 min) ; le burst et les marques rétroactives deviennent de
  simples requêtes de temps ; l'échec d'un écran est contenu à son segment.
- **Négatives** — le prix à payer, assumé :
  - Un **fichier vidéo intermédiaire contenant tout l'écran** vit sur le disque pendant la session :
    gestionnaire de mots de passe ouvert à côté, messagerie, autre projet client. C'est la
    contrepartie directe de cette décision, et elle impose tout le dispositif de
    [ADR-0020](0020-confidentialite-capture-continue.md) — `$TMPDIR`, `0600`, purge à chaque
    démarrage de session, suppression dès la fin d'extraction.
  - Le GOP court coûte du débit : c'est une partie des 6,2 Mb/s, payée pour la vitesse de seek.
  - Deux bases de temps cohabitent, puisque le PTS de l'asset ne commence pas au début de la session
    ([ADR-0008](0008-temps-asset-distinct-du-temps-session.md)) ; le clampage n'est pas optionnel.
  - Les images de marque sont issues d'un encodage avec pertes, non d'une copie exacte du framebuffer.
  - La copie de chaque frame `.complete` dans l'anneau de 4 brûle 440 MiB/s de bande passante mémoire,
    poste absent des 1,5 % de CPU ; d'où la double garde (`dirtyRatio > 0`, anneau entretenu seulement
    à partir de la première tenue de ⌥⌘).
- **Ce que ça ferme** : la relecture instantanée sans finalisation ; toute promesse de pixels
  strictement identiques à l'écran ; et l'idée d'une application sans écriture disque pendant la session.

## Signal de révision

Une image de marque en vue `full_hires` où le texte de l'IDE est moins lisible que dans le PNG témoin
pris par `SCScreenshotManager` au même instant : cela signifierait que le compromis de compression
mange l'usage principal, et rouvrirait le choix du codec ou du débit. Second signal, du côté de la
plateforme : `SCRecordingOutput` exposant un contrôle d'intervalle de clé **et** survivant à
`updateConfiguration` justifierait de reprendre l'option B.

## Références

- Spécification § 4.1 (lignes « Ring buffer », « Encodeur », « Instantané de marque »), § 5.2, § 5.5.
- Sondes de faisabilité du lot 0 : coût d'encodage, débit HEVC, temps de seek.
- [ADR-0004](0004-preroll-opt-in.md), [ADR-0008](0008-temps-asset-distinct-du-temps-session.md),
  [ADR-0009](0009-geometrie-normalisee-sur-contentrect-de-frame.md),
  [ADR-0020](0020-confidentialite-capture-continue.md).
