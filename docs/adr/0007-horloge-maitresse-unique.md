---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 3 et 5
---

# ADR-0007 — `CMClockGetHostTimeClock()` est l'horloge maîtresse unique de la session

## Contexte

Trois producteurs alimentent une session et aucun ne parle la même langue temporelle : les frames
arrivent horodatées en PTS sur l'horloge de synchronisation du `SCStream`, les marques portent le
`CGEvent.timestamp` de l'événement matériel, la parole est datée par `AVAudioTime.hostTime` du tap
micro. La promesse du produit — chaque commentaire ancré au bon pixel et au bon instant — se réduit
à une question : dans quel référentiel comparer ces trois sources sans introduire d'erreur
dépassant la durée d'une frame. Contrainte de forme : une session commence avant `startCapture()`
(phase `arming`, pré-roll) et survit à l'arrêt d'un flux.

## Décision

`CMClockGetHostTimeClock()` est l'horloge maîtresse. Un unique `SessionClock` capture son origine à
l'entrée en `arming` et expose `SessionTime` (`CMTime` à l'échelle 90 000). Les frames sont
converties par `CMSyncConvertTime` **échantillon par échantillon**, les marques et l'audio par
`CMClockMakeHostTimeFromSystemUnits`, toujours avec validation.

## Options envisagées

### Option A — `Date` / temps mural comme référentiel
- **Pour** : sérialisable tel quel, lisible par un humain dans le journal.
- **Contre** : non monotone (recalage NTP, changement d'heure), et aucun des trois producteurs ne
  le fournit — il faudrait dater chaque événement à sa réception, donc remplacer l'instant de
  l'événement par celui où on a fini de le traiter.

### Option B — `mach_absolute_time()` brut, conversion manuelle par timebase
- **Pour** : base native de `CGEvent.timestamp` et de `AVAudioTime.hostTime` ; monotone.
- **Contre** : aucun pont vers `CMTime`. Le PTS vit sur une horloge média dont la relation à la
  timebase hôte n'est pas garantie constante ; il faudrait réécrire à la main ce que
  `CMSyncConvertTime` fait déjà, suivi de dérive compris.

### Option C — l'horloge de synchronisation du `SCStream` comme maîtresse
- **Pour** : c'est le producteur le plus volumineux ; zéro conversion sur le chemin chaud.
- **Contre** : `synchronizationClock` vaut `nil` avant `startCapture()`, donc aucune marque de la
  phase `arming` n'est datable ; l'horloge meurt à l'arrêt du flux, et il y en a une **par flux**,
  donc une par écran, renouvelée à chaque redémarrage après un `-3821`. L'origine de la session
  changerait en cours de session.

### Option D — horloge hôte, mais offset scalaire mesuré une fois au démarrage du flux
- **Pour** : une soustraction d'entier par frame ; c'est l'esquisse initiale.
- **Contre** : l'offset suppose deux horloges avançant au même rythme pour toujours. Une dérive de
  quelques millisecondes par minute reste indétectable en début de session et fausse l'ancrage à la
  fin, alors que `CMSyncConvertTime` par échantillon coûte quelques nanosecondes.

## Justification

Deux propriétés départagent, et une seule horloge les réunit. **Elle existe indépendamment de la
capture** : disponible avant tout `SCStream`, elle survit à son arrêt, à sa recréation et à la
coexistence de plusieurs flux — ce qui condamne l'option C, la plus séduisante sur le papier.
**Elle partage sa base avec deux des trois producteurs** : `CGEvent.timestamp` et
`AVAudioTime.hostTime` sont déjà des ticks hôte, donc marques et parole ne coûtent qu'une
conversion et une soustraction. Le troisième passe par `CMSyncConvertTime`, l'API prévue pour cela.

Quatre corrections découlent de ce choix et n'ont rien d'optionnel.

1. **Conversion par échantillon, jamais offset figé** — option D écartée ci-dessus.
2. **`synchronizationClock` nul pendant `arming`.** Une marque posée avant `startCapture()` est
   étiquetée `preRoll` et forcée sur la source RAM, sans seek. Elle n'est jamais horodatée sur un
   offset inventé en attendant que le flux démarre.
3. **`CGEvent.timestamp` peut valoir 0.** Les événements synthétiques — Karabiner,
   BetterTouchTool, pilotes Logitech et Razer, Universal Control, partage d'écran — arrivent avec
   un timestamp nul ou hors plage. D'où la validation obligatoire dans `fromHost` : le tick doit
   tomber dans `[t0, now + 50 ms]`, sinon repli sur `now()` **avec trace**. Sans elle, l'invariant
   de monotonie rejette silencieusement les marques de tout utilisateur de ces outils, sur sa
   machine et pas sur celle du développeur. C'est l'objet du critère C12 du lot 0.
4. **La veille arrête `mach_absolute_time`.** Les trois producteurs restent cohérents entre eux,
   mais `SessionTime` cesse d'être une durée murale. Les `Interruption` sont donc datées **aussi**
   sur `mach_continuous_time`, uniquement pour que le rapport annonce « veille de 30 s ».

Une correction hors horloge consomme le même budget : la **latence d'entrée audio**.
`AVAudioTime.hostTime` date la remise du buffer, pas l'instant où le son a atteint le micro. Micro
interne : 10 à 30 ms, négligeable. AirPods : 150 à 300 ms, soit tout le budget d'erreur d'ancrage.
Elle est mesurée à l'ouverture de session et à chaque `AVAudioEngineConfigurationChange`
(`presentationLatency + kAudioDevicePropertyLatency + kAudioDevicePropertySafetyOffset`),
soustraite dans `bufferStartTime` et affichée dans le doctor ; si `when.isHostTimeValid` est faux —
fréquent sur périphérique agrégé — repli sur un compteur d'échantillons.

## Conséquences

- **Positives** : un seul référentiel, donc un seul endroit où se tromper ; les invariants de
  monotonie du journal ([ADR-0014](0014-journal-append-only.md)) portent sur une grandeur
  comparable ; la latence audio devient un paramètre mesuré et affiché, pas une constante devinée.
- **Négatives** — le prix à payer, assumé : `SessionTime` n'est pas une durée murale, ce qui impose
  un second horodatage des interruptions et interdit de dériver la durée d'une session de sa
  timeline. La validation de `fromHost` transforme certains horodatages matériels en `now()`, avec
  une imprécision de quelques millisecondes visible seulement dans la trace. La latence des
  périphériques agrégés reste couverte par un repli moins précis, et toute nouvelle source
  d'événement devra prouver qu'elle produit un tick hôte avant d'être intégrée.
- **Ce que ça ferme** : plus aucun `Date` dans le modèle, y compris là où ce serait pratique. La
  corrélation avec un log applicatif ou une trace serveur datés en temps mural exigera une table de
  correspondance explicite, pas une soustraction.

## Signal de révision

Le doctor journalise le taux de repli de `fromHost` sur `now()` : au-delà de 1 % des marques en
usage normal, la base hôte n'est plus fiable pour les événements matériels et il faudra horodater à
la réception dans le callback du tap. Second signal : une version de macOS faisant dériver
`CMClockGetHostTimeClock` de `mach_continuous_time` supprimerait la correction n°4.

## Références

- Spécification § 3.1 (les trois horloges), § 3.6 (latence d'entrée audio), § 11.2 critère C12.
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0004](0004-preroll-opt-in.md), [ADR-0005](0005-cgeventtap-arbitre-unique.md),
  [ADR-0008](0008-temps-asset-distinct-du-temps-session.md),
  [ADR-0011](0011-micro-par-fenetre-de-parole.md),
  [ADR-0014](0014-journal-append-only.md).
