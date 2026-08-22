# Recette du lot 3 — tests manuels

Ce que vous validez : **l'image jointe à une marque montre l'instant que vous
désigniez, et pas celui d'après.** C'est tout le lot, et c'est un bug qu'aucun test
automatisé ne peut voir — sur un écran statique le résultat est parfait, et c'est
sur un écran statique qu'on teste spontanément.

Comptez **50 à 60 minutes**. Les sections 1 et 2 sont bloquantes.

> **Cette recette est écrite avant sa première exécution.** Celle du lot 2 comptait
> 43 tests faux ou infaisables dans sa première version. Si un test ci-dessous décrit
> quelque chose qui n'existe pas, ou demande de regarder au mauvais endroit, c'est le
> test qu'il faut corriger — notez-le, il vaut un défaut.

---

## Avant de commencer

Deux terminaux, comme au lot 2 :

```bash
# 1. Le journal, AVANT de lancer l'application
tail -F ~/Regarde/journal.txt

# 2. L'application
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app && ./Tools/build-app.sh --run
```

`-F` majuscule et lancé **avant** : le journal est recréé à chaque démarrage, un `-f`
minuscule resterait accroché au fichier supprimé et n'afficherait plus rien, en
silence.

**Le témoin est l'instrument central de ce lot.** Sans lui, la moitié des tests ne
mesure rien :

```bash
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/prototypes/lot0 && ./Tools/serve-temoin.sh
```

Puis `3` pour le mode compteur, et **plein écran par le menu *Présentation***, pas
par `⌃⌘F` — le chemin de composition n'est pas le même, et c'est celui-là qu'on
mesure.

**Deux écrans sont nécessaires** aux sections 5 et 7. L'anneau de frames est par
flux : un budget mesuré sur un seul écran serait rassurant et faux.

**Ce qui n'existe pas encore**, pour ne pas le chercher :

| | |
|---|---|
| Voix et transcription | lot 5 |
| Rapport texte, `report.md`, projet cible | lot 4 |
| Serveur MCP | lot 6 |
| Pré-roll et marques rétroactives `⌥⌘ + 1..9` | S44 et S45, **bloc de marge** — livrés ensemble ou décalés ensemble |
| Déduplication perceptuelle | **retirée du MVP** (§ 5.7), pas reportée |

---

## 1. Le flux démarre et s'arrête — bloquant

- [ ] **1.1** `⌃⌥S` ouvre une session. Le journal montre `flux ouvert sur display N`
      avec des dimensions, puis l'icône passe au rouge.
      *Si vous voyez `flux non démarré`, la raison suit sur la même ligne. L'état
      revient à `idle` et non à `blocked` : le tap va bien, c'est cette tentative qui
      a échoué.*
- [ ] **1.2** Le bloc `FLUX` de fin de session donne `demandé` et `tampon réel`
      **identiques**.
      *S'il annonce `tampon en 1920×1080 alors qu'on demandait autre chose`,
      arrêtez-vous : `width`/`height` ont été ignorés et toutes les images du lot
      sont en résolution perdue. C'est le piège silencieux du § 5.2.*
- [ ] **1.3** Le même bloc donne `frames complètes` sur un théorique. Avec le témoin
      **en mouvement**, le compte doit être proche du théorique.
      *Un compte bas sur écran figé est NORMAL — ScreenCaptureKit ne livre que sur
      changement. Sur écran animé, il ne l'est pas.*
- [ ] **1.4** `⌃⌥F` ferme. Le journal donne `flux fermé sur display N` pour **chaque**
      écran, puis un bloc `EXTRACTION`.
- [ ] **1.5** Après la publication, `ls $TMPDIR/regarde*/` ne contient **aucun `.mov`**.
      *C'est de la vidéo de votre écran. L'ADR-0020 en borne la vie à celle du besoin
      qui l'a créée.*

## 2. Ne rien casser — bloquant

- [ ] **2.1** `./Tools/lot2-eclair.sh` — le mode éclair publie toujours son dossier
      complet, hors session.
      *Le mode majoritaire, et le seul chemin qu'un développement centré session ne
      traverse jamais. C'est là qu'un défaut se cache.*
- [ ] **2.2** `./Tools/lot2-livrable.sh` — six marques, deux vues d'ensemble, aucun
      fichier inattendu.
- [ ] **2.3** `./Tools/lot2-cible.sh` — le contrôle d'encre passe.
- [ ] **2.4** Pendant une session, `⌘Z` dans l'application testée **annule dans
      l'application**, pas dans Regarde.
      *Le raccourci le plus utilisé de macOS. Il a été volé une fois.*
- [ ] **2.5** Ouvrez une session, tracez, **verrouillez l'écran** (`⌃⌘Q`), déverrouillez.
      Le journal dit `suspension forcée`, les marques sont abandonnées, et `⌥⌘` arme
      de nouveau normalement ensuite.
      *Si `⌥⌘` n'arme plus nulle part après, la cible est restée gelée — c'est le
      défaut corrigé au commit d'ouverture du lot.*

## 3. L'instant exact — le cœur du lot

- [ ] **3.1** Témoin en mode compteur, plein écran. Ouvrez une session, tracez
      **huit marques pendant que le compteur défile**, fermez.
- [ ] **3.2** Le bloc `EXTRACTION` donne `depuis le fichier 8` et
      `servies par le filet 0`.
      *Une marque servie par le filet n'est pas une panne : son image vient de la
      capture ponctuelle au relâchement, donc d'un instant postérieur. Le journal
      nomme le motif par marque.*
- [ ] **3.3** Le même bloc donne `pire écart demandé/obtenu` **sous 67 ms**.
      *C'est l'intervalle entre deux frames encodées à 15 fps. Au-delà, le générateur
      a rendu autre chose que la frame demandée.*
- [ ] **3.4** Ouvrez chaque `marque-NN.png` et lisez la réglette en bas :
      `./.build/debug/Regarde --lire-reglette <png>` rend un `V`, un `module`
      proche de 64, et **zéro bit faible**.
      *Un `refus` nomme lequel des neuf motifs. « localisateur absent » veut dire que
      la réglette n'est pas dans l'image — cherchez le cadrage, pas le temps.*
- [ ] **3.5** Comparez le `V` lu au journal du témoin. **C'est le test qui décide du
      lot.** `app/Tools/lot3-c11.sh` le fait pour vous.
- [ ] **3.6** Refaites 3.1 sur un écran **strictement immobile**. Les huit marques
      sont servies par le filet RAM, et le journal le dit pour chacune.
      *Un écran figé ne produit aucun échantillon : le segment est vide, et c'est
      normal. Ce qui compterait comme un défaut, c'est que ça ne se dise pas.*

## 4. Le burst

- [ ] **4.1** Sur le témoin en mouvement, une marque : le journal donne
      `marque N · 3 frame(s) au plan`.
- [ ] **4.2** Sur un écran immobile, une marque : `1 frame(s) au plan`.
- [ ] **4.3** Un terminal avec un **curseur qui clignote et rien d'autre**, une
      marque : `1 frame(s) au plan`.
      *Fréquence élevée, surface dérisoire. Si vous obtenez 3, le double critère ne
      fonctionne pas et chaque marque coûte trois fois son prix.*
- [ ] **4.4** Une marque **dans la dernière seconde** de la session : le plan tombe à
      2 frames, et `burst — N frame(s) obtenues sur M demandée(s)` montre l'écart.

## 5. Les écrans

- [ ] **5.1** Mettez l'écran externe en **recopie vidéo** (Réglages → Moniteurs).
      Le journal dit `écran N écarté — écran en recopie vidéo`.
- [ ] **5.2** Tentez un `⌥⌘`-glisser sur cet écran : **rien ne se trace**, le HUD
      annonce « Écran non annotable » avec le conseil.
      *Laisser tracer serait pire : le numéro s'incrémenterait et le dossier
      sortirait sans l'image, ou avec celle d'un autre écran.*
- [ ] **5.3** Repassez en mode étendu. L'écran redevient annotable sans redémarrer.
- [ ] **5.4** *(si votre écran pivote)* Mettez-le en **portrait**. Le journal dit
      `écran en rotation`. En 180°, il reste annotable — la conversion y est juste.

## 6. La confidentialité

- [ ] **6.1** Ouvrez une session, puis **lancez une application de la liste noire**
      (1Password, Trousseau d'accès). Le journal dit `… lancée et exclue — filtre
      reconstruit`.
      *Sans ce canal, l'exclusion ne vaudrait que pour ce qui tournait déjà au
      démarrage — et un gestionnaire de mots de passe s'ouvre précisément pendant
      qu'on teste ce à quoi il donne accès.*
- [ ] **6.2** Ouvrez une image publiée et cherchez le calque, un badge, le HUD.
      **Aucun pixel.**
- [ ] **6.3** `ls -la $TMPDIR/regarde*` → répertoires en `drwx------`, fichiers en
      `-rw-------`.
- [ ] **6.4** Tuez l'application en pleine session (`pkill -9 Regarde`), relancez,
      ouvrez une session. Le journal dit `N répertoire(s) de session purgé(s)`.
      *Un `.mov` orphelin est de la vidéo de votre écran qui survit indéfiniment.*

## 7. Le débranchement

- [ ] **7.1** `./Tools/lot3-debranchement.sh` et suivez-le.
- [ ] **7.2** Le journal dit `display N débranché — finalisation immédiate`.
- [ ] **7.3** La session **continue** sur l'écran restant, et se ferme normalement.
- [ ] **7.4** Les marques de l'écran débranché **ont leur image**.
      *C'est le point du critère. Si elles ne l'ont pas, le motif est dans le journal
      par marque.*

## 8. Les budgets

- [ ] **8.1** `./Tools/lot3-budgets.sh` — dix minutes, **deux écrans**.
- [ ] **8.2** RSS crête sous 200 MiB.
- [ ] **8.3** CPU moyen sous 3 %.
- [ ] **8.4** Disque sous 500 MiB pour dix minutes.
- [ ] **8.5** Bloc `EXTRACTION`, ligne `durée` : sous 3 s.
      *Le budget du § 6.6 : au-delà, le calcul de fin de session est déjà perdu.*
- [ ] **8.6** Aucun plantage après **vingt minutes** sous charge.
      *B2. Un `EXC_BAD_ACCESS` dans `CVPixelBufferRelease` n'est pas reproductible à
      la demande — sa fréquence dépend de l'activité de l'écran. Vingt minutes sur du
      contenu très animé est le seul filet.*

## 9. C3b — la dette du lot 0

- [ ] **9.1** `./Tools/lot3-temoin.sh --duree 60`, en plein écran natif.
- [ ] **9.2** Six relevés, **dans les deux ordres**, tous au même `glLoadLocked`.
- [ ] **9.3** État 2 sous 1 %, état 3 sous 5 %.
- [ ] **9.4** `chargeInsuffisante` à **faux** sur les six.
      *Sinon le calibrage a atteint sa butée sans faire peiner la machine, et la
      mesure ne vaut rien.*
- [ ] **9.5** La cadence effective reste entre **70 et 90 %** du natif **pendant** les
      relevés, pas seulement au calibrage.
      *Le relevé du 21 août est sorti à 58 %. L'hypothèse consignée est thermique :
      le calibrage converge sur une seconde, le relevé dure soixante fois plus. Si
      vous le revoyez, notez `refreshHz` et le relevé apparié sans réglette.*
