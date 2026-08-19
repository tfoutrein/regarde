---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 2
---

# ADR-0021 — `⌥⌘ + chiffre` est désambiguïsé par la présence d'une marque attachée

## Contexte

Trois fonctions du produit revendiquent le même accord `⌥⌘ + chiffre`, et elles sont arrivées dans
la conception par des chemins indépendants :

| Fonction | Origine | Fréquence attendue |
|---|---|---|
| Marque rétroactive à T−N secondes | pré-roll, spécification § 5.1 | occasionnelle |
| Palette d'intentions `1`..`6` | mode silencieux, spécification § 7.4 | très fréquente |
| Réaffectation du segment de parole à la marque N | correction du rattachement, spécification § 3.5 | rare |

Le conflit n'a été relevé qu'à la relecture de cohérence, et il est total : une fenêtre de parole
s'ouvre **dès la pression de ⌥⌘** ([ADR-0011](0011-micro-par-fenetre-de-parole.md)), donc le
contexte « une fenêtre de parole est ouverte » est vrai dans les trois cas et ne discrimine rien.
Ni la spécification ni les autres ADR ne donnaient de règle.

La contrainte de fond est la main : le geste se fait d'une seule main, gauche, pendant que la
droite tient la souris et que l'application testée continue de s'animer. Chaque touche
supplémentaire à maintenir se paie en précision de tracé.

## Décision

Le discriminant est **la présence d'une marque attachée à la fenêtre de parole courante**, évaluée
à l'instant de la frappe du chiffre.

| État de la fenêtre de parole courante | `1`..`9` | `⇧` + `1`..`9` |
|---|---|---|
| Ouverte, aucune marque attachée | marque rétroactive à T−N secondes | — |
| Ouverte, une marque attachée | intention `1`..`6` sur cette marque ; `7`..`9` sans effet | réaffectation du segment en cours à la marque N |
| Fermée | aucun effet | aucun effet |

Le HUD affiche le sens actif du chiffre — « T−N » ou « intention » — tant que ⌥⌘ est tenu.

## Options envisagées

### Option A — Discrimination par la marque attachée (retenue)

- **Pour** : les deux fonctions courantes n'exigent aucun accord supplémentaire ; la séquence
  s'enchaîne (`⌥⌘` `3` `2` = rétroactive à T−3 s puis intention « erreur ») ; `⇧` est réservé au
  seul cas de correction.
- **Contre** : le même chiffre produit deux effets différents, ce qui est une règle à connaître —
  atténué mais pas supprimé par l'affichage du sens actif dans le HUD.

### Option B — Trois accords distincts (`⌥⌘`, `⌥⌘⇧`, `⌥⌘⌃` + chiffre)

- **Pour** : aucune ambiguïté possible, aucune règle contextuelle à comprendre, chaque fonction
  reste accessible dans n'importe quel état.
- **Contre** : trois touches maintenues plus un chiffre, d'une seule main, pendant un tracé qui
  demande de la précision. `⌥⌘⌃` est un accord difficile à tenir sans déformer le trait. Et
  l'accord le plus simple irait à la fonction la plus fréquente, ce qui laisserait les deux autres
  sur des combinaisons pénibles pour un bénéfice théorique.

### Option C — Chiffres pour les marques, lettres pour les intentions

- **Pour** : une famille de touches par concept, et des lettres mnémoniques plus lisibles à l'oral
  et dans le rapport.
- **Contre** : six lettres à mémoriser au lieu d'une plage de chiffres contiguë, et surtout un
  risque de collision réel — `⌥⌘ + lettre` est un raccourci courant dans les applications testées,
  alors que `⌥⌘ + chiffre` y est presque toujours libre. Le tap consommerait des accords que
  l'application attend.

### Option D — Repousser la palette d'intentions après le lot 4

- **Pour** : supprime le conflit sans règle, et allège le lot 2.
- **Contre** : le périmètre engagé s'arrête au lot 4, donc sans voix. Sans intentions non plus, une
  marque ne porterait **aucun mot** : le GO/NO-GO n°2 se jouerait sur un produit réduit à des
  flèches numérotées, ce qui ne teste pas la promesse.

## Justification

Ce qui a départagé est le coût par usage, pondéré par la fréquence. Les intentions sont frappées
à presque chaque marque, la rétroactive quelques fois par session, la réaffectation quelques fois
par semaine. Faire payer un accord à trois touches aux deux premières pour épargner une règle à la
troisième inverse le rapport.

La règle retenue tient parce que les deux sens ne se disputent jamais le même instant. Avant le
tracé, il n'existe aucune marque à qualifier : une intention n'aurait pas de cible, le chiffre ne
peut donc désigner qu'un instant passé. Après le tracé, la marque existe et attend d'être
qualifiée : le chiffre ne peut plus désigner un instant, puisque l'utilisateur vient précisément de
désigner celui qui l'intéresse. L'ambiguïté est apparente, pas réelle — c'est ce qui rend la règle
apprenable en une session plutôt que mémorisable.

La contrepartie assumée est qu'on ne peut pas poser deux marques rétroactives consécutives sans
relâcher ⌥⌘, puisque la première s'attache à la fenêtre et bascule le sens du chiffre suivant.
Deux rétroactives d'affilée décrivent un cas marginal — deux événements transitoires distincts
dans la même seconde — et le geste supplémentaire coûte moins qu'un mode explicite.

## Conséquences

- **Positives** : aucun accord nouveau pour les deux gestes courants ; l'enchaînement
  `⌥⌘` `N` `intention` pose et qualifie une marque rétroactive sans relâcher ; `⇧` reste libre et
  identifie sans ambiguïté le geste de correction.
- **Négatives — le prix à payer, assumé** : une règle contextuelle existe et devra être apprise,
  ce qui impose au HUD d'afficher le sens actif du chiffre — un affichage supplémentaire à
  implémenter et à maintenir lisible pendant un tracé. Les chiffres `7`..`9` deviennent muets
  lorsqu'une marque est attachée, asymétrie qui demande un retour visuel d'invalidité sous peine
  de passer pour un bug. Enfin, la palette est plafonnée à six intentions : en ajouter une septième
  demanderait de rouvrir cette décision.
- **Ce que ça ferme** : l'ajout futur d'une quatrième fonction sur `⌥⌘ + chiffre`. La plage est
  saturée ; toute nouvelle fonction devra prendre un autre accord.

## Signal de révision

Deux observations mesurables sur des sessions réelles. Des marques rétroactives suivies d'une
suppression immédiate, signe que le chiffre a été interprété comme une intention alors que
l'utilisateur visait un instant. Ou l'inverse : des intentions absentes sur des marques où le
rapport montre que l'utilisateur en attendait une. Un taux non marginal de l'un ou l'autre
justifierait de basculer sur l'option B pour la seule fonction concernée.

## Références

- Spécification § 6.7 (règle complète), § 5.1 (marque rétroactive), § 7.4 (palette d'intentions),
  § 3.5 (réaffectation du segment de parole).
- [ADR-0006](0006-modificateur-option-commande.md) — le modificateur ⌥⌘ et son ancrage à la fenêtre cible.
- [ADR-0011](0011-micro-par-fenetre-de-parole.md) — la fenêtre de parole, dont dépend le discriminant.
- [ADR-0013](0013-numerotation-definitive-au-mousedown.md) — la numérotation que les chiffres désignent.
