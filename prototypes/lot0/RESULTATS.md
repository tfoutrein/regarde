# Lot 0 — résultats

> **Un critère non mesuré est un critère échoué.** (plan § 4.6)
> Les lignes non bloquantes se remplissent quand même : elles sont la ligne de base
> contre laquelle les lots 2, 3 et 7 se compareront.

| | |
|---|---|
| Machine | *(modèle, puce, RAM)* |
| macOS | 26.1 (build 25B78) |
| Écrans | **2 · display 1 interne 1728×1117 @2× à l'origine ; display 3 externe 3440×1440 @1× en cocoa (−971, 1117)** — origine x négative ET écran au-dessus. Configuration idéale pour ce lot : elle exerce les deux pièges de coordonnées du § 3.3. |
| Date de passage | *(à remplir)* |
| Version du prototype | `git rev-parse --short HEAD` → *(à remplir)* |

---

## Les douze critères

Manipulations détaillées au § 4.6 du plan de développement. Statuts : `PASS`, `FAIL`, `NON MESURÉ`.

| # | Critère | Statut | Mesure / observation |
|---|---|---|---|
| C1 | Clics normaux hors modificateur | | |
| C2 | Aucun événement souris ne passe sous ⌥⌘ — **fatal** | | |
| C3 | L'application testée continue de s'animer | | |
| C3b | Cadence quantifiée, trois états | | voir ci-dessous |
| C4 | Focus jamais perdu | | |
| C5 | Premier point jamais perdu | | *(20 tracés)* |
| C6 | Pas d'événement orphelin au relâchement | | |
| C6b | Idem après `Échap` en plein tracé, bouton toujours enfoncé | | |
| C7 | Latence p95 < 33 ms, objectif < 16 ms | | voir ci-dessous |
| C8 | Survie plein écran et changement de Space | | |
| C9 | Non happé par Stage Manager | | |
| C10 | Tap actif après 30 min | | |
| C11 | Appariement marque ↔ frame — étalonnage seulement au lot 0 | | |
| C12 | Événements synthétiques (Karabiner) | | |

**Bloquants pour le GO** : C1, C2, C3, C3b, C4, C5, C6, C6b. Les autres sont mesurés et
consignés, leur parade appartient à un lot ultérieur.

**C6b, ajouté après la revue adversariale.** Manipulation : ⌥⌘-glisser sur le champ de texte
du témoin 1, presser `Échap` **sans relâcher le bouton**, continuer à bouger la souris, puis
relâcher. Attendu : aucune sélection de texte, et la console ne montre ni `mousemove` porteur
de `buttons=1`, ni `mouseup`. Ce critère existe parce que la première version du prototype
échouait dessus — l'invariant « tant que le bouton n'est pas relâché, l'application ne reçoit
rien de ce clic » n'était pas tenu sur le chemin `Échap`. Même manipulation à refaire dans le
Finder, en glissant un fichier : aucun drag fantôme.

---

## C3b — coût de composition

Protocole au § 4.4 : trois états, 30 s chacun, deux premières secondes jetées, puis les
trois mêmes états **dans l'ordre inverse** pour neutraliser la dérive thermique.

Témoin 1 en mode charge (touche `2`), **plein écran**, sur l'écran de référence.
La page doit garder le focus pendant toute la mesure — Chrome bride `requestAnimationFrame`
sur un onglet inactif, et si elle le perd, c'est C4 qui a échoué, pas C3b.

**Attendre le calibrage avant le premier relevé.** Le témoin mesure d'abord la période de
rafraîchissement réelle, puis règle la charge du shader jusqu'à obtenir entre 2 % et 8 % de
frames perdues, et **gèle** cette charge. Le bouton de relevé refuse de démarrer tant que ce
n'est pas fait : un relevé pris sur une charge nulle donnerait un `PASS` sans mesure.

**La métrique est la cadence effective** — frames rendues divisées par la durée écoulée —
et non la médiane des deltas. Cette dernière est quantifiée par le vsync : elle ne prend que
les valeurs 16,67 / 33,3 / 50 ms et ne peut donc pas résoudre une dégradation de 5 %.

| Rafraîchissement mesuré | | Charge gelée (itérations) | |
|---|---|---|---|

| État | fps effectifs | frames perdues % | dégradation | Seuil |
|---|---|---|---|---|
| 1 · référence — Regarde non lancé | | | — | — |
| 2 · Regarde lancé, calque non ordonné | | | | **< 1 %** |
| 3 · calque ordonné, tracé continu | | | | **< 5 %** |
| 3 bis · tracé continu (ordre inverse) | | | | |
| 2 bis · calque non ordonné (ordre inverse) | | | | |
| 1 bis · référence (ordre inverse) | | | — | — |

Un relevé marqué « charge ≠ » n'est pas comparable et invalide le verdict : c'est le
garde-fou contre une charge qui aurait dérivé entre deux états.

**Lecture.** L'état 2 doit coûter zéro : c'est l'état majoritaire d'une session. Au-delà de 1 %,
l'ordonnancement à la demande de l'[ADR-0010](../../docs/adr/0010-calque-ordonne-pendant-le-trace-seulement.md)
ne suffit pas et quelque chose reste composité en permanence — c'est un défaut d'implémentation,
pas un arbitrage.

**Si C3b échoue à l'état 3**, la parade est déjà écrite : vérifier l'ordonnancement à la demande
avant d'aller plus loin. Si elle échoue à l'état 2, chercher ce qui reste à l'écran.

JSON du témoin (bouton « Copier le JSON ») :

```json
```

---

## C7 — latence tap → commit

Menu ◎ → « Rapport de latence ». Au moins 500 points tracés avant de lire le résultat.

| Mesure | Valeur |
|---|---|
| Échantillons | |
| p50 | |
| p95 | |
| p99 | |
| Maximum | |
| Pire durée dans le callback | |

Seuil C7 : p95 < 33 ms. Objectif : < 16 ms.

---

## C11 — étalonnage du banc

**Le verdict de C11 ne se rend pas au lot 0** (plan § 4.5) : il n'y a pas encore de flux
continu, donc pas d'appariement à valider. Ce qu'on mesure ici est la latence propre du
chemin `SCScreenshotManager.captureImage`, utile pour le mode éclair du lot 2, et le fait
que le banc soit rodé avant que C11 compte vraiment, au lot 3.

Procédure : menu ◎ → « Activer le banc C11 », témoin 1 en mode compteur (touche `3`),
aligner l'horloge (touche `A` ou clic dans la scène) en notant le `SessionTime` affiché
par Regarde au même instant, puis tracer plusieurs marques.

| Mesure | Valeur |
|---|---|
| Captures réussies / tentées | |
| Latence `mouseDown` → image, médiane | |
| Latence, pire cas | |
| Décalage `performance.now()` ↔ horloge hôte | |
| Écart numéro gravé ↔ numéro journalisé | *(tolérance 16 ms)* |

---

## Diagnostic de l'exécution

Menu ◎ → « Tout exporter (JSON) », ou `~/Regarde-lot0/mesures.json`.

| Indicateur | Valeur | Attendu |
|---|---|---|
| Événements vus par le tap | | monte en continu |
| Ré-armements | | 0 en usage normal ; > 0 après le test T0.8 |
| **Reconstructions du tap** | | **0** — une reconstruction non provoquée est un défaut |
| Événements perdus (ring) | | **0** |
| Horodatages en repli | | 0 sans pilote tiers, > 0 avec (C12) |
| Origines de latence en repli | | proportion à connaître pour interpréter le p95 |
| Pire durée dans le callback | | très loin sous le seuil de timeout |
| Capturés / laissés passer | | |

**Le p95 de latence est mesuré par événement, pas par frame.** Un p95 autour de 16 ms est
la quantification normale d'un rendu à 60 Hz, pas une régression : c'est la valeur de
référence à laquelle le lot 2 se comparera.

---

## Journal des surprises

Ce que le prototype a appris et qui n'était pas dans la spécification. Cette section est le
vrai produit du lot 0 : le code, lui, sera jeté.

| Constat | Conséquence pour la suite |
|---|---|
| **`kCGKeyboardEventKeycode` designe un EMPLACEMENT, pas un caractere.** Le code 6 porte `Z` en QWERTY et `W` en AZERTY : ⌥⌘Z, code en dur sur 6, avait migre sur la touche `W` du clavier francais. Trouve par l'auteur en testant, pas par la revue. | Regle pour tout le projet : un raccourci qui designe une **lettre** se resout par le caractere, via `UCKeyTranslate` sur la disposition courante, au demarrage et a chaque changement de disposition — jamais dans le callback du tap. Les touches sans caractere (Échap, fleches, Tab) gardent leur code physique, stable. |
| **Mais la regle s'inverse pour la rangee numerique.** Sur AZERTY, resoudre le caractere `1` renvoie le code **83 — le pave numerique**, absent des MacBook ; la rangee du haut produit `& é " ' ( -` aux codes 18 a 24. | **Contrainte de conception pour le lot 2 et l'[ADR-0021](../../docs/adr/0021-desambiguisation-option-commande-chiffre.md)** : la palette d'intentions `⌥⌘ + 1..6` et les marques retroactives `⌥⌘ + 1..9` doivent utiliser les **codes physiques** de la rangee numerique, pas la resolution par caractere. Appliquer la meme regle qu'aux lettres aurait rendu la palette inaccessible sur un clavier francais. |
| **Le budget du callback est tenu avec une marge de trois ordres de grandeur.** Pire passage mesuré : **5 µs**, contre un seuil de timeout de l'ordre de la milliseconde. | Referme un angle mort de la revue : le raisonnement sur le coût des allocations dans le callback reposait sur des ordres de grandeur, pas sur une mesure. À re-mesurer sous une souris à 1000 Hz, mais la marge rend le risque R9 peu probable côté budget. |
| **Les événements postés par `CGEventPost` portent un timestamp valide** — 0 horodatage en repli sur 25 événements synthétiques. | Contredit l'hypothèse que « synthétique » implique `timestamp == 0`. Le chemin de repli du § 3.1 ne s'exerce donc PAS avec des événements postés : **C12 exige réellement d'installer Karabiner** ou un pilote tiers, on ne peut pas le simuler. |
| **`SCContentFilter.pointPixelScale` est un `Float`**, pas un `CGFloat`. | Lot 3 : ne jamais supposer un facteur entier de 2. Sur le display 3 de cette machine il vaut 1,0. |
| **`NSScreen` n'est pas `Sendable`.** | Aucun `NSScreen` ne peut franchir une frontière d'isolation : seul l'identifiant d'écran circule. |
| **`os_log` n'est pas remonté par `log show` pour ce bundle**, malgré des `notice` et des `error`. | D'où le mode `--doctor` : quand l'application est lancée par `open`, sa sortie standard n'est visible nulle part. Un diagnostic en ligne de commande n'est pas un confort, c'est la seule voie. |

---

## GO / NO-GO n°1

Question posée (plan § 3.1) : **le geste fonctionne-t-il, et à quel coût de composition ?**

- [ ] C1, C2, C3, C3b, C4, C5, C6 sont tous `PASS`
- [ ] Aucun événement perdu dans le ring
- [ ] Le tap survit à 30 minutes sans ré-armement anormal

**Décision** : *(GO / NO-GO / GO conditionnel)*

**Motif** :

**Si NO-GO** — ce qui est remis en cause, et quelle option de repli est étudiée.
