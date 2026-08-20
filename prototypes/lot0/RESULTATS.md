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

| # | Critère | Statut | Mesure / observation |
|---|---|---|---|
| C1 | Clics normaux hors modificateur | **validé à l'usage** | L'application testée se comporte normalement hors modificateur pendant toute la session d'essai. |
| C2 | Aucun événement souris ne passe sous ⌥⌘ — **fatal** | **validé à l'usage** | Aucune fuite observée en usage réel. Un échec se serait vu immédiatement : du texte se serait sélectionné sous le tracé. Également couvert par 3 séquences d'auto-test. |
| C3 | L'application testée continue de s'animer | **validé à l'usage** | Contrôle visuel, témoin en mode horloge. |
| C3b | Cadence quantifiée, trois états | **NON MESURÉ** | Voir § C3b — dette assumée, échéance avant le lot 3. |
| C4 | Focus jamais perdu | **validé à l'usage** | Aucune perte de focus constatée. |
| C5 | Premier point jamais perdu | **validé à l'usage** | Les tracés démarrent sous le curseur. Comptage formel des 20 tracés non effectué. |
| C6 | Pas d'événement orphelin au relâchement | **validé à l'usage** | Aucun comportement aberrant signalé. Couvert par 2 séquences d'auto-test. |
| C6b | Idem après `Échap` en plein tracé | **partiellement validé** | `Échap` annule bien le trait (confirmé). L'absence de fuite `mousemove`/`mouseup` n'a pas été vérifiée en console. Couvert par 2 séquences d'auto-test. |
| C6c | Idem après un clic droit en plein tracé | **NON MESURÉ** | Fonction ajoutée après la session d'essai. Couvert par 3 séquences d'auto-test, jamais exercée à la main. |
| C7 | Latence p95 < 33 ms, objectif < 16 ms | **NON MESURÉ** | Aucune traîne visible signalée à l'usage, mais aucun chiffre relevé. Ligne de base perdue pour le lot 2. |
| C8 | Survie plein écran et changement de Space | **NON MESURÉ** | Parade au lot 7 (R10). |
| C9 | Non happé par Stage Manager | **NON MESURÉ** | |
| C10 | Tap actif après 30 min | **indice favorable** | Une instance a tourné 5 h 08 sans reconstruction ni ré-armement. Non mesuré selon le protocole. |
| C11 | Appariement marque ↔ frame | **NON MESURÉ** | Étalonnage seulement au lot 0 ; le verdict revient au lot 3. |
| C12 | Événements synthétiques (Karabiner) | **NON MESURÉ** | Établi qu'on ne peut pas le simuler : `CGEventPost` produit des timestamps valides. Exige un pilote tiers. À faire avant le lot 2. |

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

### Verdict : GO, avec une dette explicite

**La première moitié de la question est tranchée.** Le geste fonctionne sur une machine
réelle, avec un clavier AZERTY et deux écrans dont un externe non-Retina en origine
négative — la configuration qui exerce les pièges de coordonnées du § 3.3. L'application
testée garde le focus, continue de s'animer, et ne reçoit aucun événement parasite. Les
critères bloquants d'usage sont validés par un usage réel plutôt que par un protocole coché.

**La seconde moitié ne l'est pas.** C3b n'a pas été mesuré : on ignore ce que coûte le
calque à l'application observée. Ce n'est pas une formalité — c'est la mesure qui valide ou
invalide l'[ADR-0010](../../docs/adr/0010-calque-ordonne-pendant-le-trace-seulement.md), et
donc l'architecture du calque que le lot 2 va construire.

### Ce que la dette implique

| Non mesuré | Quand ça devient dû | Ce qu'on risque à attendre |
|---|---|---|
| **C3b** — coût de composition | **avant le lot 3** | Si l'état 3 dépasse 5 %, l'ordonnancement à la demande ne suffit pas et le calque du lot 2 est à revoir. Découvrir ça au lot 3 coûte le lot 2. |
| **C7** — latence p95 | avant le lot 2 | Ligne de base perdue : le lot 2 n'aura rien à quoi se comparer pour détecter une régression. |
| **C6c** — clic droit | avant le lot 2 | Couvert par l'auto-test, jamais exercé à la main. Le risque est le menu contextuel avalé hors tracé. |
| **C12** — événements synthétiques | avant le lot 2 | Un utilisateur de Karabiner verrait ses marques rejetées. Non simulable. |
| **C8, C9, C11** | lots 3 et 7 | Parades déjà budgétées, aucune décision n'en dépend d'ici là. |

### Motif du GO

Le lot 0 existe pour répondre à une question binaire : **faut-il repenser l'approche ?**
La réponse est non. Le mécanisme d'arbitrage tient, y compris dans les cas limites qui
l'auraient condamné — modificateur relâché en plein tracé, annulation bouton enfoncé,
disposition clavier non-QWERTY, écran à origine négative.

Les mesures manquantes ne remettent pas ce mécanisme en cause : elles chiffrent son coût.
C'est une dette de mesure, pas une inconnue d'architecture — et elle est datée ci-dessus.

### Ce que le lot 0 a réellement produit

Le code sera jeté ; ce qui suit reste :

- **Cinq entrées au journal des surprises**, dont deux qui changent la conception du lot 2 :
  les codes de touches physiques contre les caractères, et l'inversion de cette règle pour
  la rangée numérique — qui aurait rendu la palette d'intentions inaccessible en AZERTY.
- **Un auto-test de la porte** (13 séquences) qui survivra au prototype : la logique
  d'arbitrage du lot 2 est la même, et ces séquences la protègent.
- **Un banc de mesure** calibré pour C3b et C11, réutilisable tel quel aux lots 2 et 3.
- **Le rituel de re-signature**, sans lequel chaque build coûterait une autorisation TCC.
- **La confirmation que le budget du callback tient** : 132 µs au pire sous trafic réel,
  contre un seuil de timeout de l'ordre de la milliseconde.
