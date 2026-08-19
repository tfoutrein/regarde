---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 3
---

# ADR-0004 — Maintenir un pré-roll permanent en mode économe, activé par consentement explicite

## Contexte

Le parcours réel d'un bug transitoire est : l'anomalie survient → l'utilisateur appuie sur le raccourci
→ l'état `arming` dure **0,3 à 1,5 s** le temps que `SCStream` livre sa première frame `.complete`
→ le bug est déjà passé. Sur un état non déterministe — une requête qui répond 500 une fois sur dix,
un flash de layout au montage, un toast de deux secondes — il ne sera pas reproduit à la demande.
C'est le cas d'usage numéro un d'un outil de feedback visuel, et sans pré-roll il est structurellement
hors de portée.

ScreenCaptureKit n'offre aucune reprise rétroactive : on ne peut pas demander « les vingt dernières
secondes ». La seule façon d'avoir le passé est de filmer avant d'en avoir besoin. Filmer, ici, veut
dire allumer l'indicateur système de capture d'écran — un objet visible en permanence dans la barre
de menus de macOS, que l'application ne peut ni masquer ni suspendre.

L'encodage continu sur disque est déjà acquis ([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)) :
le pré-roll ne crée pas ce mécanisme, il l'étend au temps qui précède la session. Le **défaut
d'activation** — proposé à l'onboarding ou coché d'office — reste l'arbitrage **A1** de la
spécification (§ 13), non tranché ici ; la recommandation par défaut y est l'opt-in.

## Décision

Regarde maintient un pré-roll permanent en mode économe : demi-résolution, 2 fps, trois segments
roulants de 10 s, les plus anciens supprimés. Il n'est **jamais actif sans un consentement explicite**
de l'utilisateur, donné à l'onboarding et révocable dans les réglages. Au raccourci d'ouverture, le
flux bascule en pleine résolution dans un nouveau `CaptureSegment` et les segments de pré-roll
deviennent les premiers segments de la session.

## Options envisagées

### Option A — Pas de pré-roll : la session commence quand on appuie
- **Pour** : aucun indicateur système hors session, aucune écriture disque au repos, aucune question
  de confiance à poser à l'utilisateur, un chemin de code en moins.
- **Contre** : les 0,3 à 1,5 s d'`arming` sont perdues sans recours, et avec elles la classe entière
  des observations « ça vient de se produire ». L'utilisateur apprend à ne plus signaler ce type de
  bug avec l'outil, ce qui le ramène à la capture d'écran manuelle qu'il devait remplacer.

### Option B — Pré-roll à pleine résolution et pleine cadence
- **Pour** : les marques rétroactives sortiraient des images de qualité identique aux marques normales,
  sans mention particulière dans le manifeste.
- **Contre** : 46,7 MiB/min d'écriture disque **en continu, hors session**, contre 15,4 MiB/min ;
  l'encodeur matériel et la bande passante mémoire sollicités toute la journée sur la machine même
  dont on veut mesurer la lenteur. Un outil de diagnostic qui devient un bruit de fond permanent
  n'est plus crédible.

### Option C — Pré-roll déclenché par heuristique (application cible au premier plan, activité clavier)
- **Pour** : filmer seulement quand c'est plausiblement utile ; coût moyen plus bas.
- **Contre** : l'indicateur système s'allume et s'éteint à des moments que l'utilisateur ne prédit pas
  et ne peut pas expliquer. Un indicateur de capture imprévisible est pire qu'un indicateur permanent :
  le premier inquiète, le second se comprend. Et l'heuristique rate justement les cas où l'anomalie
  précède le retour au premier plan.

### Option D — Pré-roll permanent en mode économe, opt-in (retenue)
- **Pour** : coût mesuré à **0,4 % d'un cœur**, 2,05 Mb/s soit **15,4 MiB/min**, et environ 8 MiB de
  disque occupés en régime établi (3 segments de 10 s). Demi-résolution, 1728×1117 sur l'écran de
  référence, à 2 fps : suffisant pour montrer qu'un badge d'erreur était là.
- **Contre** : l'indicateur système reste allumé tant que le mode est actif, et rien ne permet de
  le nuancer.

## Justification

Le coût machine du mode économe est négligeable au regard du gain fonctionnel : 0,4 % d'un cœur et
15,4 MiB/min achètent la seule chose que l'application ne peut pas reconstituer après coup, le passé.
Ce qui interdit l'activation d'office, ce n'est donc pas la dépense, c'est l'indicateur : un logiciel
qui se met à filmer l'écran en continu sans que l'utilisateur l'ait demandé consomme d'un coup tout le
crédit de confiance dont dépend un outil qui voit tout. Le consentement explicite est le prix d'entrée,
pas une précaution ornementale.

**Segments roulants plutôt que fichier unique tronqué** : `AVAssetWriter` ne sait pas supprimer des
échantillons par l'avant. Un writer ouvert écrit du début vers la fin, sans mécanisme d'oubli. Garder
« les vingt dernières secondes » dans un seul fichier supposerait de le réécrire en permanence. La
rotation par segments de 10 s, avec suppression des plus anciens, obtient l'oubli borné avec les
primitives disponibles.

**Marque rétroactive** : ⌥⌘ + `1`..`9` pose une marque datée à T−N secondes. La frame est **toujours
extraite du fichier encodé** — segment de session si T−N est postérieur à l'ouverture, segment de
pré-roll sinon, à résolution réduite, ce que le manifeste signale pour que l'agent ne prenne pas un
flou de rééchantillonnage pour un défaut d'affichage. L'anneau de 4 frames ne couvre que **0,27 s à
15 fps** : il sert à l'appariement du `mouseDown`, jamais aux marques rétroactives. Le dimensionner
pour couvrir quelques secondes demanderait une soixantaine de frames, soit 1,77 GiB à pleine
résolution — exclu par l'arithmétique même qui a écarté le ring buffer RAM
([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)). Le seek coûte 31 ms avec le
GOP forcé à 1 s. Un filet indépendant complète le dispositif : au tout premier instant du raccourci, avant
`arming`, un `SCScreenshotManager.captureImage` synchrone garantit qu'une image existe quoi qu'il
arrive ensuite — y compris pré-roll désactivé.

## Conséquences

- **Positives** : l'observation « le bug vient de passer » devient traitable ; la bascule vers la pleine
  résolution ne coûte pas d'`arming` visible, le flux tournant déjà ; l'icône de la barre de menus porte
  un état réel à trois valeurs (gris inactif, bleu pré-roll, rouge session).
- **Négatives** — le prix à payer, assumé :
  - **L'indicateur système de capture d'écran reste allumé en permanence**, sans possibilité de le
    désactiver. Un utilisateur en visioconférence ou en démonstration l'expose à son auditoire.
  - Écriture disque continue hors session, donc un fichier de tout l'écran existe même quand aucune
    session n'est ouverte : le dispositif de [ADR-0020](0020-confidentialite-capture-continue.md)
    (liste noire d'applications, `$TMPDIR`, purge) doit couvrir le repos, pas seulement la session.
  - Les images rétroactives antérieures à l'ouverture de session sont à résolution réduite, différence
    que l'utilisateur découvre dans le rapport et non au moment du geste.
  - Rotation, suppression et jonction des segments de pré-roll avec ceux de la session ajoutent un
    chemin de code à tester, notamment la continuité des temps entre deux segments de résolutions
    différentes ([ADR-0008](0008-temps-asset-distinct-du-temps-session.md)).
- **Ce que ça ferme** : la promesse « Regarde ne filme que quand vous le lui demandez », qui ne peut
  plus être tenue dès que le mode est activé — l'onboarding doit le dire dans ces termes.

## Signal de révision

Une proportion notable d'utilisateurs qui activent le pré-roll à l'onboarding puis le désactivent dans
la semaine, avec l'indicateur permanent cité en motif : le mode économe ne serait alors pas assez
économe socialement, et il faudrait rouvrir l'option C ou une fenêtre d'activation liée à une session
de recette déclarée. Signal symétrique côté plateforme : si macOS venait à distinguer visuellement une
capture à cadence réduite d'un enregistrement plein, l'arbitrage A1 basculerait vers l'activation
par défaut.

## Références

- Spécification § 5.1, § 10.6, § 13 arbitrage A1 ; lot 3 (pré-roll opt-in, segments roulants) et
  lot 8 (onboarding séquencé).
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0020](0020-confidentialite-capture-continue.md),
  [ADR-0008](0008-temps-asset-distinct-du-temps-session.md).
