# Protocole de test — lot 0

```bash
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/prototypes/lot0
./Tools/start.sh
```

Une seule commande : auto-test de la porte, construction signée, lancement de
l'application et du témoin, puis état réel. `--quick` saute la reconstruction.

À tout moment, sans rien interrompre :

```bash
./Tools/status.sh
```

---

## Ce que le prototype sait faire

Tout tient en quatre gestes. Le reste — numérotation, voix, rapport, MCP — appartient
aux lots suivants et n'existe pas ici.

| Geste | Effet |
|---|---|
| **⌥⌘ + glisser** | trace un trait rouge par-dessus l'application testée |
| **relâcher** | la souris revient immédiatement à l'application |
| **`Échap`** *(pendant le tracé)* | annule le trait en cours |
| **clic droit** *(pendant le tracé)* | annule le trait en cours — même effet, sans lâcher la souris |
| **⌥⌘Z** | supprime le dernier trait posé |

Et un menu **◎** dans la barre de menus, dont l'icône porte l'état réel :

| Icône | Sens |
|---|---|
| **◎** gris | au repos, tap actif — l'état normal |
| **◍** bleu | calque à l'écran, tracé en cours |
| **◉** rouge | **tap mort** — rien ne fonctionnera |

Le menu donne aussi : ligne de santé du tap, latence, rapport de permissions,
disposition des écrans, épinglage du calque, effacement, banc C11, export JSON.

---

## Les critères, dans l'ordre

Fais-les dans cet ordre : chacun élimine une classe de faux diagnostics pour le
suivant. Consigne au fur et à mesure dans [`RESULTATS.md`](RESULTATS.md).

### Série 1 — les bloquants, en fenêtre

Témoin en **mode horloge** (touche `1`), fenêtre Chrome normale, écran interne.

---

**C1 · les clics ordinaires passent**

Sans toucher à ⌥⌘ : sélectionne le texte du champ à la souris, clique les boutons du
panneau, double-clique un mot.

✅ Tout se comporte comme si Regarde n'existait pas.
❌ Un clic est avalé, une sélection ne part pas.

---

**C2 · rien ne passe sous ⌥⌘** — *fatal*

Maintiens ⌥⌘, glisse sur le champ de texte.

✅ Un trait rouge apparaît et **aucun texte n'est sélectionné**.
❌ Du texte se sélectionne sous le trait → le geste ne fonctionne pas, arrêt.

---

**C3 · l'application testée continue de s'animer**

Pendant que tu maintiens ⌥⌘ et que tu traces, regarde la trotteuse.

✅ Elle tourne sans à-coup pendant tout le tracé.
❌ Elle se fige ou saccade.

---

**C4 · le focus n'est jamais volé**

Clique d'abord dans le champ de texte pour y placer le curseur de saisie. Puis trace.

✅ Le curseur continue de clignoter dans le champ pendant le tracé, et Chrome reste
l'application active.
❌ Le clignotement s'arrête, ou la barre de titre de Chrome se grise.

---

**C5 · le premier point n'est jamais perdu**

Vingt tracés courts, à des endroits variés de la page.

✅ Les vingt démarrent **exactement sous le curseur**.
❌ Un trait démarre à quelques pixels de là où tu as appuyé, ou ne démarre pas.

---

**C6 · pas d'événement orphelin au relâchement**

Commence un tracé ⌥⌘, puis **relâche ⌥⌘ avant le bouton de la souris**. Continue de
bouger, puis relâche le bouton.

✅ Le trait va jusqu'au bout, rien n'est sélectionné dans le champ.
❌ Du texte se sélectionne dès que ⌥⌘ est relâché.

Puis le cas inverse : clique **sans** modificateur dans le champ, garde le bouton
enfoncé, presse ⌥⌘, bouge, relâche.

✅ La sélection de texte se fait normalement — le clic avait commencé dans l'application,
il lui appartient jusqu'au bout.

Enfin, dans le **Finder** : commence à glisser un fichier, presse et relâche ⌥⌘ en
cours de glissement, dépose.

✅ Aucun drag fantôme, le fichier se dépose normalement.

---

**C6b · pas d'orphelin après `Échap`**

*Ce critère existe parce que la première version du prototype échouait dessus.*

Ouvre la console Chrome (⌥⌘I) et colle :

```js
addEventListener('mousemove', e => e.buttons && console.log('FUITE mousemove buttons=' + e.buttons), true);
addEventListener('mouseup',   e => console.log('FUITE mouseup'), true);
```

Puis : ⌥⌘-glisser sur le champ, presser `Échap` **sans relâcher le bouton**, continuer
de bouger deux secondes, relâcher.

✅ Le trait disparaît, aucune sélection, et **la console reste muette**.
❌ Une ligne `FUITE` apparaît → l'application testée reçoit le milieu d'un clic dont
elle n'a pas vu le début.

Même manipulation dans le Finder avec un fichier en cours de glissement.

---

**C6c · le clic droit annule sans rien laisser filtrer**

Les écouteurs de C6b sont toujours en place ; ajoute celui-ci dans la console :

```js
addEventListener('contextmenu', e => console.log('FUITE contextmenu'), true);
```

Trace sous ⌥⌘, puis **clique droit sans relâcher le bouton gauche**. Relâche tout.

✅ Le trait disparaît, aucun menu contextuel ne s'ouvre, la console reste muette.
❌ Un menu contextuel s'ouvre, ou une ligne `FUITE` apparaît.

Puis, **hors tracé**, clique droit normalement dans la page — avec et sans ⌥⌘.

✅ Le menu contextuel s'ouvre à chaque fois. Le bouton droit n'appartient à Regarde
que pendant un tracé, jamais le reste du temps.

---

**Écran externe.** Refais C2, C5 et C6 sur ton écran 3440×1440. Sa configuration —
origine x négative *et* placé au-dessus — exerce les deux pièges de coordonnées du
§ 3.3, et c'est là que le défaut de drainage multiple se serait manifesté.

✅ Les traits apparaissent sous le curseur, à la bonne échelle, sur le bon écran.
❌ Traits décalés, à double échelle, hachés, ou apparaissant sur l'autre écran.

---

### Série 2 — C3b, le coût de composition

Six minutes, à faire d'une traite. Détail dans [`RESULTATS.md`](RESULTATS.md).

1. Témoin en **mode charge** (touche `2`), **plein écran** (⌃⌘F), sur l'écran interne.
2. **Attends le calibrage.** Le témoin mesure le rafraîchissement, puis règle la charge
   jusqu'à 2–8 % de frames perdues et la **gèle**. Le bouton de relevé reste refusé tant
   que ce n'est pas fait — c'est voulu.
3. Six relevés de 30 s, dans cet ordre :

| Ordre | Étiquette | Ce que tu fais |
|---|---|---|
| 1 | `1-reference` | **Quitte Regarde** (menu ◎ → Quitter) |
| 2 | `2-calque-non-ordonne` | Relance Regarde, ne touche à rien |
| 3 | `3-trace-continu` | Maintiens ⌥⌘ et trace sans discontinuer 30 s |
| 4 | `3-trace-continu-bis` | idem |
| 5 | `2-calque-non-ordonne-bis` | idem qu'au 2 |
| 6 | `1-reference-bis` | Quitte Regarde à nouveau |

L'ordre inverse à la fin neutralise la dérive thermique de la machine.

4. « Copier le JSON », colle dans `RESULTATS.md`.

**Seuils** : état 2 < **1 %**, état 3 < **5 %**. La page doit garder le focus tout du
long — si elle le perd, c'est C4 qui a échoué, pas C3b.

---

### Série 3 — les non-bloquants

**C7 · latence** — après au moins 500 points tracés, menu ◎ → *Rapport de latence*.
Seuil p95 < 33 ms, objectif < 16 ms. Un p95 proche de 16 ms est la quantification
normale d'un rendu à 60 Hz, pas une régression.

**C8 · plein écran et Space** — menu ◎ → *Épingler le calque*, puis passe Safari en
plein écran natif et change de Space.
✅ Le trait reste visible par-dessus.

**C9 · Stage Manager** — active Stage Manager, calque épinglé.
✅ Le calque n'est pas happé dans une pile.

**C10 · tap actif après 30 min** — laisse tourner, puis `./Tools/status.sh`.
✅ Le compteur d'événements a monté, **reconstructions = 0**.

**C11 · banc, étalonnage seulement** — menu ◎ → *Activer le banc C11*, témoin en mode
compteur (touche `3`), touche `A` pour aligner l'horloge, puis trace plusieurs marques.
Les PNG vont dans `~/Regarde-lot0/c11/`. Compare le numéro **gravé dans l'image** au
journal de la page. Le verdict de C11 ne se rend qu'au lot 3.

**C12 · événements synthétiques** — nécessite Karabiner ou un pilote de souris tiers.
Vérifié : les événements postés par `CGEventPost` portent un timestamp valide, donc on
ne peut pas simuler ce cas.

---

## Si quelque chose cloche

1. **`./Tools/status.sh`** — le tap est-il vivant ? C'est la question du § 4.2, et la
   quasi-totalité des « bugs » de cette phase n'en sont pas.
2. Icône **◉** rouge → le tap est mort. Regarde les permissions dans la sortie.
3. `~/Regarde-lot0/journal.txt` — ce que l'application a vu à son démarrage, **sous sa
   propre identité**. C'est la seule source fiable : lancé depuis un terminal, le binaire
   hérite des autorisations du terminal parent et ses préflights mesurent la mauvaise chose.
4. Autorisation qui saute après un build → Réglages › Confidentialité et sécurité ›
   Surveillance de la saisie : retirer l'entrée, la remettre, relancer.

**Décris ce que tu vois plutôt que ce que tu en déduis** — c'est plus utile pour trouver.
