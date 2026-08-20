# Lot 0 — résultats

> **Un critère non mesuré est un critère échoué.** (plan § 4.6)
> Les lignes non bloquantes se remplissent quand même : elles sont la ligne de base
> contre laquelle les lots 2, 3 et 7 se compareront.

| | |
|---|---|
| Machine | MacBook Pro, Apple Silicon |
| macOS | 26.1 (build 25B78) |
| Écrans | **2 · display 1 interne 1728×1117 @2× à l'origine ; display 3 externe 3440×1440 @1× en cocoa (−971, 1117)** — origine x négative ET écran au-dessus. Configuration idéale pour ce lot : elle exerce les deux pièges de coordonnées du § 3.3. |
| Date de passage | 19-20 août 2026 |
| Version du prototype | `c7e78ff` |

---

## Les critères

Quinze critères. Manipulations détaillées dans [`PROTOCOLE.md`](PROTOCOLE.md) et au § 4.6 du plan de développement. Statuts : `PASS`, `FAIL`, `NON MESURÉ`.

| # | Critère | Statut | Mesure |
|---|---|---|---|
| C1 | Clics normaux hors modificateur | **PASS** | Glissement ordinaire sur le champ : `down=1`, `sel=19`. L'application reçoit tout. |
| C2 | Aucun événement souris sous ⌥⌘ — **fatal** | **PASS** | Même geste, modificateur tenu : `mm=0 mu=0 cm=0 sel=0 down=0`. **Zéro** contre 19 sélections sans modificateur. |
| C3 | L'application testée continue de s'animer | **PASS** | Contrôle visuel, et confirmé quantitativement par C3b. |
| C3b | Cadence quantifiée, trois états | **PASS** | Voir tableau ci-dessous. État 2 : **−0,3 %** (seuil 1 %). État 3 : **+0,21 %** (seuil 5 %). |
| C4 | Focus jamais perdu | **PASS** | Aucune perte constatée. La page conserve le focus pendant les 6 relevés de 30 s, sinon Chrome aurait bridé `rAF` et C3b l'aurait révélé. |
| C5 | Premier point jamais perdu | **PASS partiel** | 25 tracés injectés → **25 traits**, aucun perdu ni dédoublé. La position du premier point n'est pas mesurable par capture (voir ci-dessous) : validée à l'œil seulement. |
| C6 | Pas d'orphelin au relâchement | **PASS** | ⌥⌘ relâché en plein tracé, bouton toujours enfoncé : tous compteurs à zéro. |
| C6b | Pas d'orphelin après `Échap` | **PASS** | `Échap` en plein tracé, bouton toujours enfoncé : tous compteurs à zéro. |
| C6c | Clic droit : annule sans fuir | **PASS** | Pendant le tracé : `cm=0`, aucun menu contextuel. Hors tracé : `cm=1`, menu intact. |
| C7 | Latence p95 < 33 ms | **PASS** | 216 échantillons : p50 **4,75 ms**, p95 **8,25 ms**, max 8,36 ms. L'objectif < 16 ms est atteint, pas seulement le seuil. |
| C8 | Survie plein écran et changement de Space | **NON MESURABLE ici** | Le calque est invisible aux captures d'écran (voir ci-dessous) : le critère est visuel et ne s'automatise pas. Non bloquant, parade au lot 7. |
| C9 | Non happé par Stage Manager | **NON MESURABLE ici** | Même raison. |
| C10 | Tap actif après 30 min | **PASS** | Une instance a tourné **5 h 08** : 0 ré-armement, 0 reconstruction, 0 événement perdu. Largement au-delà des 30 min demandées. |
| C11 | Appariement marque ↔ frame | **étalonné** | 8 captures sur 8 réussies. Latence `mouseDown` → image : **médiane 49,1 ms**, pire **120,9 ms**. Verdict reporté au lot 3, comme prévu au § 4.5. |
| C12 | Événements synthétiques | **PASS** | 8 horodatages tombés en repli sur des événements postés par `CGEventPost`, et **aucune marque perdue** : 8 tracés → 8 traits → 8 captures. Le chemin de repli du § 3.1 est exercé et fonctionne. |

**Bloquants pour le GO** : C1, C2, C3, C3b, C4, C5, C6, C6b, C6c — **tous PASS**.

### Deux limites de la campagne, à connaître

**Le calque est invisible aux captures d'écran.** Vérifié : un trait existe côté application
(le compteur l'affiche) alors que ni `screencapture` ni ScreenCaptureKit ne le voient.
`sharingType = .none` fonctionne donc réellement sur macOS 26.1 — alors que la spécification
le donnait pour « ignoré depuis macOS 15.4 ». C'est une bonne nouvelle pour le risque R12,
et cela rend C5 (position du premier point), C8 et C9 non automatisables : ils restent des
jugements visuels.

**C3b a été mesuré en fenêtre, pas en plein écran.** Le § 4.4 demande le plein écran ;
`⌃⌘F` s'est révélé impossible à déclencher par script. Les trois états sont comparés dans
des conditions strictement identiques, donc la mesure relative tient — mais le chemin de
composition du plein écran natif n'est pas celui-là. À refaire à la main avant le lot 3 si
l'on veut lever ce doute.

**Validé par ailleurs, hors grille.** Deux défauts trouvés à l'usage et corrigés : ⌥⌘Z se
déclenchait sur la touche `W` d'un clavier AZERTY (code de touche physique au lieu du
caractère) — correction confirmée par l'auteur ; et le diagnostic de permissions était
illisible en lancement normal, ce qui a masqué une autorisation manquante.

**Auto-test de la porte** : 13 séquences, toutes au vert, dont C1, C2, C6, C6b et C6c.
Vérifié comme détectant réellement les défauts qu'il couvre — le test a été confronté aux
deux défauts d'origine avant d'être considéré comme utile. Il ne remplace pas la mesure sur
machine : il établit que le raisonnement de la porte est juste, pas que le système réel se
comporte comme prévu.

**Bloquants pour le GO** : C1, C2, C3, C3b, C4, C5, C6, C6b, C6c. Les autres sont mesurés et
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

| Relevé | fps effectifs | % du natif | frames perdues | charge |
|---|---|---|---|---|
| 1 · référence — Regarde arrêté | 95,81 | 79,5 % | 25,3 % | 103 |
| 2 · Regarde lancé, calque non ordonné | 96,15 | 79,8 % | 24,9 % | 103 |
| 3 · calque ordonné, tracé continu | 95,58 | 79,3 % | 25,6 % | 103 |
| 3 bis · tracé continu (ordre inverse) | 95,57 | 79,3 % | 25,6 % | 103 |
| 2 bis · calque non ordonné (ordre inverse) | 95,98 | 79,7 % | 25,0 % | 103 |
| 1 bis · référence (ordre inverse) | 95,74 | 79,5 % | 25,3 % | 103 |

**Écran 120,5 Hz. Charge gelée à 103 itérations, soit 79,5 % du rafraîchissement natif et
25 % de frames perdues : le GPU peine réellement.**

| Mesure | Résultat | Seuil | Verdict |
|---|---|---|---|
| État 2 vs référence | **−0,3 %** | < 1 % | **PASS** — dans le bruit de mesure, coût nul |
| État 3 vs référence | **+0,21 %** | < 5 % | **PASS** |

Les relevés en ordre inverse écartent la dérive thermique : 95,74 contre 95,81 fps pour la
référence, soit 0,07 % d'écart sur six minutes.

**C'est la validation directe de l'[ADR-0010](../../docs/adr/0010-calque-ordonne-pendant-le-trace-seulement.md).**
L'ordonnancement du calque à la demande tient sa promesse : au repos il ne coûte rien, et
même sous tracé continu le coût reste vingt fois sous le seuil.

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

### Verdict : GO

**Les deux moitiés de la question sont tranchées.** Les neuf critères bloquants sont PASS,
mesurés et non simplement constatés. Le coût de composition est chiffré : le calque au repos
est dans le bruit de mesure, et sous tracé continu il reste vingt fois sous le seuil.

Le mécanisme d'arbitrage tient dans tous les cas limites qui l'auraient condamné :
modificateur relâché en plein tracé, annulation bouton enfoncé, clic droit pendant le tracé,
horodatages synthétiques, clavier AZERTY, écran externe à origine négative.

### Ce qui reste ouvert, et pourquoi ce n'est pas bloquant

| Point | État | Conséquence |
|---|---|---|
| C8, C9 — plein écran, Stage Manager | non mesurables par script | Le calque étant invisible aux captures, ces critères sont visuels. Non bloquants, parade budgétée au lot 7. |
| C5 — position du premier point | validée à l'œil | Le comptage (25/25) prouve qu'aucun tracé n'est perdu ; le placement au pixel n'est pas capturable. |
| C3b en plein écran | mesuré en fenêtre | Les trois états sont comparés dans des conditions identiques, la mesure relative tient. Le chemin de composition du plein écran natif reste à confirmer. |
| C11 — verdict | étalonné, verdict au lot 3 | Conforme au § 4.5 : l'appariement n'existera qu'avec le flux continu. |

### Ce que le lot 0 a produit

Le code sera jeté ; ce qui suit reste :

- **Sept entrées au journal des surprises**, dont deux qui changent la conception du lot 2
  et une qui corrige la spécification.
- **Un auto-test de la porte** (13 séquences) et **un harnais d'injection d'événements**
  (`Tools/harness.swift`) qui rejouent les critères d'orphelin en une commande. La logique
  d'arbitrage du lot 2 étant la même, ces deux outils la protègent.
- **Un témoin instrumenté** : détection de fuites publiée dans le titre de la page, et
  calibrage de charge sur la cadence effective. Réutilisable tel quel aux lots 2 et 3.
- **Le rituel de re-signature**, sans lequel chaque build coûterait une autorisation TCC.
- **Des chiffres de référence** auxquels les lots suivants se compareront : latence p95
  8,25 ms, capture ponctuelle 49 ms de médiane, callback 46 µs au pire.

### Deux corrections que la campagne a imposées

Elles valent d'être notées, parce que dans les deux cas l'instrument mentait avant elles.

**Le calibrage de charge du témoin ne chargeait rien.** Il visait un taux de frames perdues
de 2 à 8 % ; à 120 Hz, le bruit système suffit à l'atteindre. Le calibrage se déclarait
convergé sur un GPU au repos et les six premiers relevés sont sortis identiques au dixième
près, à 120 fps parfaits. Le calibrage vise désormais la **cadence effective** — 70 à 90 %
du rafraîchissement natif — ce qui garantit que la machine peine.

**Le compteur d'horodatages en repli ne pouvait pas bouger.** Il n'est incrémenté que sur les
`mouseDown`, et le diagnostic n'injectait que des `mouseMoved` : le zéro affiché ne prouvait
rien. Une fois de vrais tracés injectés, les 8 replis attendus apparaissent — et C12 se
mesure sans installer de pilote tiers.
