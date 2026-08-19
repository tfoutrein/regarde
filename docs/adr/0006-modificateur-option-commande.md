---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 2
---

# ADR-0006 — Le mode annotation s'arme par ⌥⌘ maintenu, configurable, sans double-appui

## Contexte

[ADR-0005](0005-cgeventtap-arbitre-unique.md) place la décision d'entrée dans le callback du tap,
sur `event.flags`. Reste à choisir quels drapeaux arment le mode. La contrainte est asymétrique :
un modificateur trop discret vole des gestes que le développeur fait cent fois par jour dans
l'application qu'il est justement en train de tester, tandis qu'un modificateur trop exotique
casse le geste fugace qui est la raison d'être du produit — main gauche sur le clavier, main droite
qui trace, sans changer de mode ni de fenêtre.

La conception initiale retenait ⌥ seul, complété par un double-appui sur Option pour basculer en
mode verrouillé. La critique a défait les deux.

## Décision

Le mode annotation s'arme par **⌥⌘ maintenu**, valeur par défaut configurable dans les réglages.
Le `mouseDown` n'est consommé que si son point tombe dans le cadre de la fenêtre cible ; `⌥⌘⇧`
force la capture hors cible. **Aucun mécanisme de double-appui n'existe** : le mode verrouillé
passe par un raccourci Carbon distinct (⌃⌥L) ou par un clic sur le HUD.

## Options envisagées

### Option A — ⌥ seul maintenu
- **Pour** : une seule touche, atteignable du pouce ou de l'auriculaire sans regarder, geste le
  plus fluide possible.
- **Contre** : ⌥-clic est un geste légitime et fréquent dans les applications que l'on teste —
  télécharger un lien dans Safari, révéler le chemin dans le Finder, dupliquer un calque dans
  Figma, poser un curseur supplémentaire ou ouvrir la définition dans un IDE. L'outil volerait
  ces gestes dans l'application observée, ce qui est exactement le mode de défaillance que
  [ADR-0005](0005-cgeventtap-arbitre-unique.md) cherche à éliminer.

### Option B — ⌥ seul, plus double-appui sur Option pour le mode verrouillé
- **Pour** : arme un mode persistant sans consommer de raccourci supplémentaire.
- **Contre** : structurellement incompatible avec le clavier AZERTY. Sur un clavier français,
  `{` `}` `[` `]` `|` `~` s'obtiennent avec Option : taper `{{` en JSX, `[[` dans un tableau ou
  `||` dans une condition arme le mode en pleine frappe. Le problème n'est pas réglable par une
  temporisation, puisque la frappe rapide de deux accolades est précisément ce qu'un détecteur de
  double-appui doit reconnaître.

### Option C — Armement par raccourci global, puis clics libres
- **Pour** : aucun conflit avec les gestes souris, `RegisterEventHotKey` ne demande aucune
  autorisation TCC.
- **Contre** : transforme un geste fugace en mode modal. Il faut armer, tracer, désarmer, et tout
  clic passé après une désactivation oubliée est volé sans que l'utilisateur comprenne pourquoi.
  Le mode verrouillé conserve cette voie, mais comme option, pas comme chemin nominal.

### Option D — ⌥⌘ maintenu, configurable, ancré à la fenêtre cible (retenue)
- **Pour** : ⌥⌘-clic n'est presque jamais un geste souris courant dans les navigateurs et les
  outils de conception ; l'ancrage à la fenêtre traite le cas résiduel.
- **Contre** : deux touches, et une combinaison qui reste utilisée dans certains IDE.

## Justification

⌥⌘ n'est pas choisi parce qu'il serait libre partout — il ne l'est pas, notamment dans les IDE —
mais parce qu'il est le seul candidat dont le résidu de conflits est **localisable**. Le conflit qui
subsiste est un ⌥⌘-clic sur du code, c'est-à-dire dans une fenêtre qui n'est pas la fenêtre testée.
D'où la seconde moitié de la décision : la porte n'arme que si `targetWindowRect.contains(e.location)`,
avec un rectangle issu de `SCWindow.frame` et réactualisé à chaque changement d'application au
premier plan. Ailleurs, l'événement passe sans être touché. `⌥⌘⇧` sert le cas inverse, rare mais
réel : annoter quelque chose qui déborde de la fenêtre testée, une notification par exemple.

Le rejet du double-appui n'est pas un arbitrage de confort. Un mécanisme qu'on ne peut pas rendre
fiable sur le clavier de l'auteur n'a pas de version acceptable ; il est supprimé, pas atténué.

Le badge « armé » suit la même logique de non-déclenchement parasite. ⌥← ⌥→ ⌥⌫ sont des raccourcis
d'édition courants, et un badge qui clignote à chaque mot effacé rend l'indicateur illisible. Il ne
s'allume donc que si le modificateur est tenu depuis **120 ms**, que le curseur est dans la fenêtre
cible, et qu'aucun `keyDown` n'est survenu depuis la pression. Les 120 ms sont une temporisation
d'affichage seulement : la porte, elle, arme dès le premier événement, sans quoi on réintroduirait
la course que [ADR-0005](0005-cgeventtap-arbitre-unique.md) élimine.

## Conséquences

- **Positives** : les gestes ⌥-clic de l'application testée restent intacts ; le développeur peut
  travailler dans son IDE avec l'outil actif sans produire de marques parasites ; le modificateur
  étant configurable, un conflit découvert dans une application précise se règle sans livraison.
- **Négatives** — le prix à payer, assumé :
  - Deux touches au lieu d'une. Le geste est mesurablement moins fluide d'une seule main, et c'est
    une friction payée à chaque marque, donc plusieurs fois par session.
  - La démonstration repose sur la disposition AZERTY de l'auteur. Sur un clavier QWERTY, où les
    accolades et les crochets ne passent pas par Option, l'argument qui tue l'option B tombe : la
    décision devra être revalidée, pas reconduite par habitude.
  - Le tap doit écouter `keyDown` dès le lot 0 — pour `Échap`, `⌘Z` et la condition du badge. On
    élargit donc la surface d'écoute clavier d'un outil qui tourne en permanence, ce qui alourdit
    les obligations de confidentialité ([ADR-0020](0020-confidentialite-capture-continue.md)) et
    impose de fermer d'office la fenêtre de parole quand `IsSecureEventInputEnabled()` passe à vrai.
  - `targetWindowRect` devient un état à maintenir juste. Un rectangle périmé refuse une marque
    légitime ou en consomme une hors cible, et le symptôme sera attribué au tap, pas à la fenêtre.
- **Ce que ça ferme** : tout armement par répétition de touche, y compris les variantes plus
  élaborées (triple-appui, appui long sur Option). La voie est fermée pour la disposition AZERTY,
  et l'outil n'aura pas deux mécanismes d'armement selon le clavier.

## Signal de révision

Passage durable de l'auteur à un clavier QWERTY : l'option B redevient examinable. Ou, dans
l'usage, le recours à `⌥⌘⇧` devient plus fréquent que le geste nominal — signe que l'ancrage à la
fenêtre cible désigne la mauvaise fenêtre et que c'est lui, non le modificateur, qu'il faut
reprendre. Ou encore : une marque parasite apparaît de façon répétée dans une application donnée
alors que le modificateur configuré est censé y être libre.

## Références

- Spécification § 4.1 (ligne « Modificateur »), § 6.3, § 11.2 (C2), § 11.3 (lot 2), § 12 (R13).
- [ADR-0005](0005-cgeventtap-arbitre-unique.md), [ADR-0010](0010-calque-ordonne-pendant-le-trace-seulement.md),
  [ADR-0013](0013-numerotation-definitive-au-mousedown.md), [ADR-0020](0020-confidentialite-capture-continue.md).
