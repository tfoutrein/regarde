---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 3
---

# ADR-0008 — Le temps de l'asset n'est pas le temps de session : `firstSamplePTS` et `assetTime()`

## Contexte

La capture est un encodage HEVC continu sur disque
([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)) : l'image d'une marque n'est
pas prélevée au moment du geste, elle est extraite après coup du fichier par
`AVAssetImageGenerator`. Les marques, elles, sont datées en `SessionTime` sur l'horloge maîtresse
([ADR-0007](0007-horloge-maitresse-unique.md)).

Or `AVAssetWriter.startSession(atSourceTime:)` décide quel PTS devient le temps 0 **du fichier**.
Ce PTS est celui du premier échantillon réellement reçu, et ScreenCaptureKit ne livre une frame que
lorsque l'écran change : entre le démarrage du `SCStream` et la première frame, il s'écoule 0,3 à
3 s. Demander la frame à `SessionTime` revient donc à demander un instant décalé de
`PTS_première_frame − t0`, systématiquement. La spécification qualifie ce point de « défaut le plus
grave de la conception initiale ».

## Décision

Chaque `CaptureSegment` mémorise `firstSamplePTS` (le PTS passé à `startSession`) et
`lastSamplePTS`. Toute extraction d'image passe par `assetTime(for:clock:)`, qui convertit le
`SessionTime` demandé en PTS, en soustrait `firstSamplePTS`, et **retourne `nil` avec une trace**
si le résultat sort de `[0, duration]`. Le plan de burst `[t − 0,8, t, t + 0,4]` est clampé sur ces
mêmes bornes. Aucun code n'adresse `AVAssetImageGenerator` autrement.

## Options envisagées

### Option A — demander la frame directement à `SessionTime` (conception initiale)
- **Pour** : aucun champ supplémentaire dans le modèle, aucune conversion.
- **Contre** : décalage constant de 0,3 à 3 s. Invisible sur écran statique, systématique sur écran
  animé — c'est-à-dire précisément dans le cas d'usage qui justifie l'existence du produit. Une
  marque posée sur une animation renvoie une image plausible mais fausse, et l'agent reçoit un
  diagnostic construit sur un état que l'utilisateur n'a jamais désigné.

### Option B — forcer `startSession(atSourceTime: .zero)` et réécrire le PTS de chaque échantillon
- **Pour** : le temps de l'asset devient le temps de session, la conversion disparaît à
  l'extraction.
- **Contre** : le problème est déplacé, pas supprimé. Chaque `CaptureSegment` a de toute façon son
  propre premier échantillon (un writer par écran, plus un redémarrage après un `-3821`), donc il
  faut porter un offset par segment quoi qu'il arrive. Et la réécriture met le calcul sur la file
  d'encodage, chemin chaud, tout en produisant un fichier qui ne reflète plus ce que l'encodeur a
  reçu — donc invérifiable quand justement on doute du résultat.

### Option C — un offset unique de session, partagé par tous les segments
- **Pour** : un seul champ, calculé une fois.
- **Contre** : faux dès le deuxième segment. Deux écrans capturés en parallèle démarrent leur
  premier échantillon à des instants différents, et un redémarrage de flux en crée un troisième.
  L'offset unique corrige un segment et introduit l'erreur d'origine sur tous les autres.

### Option D — clamper silencieusement sur `[0, duration]` au lieu de refuser
- **Pour** : chaque marque a toujours une image, jamais de trou dans le rapport.
- **Contre** : renvoie la première ou la dernière frame du segment en la présentant comme l'instant
  désigné. Une marque de la phase `arming` — où `synchronizationClock` est encore `nil` — produirait
  la frame 0 d'un segment démarré plus tard. C'est le mode d'échec que la décision entière cherche
  à supprimer, avec en prime l'apparence de la normalité.

## Justification

Le décalage n'est pas une imprécision, c'est une erreur structurelle qui rend le produit faux là où
il prétend être utile. Le coût de la correction est une soustraction de `CMTime` par extraction et
deux champs par segment ; il n'y a pas d'arbitrage à faire.

Le refus hors bornes plutôt que le clampage silencieux (option D) répond à une règle de conception
plus large : le rapport peut manquer une image, il ne peut pas en contenir une fausse. Le filet
universel du § 5.5 — toute marque conserve sa frame RAM — couvre le cas où `assetTime()` refuse, ce
qui rend le refus peu coûteux en pratique et laisse une trace exploitable dans le journal.

**Ce bug ne se détecte pas à l'œil.** L'image extraite montre une application dans un état
cohérent, simplement une seconde trop tôt ; sans repère absolu, un relecteur humain n'a aucun moyen
de le voir. D'où un test qui fournit ce repère : le critère **C11** installe au lot 0 un compteur
d'images affichant son propre numéro à l'écran, et exige que le numéro gravé sur la marque et le
numéro visible dans l'image coïncident. Le lot 3 rejoue ce harnais contre la chaîne d'extraction
complète, et le risque **R5** en fait sa parade explicite (« visible seulement au test C11 »).

## Conséquences

- **Positives** : l'image d'une marque montre l'instant désigné, ce qui est la condition de vérité
  du produit ; le refus tracé transforme une classe entière d'erreurs silencieuses en défauts
  observables dans le journal ; chaque segment reste autonome, ce que le débranchement d'écran et
  le redémarrage après `-3821` exigent de toute façon.
- **Négatives** — le prix à payer, assumé : toute marque doit porter son `CaptureSegmentID`, sans
  quoi ses pixels deviennent ininterprétables après une réouverture de segment ; `firstSamplePTS`
  n'existe qu'après le premier échantillon, donc une session sur écran totalement figé n'a **aucune**
  image extractible et dépend entièrement du filet RAM ; `lastSamplePTS` n'est stable qu'après
  finalisation, ce qui interdit un clampage exact tant que le segment est ouvert ; et le burst rend
  1, 2 ou 3 images selon les bornes — `t + 0,4` sort systématiquement de l'asset pour une marque
  posée juste avant la fin de session, si bien que le nombre d'images par marque varie sans que
  l'utilisateur comprenne pourquoi.
- **Ce que ça ferme** : plus de fichier vidéo unique par session, chaque segment gardant son
  référentiel ; aucune extraction depuis un asset dont on n'a pas écrit soi-même le writer ; et
  aucun temps d'asset exposé à l'utilisateur ou à l'agent, qui ne voient que du `SessionTime`.

## Signal de révision

C11 qui échoue avec un écart **variable d'une marque à l'autre** plutôt que constant : le décalage
ne serait alors plus un simple offset d'origine, et la conversion par échantillon d'ADR-0007 ne
suffirait pas. Second signal : un taux de refus hors bornes journalisé au-delà de quelques pour
cent des extractions en usage normal, qui signifierait que le plan de burst ou les bornes sont mal
posés, et non que les temps sont faux.

## Références

- Spécification § 3.2 (le temps de l'asset), § 5.4 (décision de burst), § 5.5 (finalisation par
  segment), § 11.2 critère C11, § 12 risque R5 (B1).
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0004](0004-preroll-opt-in.md), [ADR-0007](0007-horloge-maitresse-unique.md),
  [ADR-0009](0009-geometrie-normalisee-sur-contentrect-de-frame.md),
  [ADR-0013](0013-numerotation-definitive-au-mousedown.md).
