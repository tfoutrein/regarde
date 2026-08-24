# Lot 4 — les neuf seuils, écrits avant la première mesure

**Date** : 24 août 2026 — S46. Aucune ligne de Swift n'existe encore pour ce lot.

Un seuil écrit après coup est un seuil ajusté au résultat — la leçon de S31,
appliquée ici à ce qui décide de la suite du projet : quatre de ces neuf seuils
**sont** le GO/NO-GO n°2. Chaque seuil porte son unité, sa méthode de relevé et sa
source. Aucun ne pourra être modifié après la première mesure sans que la
modification soit datée et motivée dans ce fichier.

---

## Les quatre seuils du GO/NO-GO n°2 (plan § 3.2)

Le § 3.2 énonçait trois d'entre eux en français sans les traduire en unités
relevables. Voici la traduction, et ce qui la rend relevable par commande
(`lot4-gonogo.sh`, S55) plutôt que par impression.

### 1. Fréquence spontanée

- **Seuil** : ≥ 5 sessions spontanées sur 10 jours ouvrés.
- **Unité** : sessions / 10 jours ouvrés.
- **Relevé** : entrées d'`index.jsonl` de tous les projets, horodatées ; une session
  est *spontanée* si elle n'est ni un banc (`--c11-bench`, scripts `lot*-*.sh`) ni
  une session de recette identifiée. La fenêtre des 10 jours part de la première
  session qui suit `v0.4.0`.
- **Source** : plan § 3.2, « une session tous les deux jours ».

### 2. Taux de repli

- **Seuil** : replis ≤ 50 % des besoins de retour visuel, où
  besoins = sessions spontanées + replis déclarés.
- **Unité** : ratio replis / (sessions + replis), sur la même fenêtre de 10 jours.
- **Relevé** : un repli se **déclare** — élément de barre de menus « J'ai préféré
  une capture manuelle » — et s'écrit dans `metrics.jsonl` avec son horodatage et un
  motif optionnel. `lot4-gonogo.sh` refuse de conclure si *aucun* repli n'a jamais
  été noté : zéro repli déclaré sur dix jours mesure l'oubli de déclarer, pas la
  perfection de l'outil (S55).
- **Source** : plan § 3.2, « la moitié des besoins de retour visuel ».

### 3. Qualité du diff

- **Seuil** : ≥ 7 des 10 derniers rapports avec verdict « diff pertinent sans
  réexplication ».
- **Unité** : rapports / 10 derniers rapports *ayant un verdict*.
- **Relevé** : le verdict se **persiste** au moment où l'on traite le rapport —
  pertinent / à réexpliquer / non utilisé — dans `metrics.jsonl` (S55). Un rapport
  sans verdict ne compte ni pour ni contre ; sous 10 verdicts, `lot4-gonogo.sh`
  refuse de conclure.
- **Source** : plan § 3.2, « 7 sur 10 ».

### 4. Coût de la fin de session

- **Seuil** : ≤ 20 s entre le raccourci de fin et la phrase au presse-papiers,
  au 95ᵉ centile des sessions de la fenêtre.
- **Unité** : secondes, relevées du journal (`⌃⌥F` → « phrase au presse-papiers »)
  et recopiées dans `metrics.jsonl`.
- **Source** : plan § 3.2 et spécification § 6.6 — le seul des quatre critères que
  la conception avait déjà chiffré.

---

## Les cinq seuils d'ouvrage

### 5. Empreinte du rapport de référence

- **Seuil** : le rendu de `--render-test` (S49), à partir du **seul**
  `manifest.json` de référence, est **octet pour octet** le fichier
  `app/Tools/lot4-rapport-reference.md`, soit :
  `SHA-256 fdd77af8e3048e6d7626ba7e780978487ae5ccf7e3541e67ec1dbfb6c1802801`
  (3 480 octets).
- **Unité** : empreinte SHA-256.
- **Relevé** : `lot4-conformite.sh` la vérifie ; S49 la reproduit.
- **Source** : S46/S49 — la cible de rendu se fige avant que le moteur n'existe,
  sinon le moteur définit sa propre cible.

### 6. Poids du rapport rendu

- **Seuil** : `report.md` ≤ 25 Kio par session ; le rapport de référence pèse
  3 480 octets et son estimation texte ≈ 870 jetons (4 car./jeton, approximation
  étiquetée comme telle).
- **Unité** : Kio sur disque.
- **Relevé** : `stat` sur le fichier rendu, dans `lot4-gonogo.sh` et au passage.
- **Source** : spécification § 9.2 (« moins de 25 Ko par session » versionnables).

### 7. Exactitude des jetons annoncés

- **Seuil** : pour chaque image publiée, jetons annoncés = `min(⌈l/28⌉ × ⌈h/28⌉,
  plafond du palier)`, et l'écart entre l'annonce et la facturation constatée est
  **< 10 %**. Les quatre vecteurs de contrôle du § 9.6 sont normatifs :
  3456×2234 → **4 784** (plafond) · 2380×1540 → **4 675** · 1316×868 → **1 457** ·
  756×532 → **513**. Retirer le plafond doit faire annoncer 9 920 sur le premier
  vecteur et échouer le test (S48).
- **Unité** : jetons ; écart en %.
- **Relevé** : autotest du barème (S48) sur les quatre vecteurs plus un cinquième à
  rapport d'aspect 8:1 ; l'écart de facturation se constate au premier usage réel
  d'agent (S58 pour `full_hires`).
- **Source** : spécification § 9.6 — « l'annonce doit être exacte », c'est ce que le
  produit vend.

### 8. Distance des trois pastilles de détection

- **Seuil** : entre chacune des trois teintes (certain / probable / ambigu), mesurée
  sur capture d'écran des pastilles rendues côte à côte : **ΔE*ab ≥ 20** (CIE76,
  après conversion sRGB → Lab). Le script de S51 **refuse de conclure** si deux
  teintes sont sous ce seuil.
- **Unité** : ΔE*ab (CIE76).
- **Relevé** : script de S51, sur pixels capturés — pas sur les constantes du code,
  qui diraient ce qu'on a écrit et non ce qu'on voit.
- **Source** : risque R2 — la confirmation qui se dégrade en réflexe ; « trois états
  **visuellement** distincts, pas trois libellés dans la même couleur ».

### 9. Justesse de la détection de projet

- **Seuil** : sur les 10 sessions du passage (5 projets, S56) : **zéro verdict
  « certain » erroné**. Un « ambigu » sur une situation réellement ambiguë est un
  succès, pas un échec ; un « certain » faux est éliminatoire — c'est lui qui pousse
  un rapport dans le mauvais dépôt.
- **Unité** : verdicts erronés / 10 sessions, par catégorie de verdict.
- **Relevé** : tableau du passage S56, chaque session avec verdict affiché, projet
  réel, et concordance.
- **Source** : livrable observable du lot (« projet correct sur 10 sessions dans
  5 projets, ou affiché ambigu quand il l'est ») ; ADR-0017.

---

## Les quatre trous du § 9.2, tranchés

Actés ce jour dans la spécification (§ 9.2, amendement S46) :

1. **`context/`** — gitignoré depuis toujours mais absent de l'arborescence : le
   répertoire n'est **pas créé** avant le lot 9 ; son absence est silencieuse (P5).
2. **`transcript.txt`** — n'existe pas au lot 4 : pas de voix. Absence silencieuse ;
   le fichier naît au lot 5. Le rendu ne mentionne jamais un fichier absent.
3. **Le suffixe du nom de dossier** (`0042-20260819-1432-checkout`) — slug de la
   **branche git** si elle est détectée, sinon slug du nom de l'application cible,
   sinon rien ; `[a-z0-9-]`, tronqué à 24 caractères, jamais vide s'il y a un tiret
   qui le précède.
4. **`metrics.jsonl`** — les relevés du GO/NO-GO sont des données d'usage
   personnelles, pas des données de projet : le fichier vit **hors projet**, dans
   `~/Library/Application Support/Regarde/metrics.jsonl`, append-only, jamais
   versionné, jamais servi par MCP.

## Les trois reports de périmètre, actés

1. **`full_hires` et le second palier** (S58) — derrière l'option `include_hires`
   posée dès S49 mais inerte ; les 3 h de S58 sont hors des 32 h du lot.
2. **Tout ce qui touche la voix dans le rapport** — citations, `[terme ?]`, lexique,
   commentaires généraux dictés — au lot 5. Le rapport de référence rend la section
   « Commentaires généraux » avec « aucun. » : la *forme* est stable dès
   maintenant, le *contenu* attendra la voix.
3. **Les cinq outils MCP et le sidecar** — au lot 6. Les options de rendu qu'ils
   exigeront (`bandeau`, `filtre par marques`, `include_context`) sont posées et
   exercées **sans appelant** en S49, pour que le lot 6 n'ait pas à rouvrir la
   bibliothèque.

## Écarts assumés entre le rapport de référence et l'exemple du § 9.4

L'exemple du § 9.4 est un rapport du **lot 5+** (voix, lexique). Le rapport de
référence du lot 4 s'en déduit ainsi, et ces choix font partie du contrat de rendu :

- chapeau sans mention de transcription ni de commentaire général ; version 0.4.0 ;
- « Comment lire » sans les puces voix et `[terme ?]` ;
- marques sans citation ;
- la **marque 2 existe** — l'exemple du § 9.4 la comptait au récapitulatif sans lui
  donner de section, une incohérence du document de conception ;
- section « Commentaires généraux » toujours rendue (« aucun. » à vide) — six
  sections, toujours, dans le même ordre ;
- le paragraphe `full_hires` du § 9.4 n'apparaît pas (report n°1).
