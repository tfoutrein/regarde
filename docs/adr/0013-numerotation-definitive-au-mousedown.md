---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 2
---

# ADR-0013 — Le numéro d'une marque est attribué au `mouseDown` et n'est jamais renuméroté

## Contexte

Chaque marque porte un numéro visible : gravé en badge sur l'image exportée, titre de section
dans le rapport, cité par le chaînage de sessions (« Marques 1 et 4 corrigées, marque 3 toujours
en échec »), et cible du raccourci de réaffectation `⌥⌘ + chiffre` pendant qu'une fenêtre de
parole est ouverte.

Deux faits cadrent la décision. D'une part, l'utilisateur **prononce** ces numéros : le micro
est ouvert par fenêtre de parole liée au geste ([ADR-0011](0011-micro-par-fenetre-de-parole.md)),
et une phrase comme « le même problème que sur la marque 2 » est un usage attendu, pas un cas
limite. D'autre part, la revue permet de supprimer une marque après coup, et la conception
initiale renumérotait alors les suivantes pour garder une suite compacte.

Restent deux points liés à trancher : à quel instant le numéro est attribué, et ce qu'il devient
quand la marque disparaît.

## Décision

Le numéro est attribué au `mouseDown` du tracé, il est définitif, et une suppression laisse un
trou dans la suite. Le rapport écrit « marque 2 (supprimée) » lorsqu'un texte conservé y fait
référence. Seule exception : un tracé avorté par `Échap` libère son numéro, qui est réattribué
à la marque suivante.

## Options envisagées

### Option A — Numéro au `mouseUp`, renumérotation compacte après suppression (conception initiale)
- **Pour** : le rapport ne présente jamais de trou ; la lecture est immédiate pour l'agent.
- **Contre** : contredit la parole déjà enregistrée. Après suppression de la marque 1, la
  marque 2 devient la 1, et la phrase transcrite « comme sur la marque 2 » désigne alors autre
  chose. Casse aussi le chaînage : un rapport #43 cite les numéros de #42, qui ne sont donc pas
  un index interne mais une référence externe déjà publiée.

### Option B — Numéro au `mouseUp`, définitif
- **Pour** : identique à la décision retenue du point de vue du rapport.
- **Contre** : le numéro n'existe pas pendant le tracé, alors que la fenêtre de parole s'ouvre
  à la pression de `⌥⌘`, avant le `mouseUp`. Un segment de parole dont le premier mot tombe
  pendant le tracé n'aurait aucune marque à laquelle se rattacher, et le badge de réaffectation
  `⌥⌘ + chiffre` n'aurait rien à illuminer.

### Option C — Renumérotation, avec réécriture automatique des mentions dans la transcription
- **Pour** : conserve la suite compacte sans mentir sur le contenu.
- **Contre** : suppose de détecter de façon fiable les références numériques dans du français
  parlé — « la deux », « deux », « la marque d'avant », « celle du panier ». Un faux positif ne
  produit pas un rapport incomplet mais un rapport **faux**, et l'erreur est indétectable à la
  relecture puisque le texte reste grammatical.

### Option D — Pas de numéros : identifiants opaques, désignation par couleur ou par position
- **Pour** : supprime le problème à la racine.
- **Contre** : l'utilisateur ne peut plus désigner une marque à voix haute en testant, ce qui est
  précisément le geste que l'outil existe pour capter.

## Justification

La parole tranche. Un numéro prononcé est figé au moment où il est prononcé : le système peut
réordonner sa propre table, il ne peut pas réécrire ce que l'utilisateur a dit. Toute
renumérotation crée donc un rapport dont le texte et les images se contredisent, et le mode
d'échec est silencieux — un agent qui lit « comme sur la marque 2 » applique la correction à la
mauvaise zone sans que rien ne signale l'incohérence. Un trou dans la numérotation, à l'inverse,
est visible et se documente en une phrase.

Le `mouseDown` plutôt que le `mouseUp` se justifie deux fois. Il donne au numéro une existence
pendant le geste, où la fenêtre de parole et la réaffectation en ont besoin. Et il désigne le bon
instant pour la frame : l'appariement marque ↔ frame se fait sur la file d'encodage en retenant
la frame dont le PTS est le plus proche **par valeur inférieure**, et l'anneau de 4 frames existe
justement pour permettre de choisir la frame *précédant* le `mouseDown`. La sémantique voulue est
l'écran tel qu'il était quand l'utilisateur a décidé de désigner, pas tel qu'il est devenu à la
fin d'un tracé qui dure une à deux secondes — sur une page animée capturée à 15 fps, l'écart
représente quinze à trente frames.

`Échap` libère le numéro parce que, dans ce seul cas, l'utilisateur n'a pas encore eu le temps de
le prononcer : le tracé est annulé pendant qu'il est en cours.

## Conséquences

- **Positives** : ce qui est dit et ce qui est montré désignent la même chose, en session comme
  après chaînage. La cible de `⌥⌘ + chiffre` existe dès le premier pixel du tracé. La frame
  retenue correspond à l'intention de désignation.
- **Négatives — le prix à payer, assumé** : les rapports comportent des trous, qu'il faut
  expliquer à l'agent — c'est le rôle de la ligne « les numéros peuvent comporter des trous » de
  la section « Comment lire ce rapport ». Une marque supprimée n'est pas effacée du manifeste
  mais portée par `isDeleted`, ce qui laisse un objet mort dans le modèle et une mention
  « (supprimée) » dans le rendu. Enfin, l'exception `Échap` reste imparfaite : si l'utilisateur a
  déjà prononcé « marque 3 » avant d'annuler, la réattribution du 3 crée une ambiguïté que rien
  ne détecte.
- **Ce que ça ferme** : tout réordonnancement des marques par gravité ou par thème, la fusion de
  deux marques en une, et l'export « propre » à numérotation continue. L'ordre est chronologique
  et les numéros le figent.

## Signal de révision

La décision repose entièrement sur l'hypothèse que l'utilisateur prononce les numéros. Elle doit
être rouverte si, sur un corpus d'une vingtaine de sessions réelles, les transcriptions ne
contiennent aucune référence croisée à un numéro de marque : la contrainte disparaîtrait et la
renumérotation compacte redeviendrait le meilleur choix pour la lisibilité du rapport.

## Références

- Spécification § 3.4 (`Mark.number`, `isDeleted`), § 3.5 (dernier paragraphe), § 5.3
  (appariement et anneau de 4 frames), § 9.4 et § 9.9.
- [ADR-0011](0011-micro-par-fenetre-de-parole.md) — la fenêtre de parole ouverte avec le geste.
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md) — l'anneau applicatif de
  4 frames et son rôle dans l'appariement.
- [ADR-0014](0014-journal-append-only.md) — l'attribution du numéro est un événement du journal.
