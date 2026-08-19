---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 0
---

# ADR-0010 — Le calque d'annotation n'est ordonné à l'écran que pendant le tracé

## Contexte

La promesse du produit est que l'application testée **continue de tourner normalement** pendant qu'on
l'annote. Une des six intentions de la palette est `lenteur` : l'outil sert explicitement à signaler
des problèmes de fluidité. Or le calque est une `NSPanel` transparente couvrant tout l'écran, au
niveau `.screenSaver`. Tant qu'une telle couche est ordonnée à l'écran, le WindowServer ne peut plus
accorder à l'application testée ses chemins de composition optimisés : elle passe par une passe de
composition supplémentaire, en permanence.

C'est le risque R8. Sa gravité ne tient pas à l'ampleur de la dégradation mais à sa nature :
**l'outil censé diagnostiquer une lenteur en devient la cause**, le développeur mesure un symptôme
qu'il a lui-même introduit, et optimise un faux problème. Aucun message d'erreur, aucune trace ; on
ne le voit qu'en mesurant.

L'arbitrage souris est déjà tranché par [ADR-0005](0005-cgeventtap-arbitre-unique.md) : le tap décide
seul, la fenêtre n'est jamais dans le chemin de décision. Cet ADR ne traite que de la visibilité.

## Décision

Les panneaux existent en permanence — **une `NSPanel` par `NSScreen`**, configurées à l'initialisation
— mais ne sont ordonnées à l'écran qu'à la pression du modificateur et retirées à la fermeture de la
fenêtre de parole. Hors de ces intervalles, aucune couche de composition ne s'intercale entre
l'application testée et le WindowServer.

## Options envisagées

### Option A — Une fenêtre transparente plein écran ordonnée pendant toute la session
- **Pour** : aucune latence d'apparition, aucune machine à états ; les badges des marques déjà posées
  restent visibles, ce qui aide l'utilisateur à prononcer « comme sur la marque 2 ».
- **Contre** : R8 sur toute la durée de la session, y compris les minutes où l'utilisateur ne fait
  qu'observer. La dégradation est invisible sans instrumentation, donc jamais attribuée à l'outil.

### Option B — Une seule fenêtre couvrant l'union des écrans
- **Pour** : un seul objet, une seule couche de rendu, pas de synchronisation inter-écrans.
- **Contre** : `backingScaleFactor` est une propriété **de fenêtre** ; sur un Retina et un externe
  non-Retina, l'un des deux tracés est faux d'un facteur 2. L'union de deux écrans en disposition L
  n'est pas un rectangle. Et les écrans changent d'échelle à chaud, ce qui invalide la fenêtre en
  cours de session.

### Option C — Dessiner dans une couche du WindowServer sans fenêtre (API privées `CGS`)
- **Pour** : la voie la plus légère du point de vue composition.
- **Contre** : API privées, incompatibles avec la notarisation visée par
  [ADR-0002](0002-hors-sandbox-developer-id.md) et avec la revalidation d'une journée par version
  majeure de macOS.

### Option D — Panneaux persistants, ordonnés à la demande (retenue)
- **Pour** : le coût de composition n'existe que pendant les quelques secondes du geste.
- **Contre** : un cycle `orderFrontRegardless` / `orderOut` par geste, et une machine à états de plus.

## Justification

Le seul argument sérieux pour l'option A est la latence : si la fenêtre arrive après le premier point,
le trait démarre à côté du curseur et le critère C5 tombe. Cet argument s'effondre à cause de
[ADR-0005](0005-cgeventtap-arbitre-unique.md) : quand le modificateur est pressé, le tap a **déjà**
décidé et bufferise les points dans le ring lock-free. La fenêtre arrive ensuite et le trait s'affiche
complet. L'ordre à l'écran n'est jamais sur le chemin critique de la décision, seulement sur celui de
l'affichage — c'est précisément ce que l'architecture « tap d'abord » achète.

Il reste alors à comparer un coût permanent et invisible (option A) à un coût transitoire et mesurable
(option D). Le premier attaque la crédibilité même du produit ; le second se borne à quelques secondes
par geste.

**Configuration des panneaux, et pourquoi chaque ligne est là.**

- `styleMask = [.borderless, .nonactivatingPanel]`, fixé à l'initialisation et **jamais muté** : muter
  le `styleMask` d'un panneau vivant reconstruit son backing store et fait disparaître les couches.
- `canBecomeKey = false` **en plus** de `.nonactivatingPanel`. Ce sont deux mécanismes distincts :
  `.nonactivatingPanel` empêche l'activation de l'application quand on clique dans le panneau ;
  `canBecomeKey` empêche le panneau de devenir fenêtre clé par les chemins qui ne passent pas par la
  souris — un `makeKeyAndOrderFront` hérité d'AppKit, un ordre à l'écran d'une fenêtre accessoire. Le
  premier seul laisse la porte ouverte au vol de focus, et le critère C4 (le caret continue de
  clignoter dans l'application testée) tombe.
- `hidesOnDeactivate = false` : `NSPanel` masque par défaut ses fenêtres quand l'application se
  désactive. Comme la politique est `.accessory` avec `LSUIElement = 1`, l'application n'est
  **jamais** active — laisser la valeur par défaut signifie que le calque ne s'affiche jamais. Le
  symptôme est un panneau parfaitement configuré et invisible, sans erreur.
- `ignoresMouseEvents = true` **en permanence**, jamais piloté par `flagsChanged`. C'est cosmétique et
  jamais décisionnel : la décision appartient au tap. Le basculer selon le modificateur réintroduit la
  course de R4 — un `mouseDown` dans l'intervalle de bascule part à l'application testée.
- `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary,
  .ignoresCycle, .transient]`, `orderFrontRegardless()` : critères C8 et C9.
- Aucun `NSVisualEffectView`, aucun flou, aucune ombre (`hasShadow = false`) : chaque effet est une
  passe de composition supplémentaire, sur le poste précis qu'on cherche à protéger.

## Conséquences

- **Positives** : hors tracé, la pile de composition de l'application testée est celle qu'elle aurait
  sans Regarde ; R8 est borné à la durée des gestes et devient mesurable ; le mode économe du lot 12
  se greffe sur une architecture déjà prévue pour retirer le calque.
- **Négatives** — le prix à payer, assumé : les badges des marques posées disparaissent entre deux
  gestes, alors que l'utilisateur les prononce à voix haute — le repère visuel qui rend naturel
  « comme sur la marque 2 » n'est présent que pendant les fenêtres de parole. La réaffectation
  `⌥⌘ + chiffre` n'illumine un badge que tant que la fenêtre de parole est ouverte, ce qui couple
  l'affichage au minuteur audio de [ADR-0011](0011-micro-par-fenetre-de-parole.md) sans nécessité
  conceptuelle. Enfin, chaque cycle d'ordre à l'écran est une occasion pour le WindowServer de
  recomposer : le coût permanent est remplacé par des dizaines de coûts transitoires, qu'il faut
  vérifier invisibles (C7, p95 < 33 ms).
- **Ce que ça ferme** : pas de HUD d'annotation persistant sur l'écran ; pas de survol ni de
  manipulation à la souris des marques déjà posées en cours de session — le panneau ne reçoit jamais
  la souris, toute correction passe par `Échap`, `⌘Z` ou la revue à la demande.

## Signal de révision

Le critère C3b du lot 0 : deltas de `requestAnimationFrame` sur une page WebGL plein écran, avec et
sans calque, seuil de 5 % de dégradation. Si, mesuré **calque ordonné en permanence**, l'écart reste
sous 5 % sur trois générations de matériel et deux versions majeures de macOS, l'ordonnancement à la
demande ne paie plus sa complexité et l'option A redevient défendable. Si à l'inverse C3b échoue
**même avec** l'ordonnancement à la demande, cette décision ne suffit pas : il faut le gel du rendu et
le mode économe explicite, avant d'aller plus loin dans les lots.

## Références

- Spécification § 4.1 (ligne « Ordonnancement du calque »), § 6.1, § 6.4, § 12 R8,
  § 11.2 critères C3b, C4, C5, C7, C8, C9.
- [ADR-0005](0005-cgeventtap-arbitre-unique.md), [ADR-0002](0002-hors-sandbox-developer-id.md),
  [ADR-0011](0011-micro-par-fenetre-de-parole.md),
  [ADR-0006](0006-modificateur-option-commande.md).
