---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 0
---

# ADR-0005 — Le `CGEventTap` est l'arbitre unique des événements souris

## Contexte

Le geste central du produit demande deux comportements opposés au même périphérique. Pendant qu'un
tracé est en cours, aucun événement souris ne doit atteindre l'application testée : un `mouseDown`
qui passe déclenche un bouton, démarre une sélection de texte ou un glisser de fichier, et l'état
de l'application observée est corrompu par l'outil censé l'observer (R4). Hors tracé, tout doit
passer intact, y compris le premier clic — le critère C5 du lot 0 exige que vingt tracés démarrent
exactement sous le curseur, sans perte du point de départ.

[ADR-0010](0010-calque-ordonne-pendant-le-trace-seulement.md) a déjà écarté la fenêtre transparente
permanente : le calque n'est ordonné à l'écran que pendant le tracé. Il n'existe donc, la plupart du
temps, aucune surface capable d'intercepter quoi que ce soit. La décision d'entrée doit être prise
ailleurs que dans la hiérarchie des vues.

## Décision

Un `CGEventTap` installé en `.headInsertEventTap` sur un thread dédié avec sa propre boucle
d'exécution arbitre chaque événement souris, individuellement, à partir de `event.flags` et de
`event.location`. `ignoresMouseEvents` reste à `true` en permanence sur les panneaux : c'est une
propriété cosmétique, jamais un mécanisme de décision.

## Options envisagées

### Option A — `ignoresMouseEvents` piloté par `flagsChanged`
- **Pour** : aucune permission TCC supplémentaire, quelques lignes d'AppKit, sémantique d'entrée
  standard traitée dans une `NSView`.
- **Contre** : course garantie. Entre l'instant où le modificateur est enfoncé et l'instant où le
  WindowServer a pris en compte le nouveau `ignoresMouseEvents`, tout `mouseDown` part à
  l'application testée. La fenêtre de course n'est pas bornée par contrat, et l'utilisateur qui
  presse le modificateur et clique dans la foulée tombe précisément dedans.

### Option B — Fenêtre transparente permanente qui reçoit les clics et les redistribue
- **Pour** : un seul chemin d'entrée, du code AppKit ordinaire, pas de callback C.
- **Contre** : la redistribution n'existe pas — on ne réinjecte pas proprement un événement vers
  l'application dessous. Le coût de composition permanent fait perdre à l'application testée les
  chemins optimisés du WindowServer (C3b : moins de 5 % de dégradation), et cette voie est celle
  qu'atteint la régression Apple FB21879057 (R10).

### Option C — `CGEventTap` arbitre, porte à verrou (retenue)
- **Pour** : la décision est prise sur l'événement lui-même, avec ses propres `flags` : il n'y a
  plus d'intervalle entre l'état observé et l'état appliqué. Insensible à R10, puisque
  l'architecture ne dépend pas du comportement des fenêtres transparentes.
- **Contre** : Input Monitoring **et** Accessibilité obligatoires, callback C sur thread dédié,
  budget de temps strict, tap désactivable par le système.

## Justification

C'est l'atomicité qui départage. L'option A décide sur un état (« le modificateur est-il tenu ? »)
que le système a mémorisé ailleurs et applique plus tard ; l'option C décide sur l'événement
qu'elle tient. La différence s'incarne dans la porte à verrou (§ 6.2) :

- `.leftMouseDown` est le **seul** point de décision d'entrée. `capture = armed && !mouseDownInApp`.
- `strokeActive` et `mouseDownInApp` sont exclusifs et écrits uniquement à cet instant : le drag
  appartient à l'outil ou à l'application testée, jamais aux deux, jamais à personne.
- `.leftMouseDragged` et `.mouseMoved` ne redécident rien, ils suivent l'état.
- `.leftMouseUp` ferme le verrou dans les deux sens. Le verrou tient jusque-là **même si le
  modificateur est relâché en plein tracé** : sans cela, relâcher ⌥⌘ à mi-parcours enverrait la
  suite du drag et le `mouseUp` à l'application testée, qui recevrait un glisser sans début —
  le drag fantôme dans le Finder que le critère C6 cherche précisément.

Le budget du callback est la contrepartie non négociable : zéro allocation, zéro appel AppKit,
zéro I/O, zéro verrou bloquant. Une souris haute fréquence émet entre 125 et 1000 Hz, et un
dépassement fait basculer le système en `kCGEventTapDisabledByTimeout` sans avertissement. Les
points partent dans un anneau sans verrou (`Ink.shared.push`) ; le tap ne touche jamais un
`CVPixelBuffer`, ce qui est aussi la parade au crash B2
([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)).

## Conséquences

- **Positives** : le premier point n'est jamais perdu ; l'application testée reçoit tout ou ne
  reçoit rien, sans état intermédiaire ; l'architecture survit à la régression macOS 26.3/26.4, le
  second chemin d'entrée du lot 7 restant une parade et non une dépendance.
- **Négatives** — le prix à payer, assumé :
  - Input Monitoring **et** Accessibilité deviennent obligatoires. Un tap `.defaultTap` qui
    *consomme* des événements exige l'Accessibilité en plus ; seule la lecture pure se contenterait
    d'Input Monitoring. Deux autorisations de plus sur le premier contact, dont deux qui demandent
    un redémarrage (R1).
  - Le tap peut être désactivé silencieusement par timeout, par entrée utilisateur ou par une
    re-signature du binaire. Symptôme : « ça marchait il y a dix minutes » (R9). Il faut un watchdog
    toutes les 5 s vérifiant `tapIsEnabled` **et** qu'un événement a été vu récemment — la seconde
    condition est celle qui compte, un tap peut se déclarer actif et ne plus rien recevoir.
  - Le cœur du produit vit dans un callback C sur un thread dédié : pas d'isolation d'acteur, état
    mutable tenu à la main, terrain chiffré à ×2,0–2,5 dans la spécification — ce qui porte le
    lot 0 à 2,5 j.
- **Ce que ça ferme** :
  - Tout mode dégradé sans tap. Sans Input Monitoring ni Accessibilité, **il n'y a pas de session**
    (§ 4.2) ; le doctor le dit et propose l'octroi, il ne propose pas de contourner.
  - Le Mac App Store, un tap consommateur d'événements ne passant pas la revue
    ([ADR-0002](0002-hors-sandbox-developer-id.md)).
  - Le filtrage par source d'événement : le critère C12 impose qu'une souris pilotée par Karabiner
    ou un pilote tiers fonctionne, donc on ne peut pas distinguer un événement synthétique.

## Signal de révision

Le watchdog recrée le tap plus d'une fois par session de dix minutes sur une machine au repos, ou
un test C1 montre qu'un événement destiné à l'application testée a été consommé hors tracé. Rouvrir
également si Apple publie une API permettant à une fenêtre de revendiquer les événements souris de
façon atomique et documentée — l'option A redeviendrait alors défendable.

## Références

- Spécification § 4.1 (« Arbitrage souris »), § 4.2, § 6.1, § 6.2, § 11.2 (C1, C2, C5, C6, C10,
  C12), § 12 (R4, R9, R10). Radar Apple FB21879057.
- [ADR-0002](0002-hors-sandbox-developer-id.md), [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0006](0006-modificateur-option-commande.md), [ADR-0010](0010-calque-ordonne-pendant-le-trace-seulement.md),
  [ADR-0013](0013-numerotation-definitive-au-mousedown.md).
