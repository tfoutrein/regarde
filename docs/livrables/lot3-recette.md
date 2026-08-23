# Recette du lot 3 — tests manuels

Ce que vous validez : **l'image jointe à une marque montre l'instant que vous
désigniez, et pas celui d'après.** C'est tout le lot. Sur un écran immobile le
résultat est toujours parfait — et c'est sur un écran immobile qu'on teste
spontanément. D'où le témoin animé, qui est l'instrument central de cette recette.

Comptez **50 à 60 minutes**. Les sections 1 et 2 sont bloquantes.

> **Chaque test se lit en quatre temps** : ce que vous **faites**, où vous
> **regardez**, ce que vous devez **voir**, et quoi faire **si ça rate**. Si un test
> vous demande de regarder au mauvais endroit, ou décrit quelque chose qui n'existe
> pas, c'est le test qui est faux — notez-le, il vaut un défaut.

---

## Avant de commencer

**Deux terminaux.** Le journal se lance **avant** l'application :

```bash
# Terminal 1 — le journal
tail -F ~/Regarde/journal.txt

# Terminal 2 — l'application
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app && ./Tools/build-app.sh --run
```

`-F` majuscule : le journal est effacé et recréé à chaque démarrage, un `-f`
minuscule resterait accroché au fichier supprimé et n'afficherait plus rien, sans le
dire.

**Le témoin**, dans un troisième terminal :

```bash
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/prototypes/lot0 && ./Tools/serve-temoin.sh
```

Si le script refuse en disant qu'un autre serveur occupe le port, il vous donne le
`kill` exact : un `python3 -m http.server` d'avant peut traîner depuis des jours, et
il ne sait pas recevoir les dépôts.

Chrome s'ouvre. **Cliquez le bouton « 3 · Compteur »** plutôt que de taper `3` : le
champ de test a le focus au chargement — c'est le critère C4, le caret doit
continuer de clignoter pendant un tracé — et les frappes nues s'y écrivent au lieu
d'être interprétées. Si vous préférez le clavier, cliquez d'abord dans la scène.

Puis plein écran **par le menu *Présentation → Activer le mode plein écran***. Pas
par `⌃⌥⌘F` : le chemin de composition n'est pas le même, et c'est celui-là qu'on
mesure.

**Ce que vous devez voir** : une bande noire et blanche en bas de l'écran, qui
grésille à chaque image, par-dessus un fond sombre animé. **Pas de gros chiffres** —
c'est la bande qui porte le numéro de frame, en code binaire lisible par machine.
Les chiffres décoratifs existent derrière `⌃⌥N`, mais aucun relevé n'est accepté tant
qu'ils sont allumés : leur mise en page coûte un temps variable selon le nombre de
chiffres, ce qui fausserait une mesure à 0,1 %.

**Deux écrans** sont nécessaires aux sections 5, 7 et 8.

### Deux icônes différentes, à ne pas confondre

| Icône | Qui l'affiche | Ce qu'elle dit |
|---|---|---|
| Disque **rouge** dans la barre de menus | Regarde | une session est ouverte |
| Icône **violette** dans la barre de menus | **macOS**, pas Regarde | l'écran est en cours de capture |

La violette apparaît d'elle-même dès que la capture démarre, et cliquer dessus
affiche « Regarde · Partage en cours ». C'est normal, c'est le § 10.6, et c'est même
une bonne preuve que le flux tourne. Mais ce n'est **pas** l'icône de Regarde.

### Ce qui n'existe pas encore

Pour ne pas le chercher :

| | |
|---|---|
| Voix et transcription | lot 5 |
| Rapport texte, `report.md`, projet cible | lot 4 |
| Serveur MCP | lot 6 |
| Pré-roll, marques rétroactives `⌥⌘ + 1..9` | S44 et S45, **bloc de marge** — livrés ou décalés ensemble |
| Déduplication perceptuelle | **retirée du MVP** (§ 5.7) — pas reportée, retirée |

---

## 1. Le flux démarre et s'arrête — bloquant

- [ ] **1.1** Une session ouverte démarre un flux de capture
      FAIRE : cliquer dans la fenêtre du témoin, puis frapper `⌃⌥S`.
      REGARDER : le terminal du journal.
      ATTENDU : une ligne `flux ouvert sur display N — LARGEURxHAUTEUR demandés à 15 fps`,
      une par écran.
      ATTENDU : l'icône de Regarde dans la barre de menus devient un **disque rouge**.
      ATTENDU : l'icône **violette** de macOS apparaît aussi — c'est le système, pas nous.
      SI ÇA RATE : cherchez `flux non démarré` dans le journal, la raison suit sur la
      même ligne. L'état repasse à `idle` et non à `blocked` : le tap et les
      autorisations vont bien, c'est cette tentative-ci qui a échoué.

- [ ] **1.2** La capture sort à la bonne résolution
      FAIRE : frapper `⌃⌥F` pour fermer la session.
      REGARDER : dans le journal, le bloc `FLUX`, lignes `demandé` et `tampon réel`.
      ATTENDU : les deux valeurs sont **identiques**.
      SI ÇA RATE : si vous lisez `tampon en 1920×1080 alors qu'on demandait autre
      chose`, **arrêtez la recette ici**. `width` et `height` ont été ignorés, toutes
      les images du lot sont en résolution perdue, et le texte y sera illisible. C'est
      le piège silencieux du § 5.2 — il ne produit aucune erreur.

- [ ] **1.3** Le flux reçoit bien les images de l'écran qui bouge
      FAIRE : rouvrir une session, laisser le témoin animé tourner **20 secondes**
      sans rien faire, fermer.
      REGARDER : **le bloc `FLUX` de l'écran qui porte le témoin** — il y en a un par
      écran, et ils ne disent pas la même chose.
      ATTENDU : sur cet écran-là, `frames complètes` proche du théorique annoncé à
      côté (environ 15 par seconde).
      ATTENDU : sur l'écran **immobile**, un compte bas et un `autres statuts` élevé —
      c'est normal, et c'est même la preuve que la double garde fonctionne.
      SI ÇA RATE : ScreenCaptureKit ne livre une image `complete` que lorsque l'écran
      CHANGE ; le reste du temps il livre des statuts `idle`, comptés à part. Un
      compte bas sur l'écran animé, en revanche, n'est pas normal.

- [ ] **1.3 bis** Le `contentRect` est cohérent avec le tampon
      FAIRE : rien de plus, la session vient d'être fermée.
      REGARDER : dans le bloc `FLUX`, les lignes `tampon réel` et `contentRect`.
      ATTENDU : sur un écran Retina, `contentRect` vaut la **moitié** du tampon —
      3456×2234 de tampon pour 1728×1117 de contentRect, avec `scale 2.00`.
      ATTENDU : `variations 0`.
      SI ÇA RATE : ScreenCaptureKit publie le `contentRect` en POINTS et le tampon en
      PIXELS ; le rapport entre les deux doit être exactement `scale`. Une variation
      en cours de segment signale un changement de résolution ou une bascule d'espace.

- [ ] **1.4** Chaque écran ferme son propre flux, avant que la session publie
      FAIRE : rien de plus, la session vient d'être fermée.
      REGARDER : le journal, juste après `⌃⌥F`, **en lisant l'ORDRE des lignes**.
      ATTENDU : une ligne `flux fermé sur display N` **par écran branché**, chacune
      suivie de son bloc `FLUX`.
      ATTENDU : puis `N fichier(s) de capture supprimé(s)`.
      ATTENDU : et le bloc `FIN DE SESSION` **en dernier**.
      SI ÇA RATE : si `FIN DE SESSION` s'imprime AVANT les « flux fermé », la
      publication a gagné la course sur la fermeture des flux. Le symptôme visible
      est un `.mov` qui reste ; le vrai dégât est que l'extraction n'a rien à ouvrir
      et que toutes les marques retombent sur la capture au relâchement. Le lot
      entier serait inopérant, en silence.
      *Il n'y a de bloc `EXTRACTION` que s'il y a des marques : sans marque, il n'y a
      rien à extraire, et l'imprimer dirait « 0 sur 0 ». Le bloc apparaît à partir du
      test 3.2.*

- [ ] **1.5** Aucune vidéo ne survit à la publication
      FAIRE : dans un terminal, `ls $TMPDIR/regarde*/ 2>/dev/null`.
      REGARDER : la liste des fichiers.
      ATTENDU : **aucun fichier `.mov`**.
      SI ÇA RATE : un `.mov` qui reste est un enregistrement de votre écran qui
      survit à la session. L'ADR-0020 borne sa vie à celle du besoin qui l'a créé.

## 2. Ne rien casser — bloquant

- [ ] **2.1** Le mode éclair fonctionne toujours
      FAIRE : depuis `~/DEV/PERSO/AI-DEV/TOOLS/regarde/app`, lancer
      `./Tools/lot2-eclair.sh`
      REGARDER : la sortie du script.
      ATTENDU : le dossier publié est complet, sans erreur.
      SI ÇA RATE : c'est le mode **majoritaire**, et le seul chemin qu'un
      développement centré session ne traverse jamais. C'est là que les défauts se
      cachent — celui du lot 2 y est resté une journée entière.

- [ ] **2.2** Le livrable du lot 2 passe encore
      FAIRE : `./Tools/lot2-livrable.sh`
      REGARDER : les trois lignes de verdict en fin de script.
      ATTENDU : `✓ 6 marques`, `✓ 2 vues d'ensemble`, `✓ aucun fichier inattendu`.

- [ ] **2.3** La gravure est toujours au bon endroit
      FAIRE : `./Tools/lot2-cible.sh`
      REGARDER : le verdict du script.
      ATTENDU : le contrôle d'encre passe.

- [ ] **2.4** `⌘Z` reste à l'application testée
      FAIRE : ouvrir une session, aller dans un éditeur de texte, taper quelques
      lettres, frapper `⌘Z` **sans modificateur**.
      REGARDER : l'éditeur de texte.
      ATTENDU : l'éditeur annule votre frappe.
      SI ÇA RATE : c'est le raccourci le plus utilisé de macOS, et Regarde l'a volé
      une fois. Si l'éditeur ne réagit pas, notez-le comme bloquant.

- [ ] **2.5** Un verrouillage d'écran suspend proprement
      FAIRE : ouvrir une session, tracer une marque, verrouiller l'écran (`⌃⌘Q`),
      déverrouiller.
      REGARDER : le journal.
      ATTENDU : une ligne `⚠ suspension forcée depuis recording — …`.
      ATTENDU : une ligne `1 marque(s) abandonnée(s)`.
      ATTENDU : ensuite, `⌥⌘` arme de nouveau normalement dans l'application testée.
      SI ÇA RATE : si `⌥⌘` n'arme plus **nulle part** après le déverrouillage, la
      fenêtre cible est restée figée sur la session morte. C'est un défaut corrigé à
      l'ouverture du lot ; s'il revient, il est bloquant.

## 3. L'instant exact — le cœur du lot

- [ ] **3.1** Poser huit marques pendant que l'écran bouge
      FAIRE : témoin en mode compteur, plein écran. Ouvrir une session (`⌃⌥S`), puis
      tracer **huit marques** avec `⌥⌘ + glisser` pendant que le compteur défile.
      Fermer (`⌃⌥F`).
      REGARDER : rien pour l'instant — les tests suivants dépouillent.
      ATTENDU : huit marques numérotées de 1 à 8 dans le bloc `MARQUES`.

- [ ] **3.2** Les images viennent du fichier, pas de la capture de secours
      REGARDER : dans le journal, le bloc `EXTRACTION`.
      ATTENDU : `depuis le fichier   8`.
      ATTENDU : `servies par le filet   0`.
      SI ÇA RATE : une marque « servie par le filet » n'est pas une panne : son image
      vient d'une capture prise au **relâchement**, donc une à deux secondes après
      l'instant que vous désigniez. Le journal nomme le motif marque par marque,
      juste au-dessus du bloc.

- [ ] **3.3** L'image extraite est celle du bon instant
      FAIRE : cette mesure n'a de sens que sur un écran qui BOUGE. Reprenez la session
      du 3.1, témoin en mode compteur animé.
      REGARDER : dans le bloc `EXTRACTION`, la ligne `pire écart demandé/obtenu`.
      ATTENDU : une valeur **inférieure à 67 ms**.
      ATTENDU : la ligne précise `sur N marque(s) à l'écran animé`, avec N égal au
      nombre de marques tracées.
      SI ÇA RATE : 67 ms est l'intervalle entre deux images encodées à 15 fps. Au-delà,
      le générateur a rendu une autre image que celle demandée. Si la ligne dit
      `sans objet — aucune marque sur un écran animé`, l'écran ne bougeait pas assez :
      la mesure n'a pas eu lieu, ce n'est ni un succès ni un échec.

- [ ] **3.4** La réglette est lisible dans chaque image
      FAIRE : pour chaque image, lancer
      `./.build/debug/Regarde --lire-reglette ~/Regarde/sessions/DERNIÈRE/frames/marque-01.png`
      (remplacez `DERNIÈRE` par le dossier le plus récent).
      REGARDER : la sortie de la commande.
      ATTENDU : un `V` (un nombre), un `module` proche de **64**, et `faibles 0`.
      SI ÇA RATE : la sortie dit `refus` suivi du motif. `localisateur absent` veut
      dire que la réglette n'est pas dans l'image — c'est un problème de cadrage, pas
      de temps. `CRC` veut dire qu'elle est là mais abîmée.

- [ ] **3.5** Le numéro lu correspond à l'instant désigné — **le test qui décide du lot**
      FAIRE : `./Tools/lot3-c11.sh` et suivre ses instructions.
      REGARDER : le verdict en fin de script.
      ATTENDU : aucun refus opposable, et une latence dans la plage annoncée.
      SI ÇA RATE : le script nomme lequel de ses quatre refus s'applique. Il ne rend
      **pas** de verdict C11 sur cette chaîne — c'est voulu, et c'est écrit dans sa
      sortie.

- [ ] **3.6** Sur un écran immobile, l'image reste juste et le journal le dit
      FAIRE : annoter une fenêtre vraiment figée — le Finder, ou une image ouverte dans
      Aperçu. Pas un navigateur : ils recomposent en continu. Ouvrir une session,
      tracer trois marques, fermer.
      REGARDER : le bloc `EXTRACTION` et le bloc `FLUX` de l'écran annoté.
      ATTENDU : `depuis le fichier   3` — l'écran immobile n'empêche pas l'extraction.
      ATTENDU : dans le bloc `FLUX`, `autres statuts` **non nul** : c'est la preuve que
      l'écran était bien au repos.
      ATTENDU : `1 frame(s) au plan` sur les trois marques — pas de burst sur un écran
      qui ne bouge pas.
      SI ÇA RATE : une ligne `âge de l'image, écran immobile` de plusieurs centaines de
      millisecondes n'est **pas** un défaut : l'encodeur n'écrit que ce qui change, et
      l'image d'il y a 600 ms est exacte puisque rien n'avait bougé depuis. De même,
      `obtenues au second essai` est normal ici. Le vrai défaut serait
      `servies par le filet` non nul : ni le passage exact ni le repli n'auraient
      trouvé d'image.

- [ ] **3.7** La part de l'écran qui change est mesurée dans la bonne unité
      FAIRE : n'importe quelle session sur un Mac à écran Retina (facteur 2×).
      REGARDER : dans chaque bloc `FLUX`, la ligne `surface salie`.
      ATTENDU : `max` **inférieur ou égal à 1.000** sur tous les écrans.
      ATTENDU : **aucune** mention `← IMPOSSIBLE : recouvrement ou unités`.
      SI ÇA RATE : une part de surface ne peut pas dépasser 1. Une valeur de 4.000 sur
      un écran 2× et de 1.000 sur un écran 1× dans la même session veut dire que les
      rectangles salis, qui arrivent en pixels, sont divisés par une surface en points.

## 4. Le burst — plusieurs images quand l'écran bouge

- [ ] **4.1** Un écran animé déclenche trois images
      FAIRE : témoin en mode compteur animé, une session, **une seule** marque, fermer.
      REGARDER : dans le journal, la ligne `marque 1 · N frame(s) au plan`.
      ATTENDU : `3 frame(s) au plan`.

- [ ] **4.2** Un écran immobile n'en déclenche qu'une
      FAIRE : sur une fenêtre figée, une session, une marque, fermer.
      REGARDER : la même ligne.
      ATTENDU : `1 frame(s) au plan`.

- [ ] **4.3** Un curseur qui clignote ne suffit pas à déclencher un burst
      FAIRE : ouvrir un terminal vide où **seul le curseur clignote**, rien d'autre.
      Une session, une marque dessus, fermer.
      REGARDER : la même ligne.
      ATTENDU : `1 frame(s) au plan`.
      SI ÇA RATE : si vous obtenez 3, le double critère ne fonctionne pas — un curseur
      change souvent mais sur une surface dérisoire. Chaque marque coûterait alors
      trois fois son prix pour rien.

- [ ] **4.4** Une marque juste avant la fin perd une image, et le dit
      FAIRE : témoin animé, une session, tracer une marque puis fermer **dans la
      seconde**.
      REGARDER : la ligne `burst — N frame(s) obtenues sur M demandée(s)`.
      ATTENDU : `N` est inférieur à `M`.
      SI ÇA RATE : l'écart est le nombre d'images demandées hors des bornes du
      segment. Qu'il y en ait est normal ici ; qu'on ne le sache pas ne l'est pas.

## 5. Les écrans qu'on écarte

- [ ] **5.1** Un écran en recopie vidéo est écarté, et nommé
      FAIRE : Réglages → Moniteurs → mettre l'écran externe en **recopie** de
      l'interne.
      REGARDER : le journal.
      ATTENDU : une ligne `⚠ écran N écarté — écran en recopie vidéo — il duplique un
      autre écran`.

- [ ] **5.2** On ne peut pas tracer sur un écran écarté
      FAIRE : tenter un `⌥⌘ + glisser` sur l'écran en recopie.
      REGARDER : l'écran, et le journal.
      ATTENDU : **aucun trait ne se dessine**.
      ATTENDU : le HUD affiche « Écran non annotable » avec un conseil.
      ATTENDU : le journal écrit `⚠ geste refusé sur l'écran N`.
      SI ÇA RATE : si le trait se dessine, c'est pire qu'un refus — le numéro
      s'incrémente, vous croyez la marque posée, et le dossier sort sans son image ou
      avec celle d'un autre écran.

- [ ] **5.3** Revenir en mode étendu suffit à réactiver l'écran
      FAIRE : Réglages → Moniteurs → repasser en affichage étendu.
      REGARDER : tracer une marque sur l'écran externe.
      ATTENDU : le trait se dessine, sans avoir eu à relancer Regarde.

- [ ] **5.4** Un écran pivoté est écarté — *seulement si votre moniteur pivote*
      FAIRE : Réglages → Moniteurs → rotation **90°**.
      REGARDER : le journal.
      ATTENDU : `écran N écarté — écran en rotation`.
      SI ÇA RATE : en rotation **180°** l'écran doit rester annotable — largeur et
      hauteur ne sont pas inversées, et la conversion y est juste. Le refuser serait
      refuser une fois de trop.

## 6. Ce qui ne doit pas se retrouver dans les images

- [ ] **6.1** Une application sensible ouverte en cours de session est exclue
      FAIRE : ouvrir une session, puis **lancer** 1Password ou Trousseau d'accès.
      REGARDER : le journal.
      ATTENDU : une ligne `com.xxx lancée et exclue — filtre reconstruit`.
      SI ÇA RATE : sans ce mécanisme, l'exclusion ne vaudrait que pour ce qui tournait
      déjà au démarrage — et un gestionnaire de mots de passe s'ouvre précisément
      pendant qu'on teste ce à quoi il donne accès.

- [ ] **6.2** Le calque de Regarde n'est pas dans les images
      FAIRE : ouvrir n'importe quelle image publiée dans Aperçu.
      REGARDER : l'image, en cherchant du rouge vermillon, un badge numéroté, ou le HUD.
      ATTENDU : **aucun pixel** de tout cela, en dehors de la gravure voulue.

- [ ] **6.3** Les fichiers de travail sont fermés aux autres comptes
      FAIRE : `ls -la $TMPDIR/regarde* 2>/dev/null`.
      REGARDER : la colonne des permissions.
      ATTENDU : répertoires en `drwx------`, fichiers en `-rw-------`.

- [ ] **6.4** Une session tuée ne laisse pas de vidéo traîner
      FAIRE : ouvrir une session, puis `pkill -9 Regarde` en pleine session.
      Relancer l'application, ouvrir une nouvelle session.
      REGARDER : le journal, au démarrage de la nouvelle session.
      ATTENDU : une ligne `N répertoire(s) de session purgé(s)`.
      SI ÇA RATE : un `.mov` orphelin est un enregistrement de votre écran qui survit
      indéfiniment.

## 7. Débrancher un écran en pleine session

- [ ] **7.1** Dérouler le scénario
      FAIRE : `./Tools/lot3-debranchement.sh` et suivre ses instructions — deux
      écrans, une marque sur chacun, puis **débrancher physiquement** l'externe sans
      fermer la session.
      REGARDER : la sortie du script.
      ATTENDU : ses trois contrôles passent.

- [ ] **7.2** Le segment de l'écran parti est fermé tout de suite
      REGARDER : le journal, au moment du débranchement.
      ATTENDU : `⚠ display N débranché — finalisation immédiate de son segment`.
      SI ÇA RATE : fermé plus tard, au milieu des autres, son échec emporterait les
      segments d'écrans qui ont tout enregistré.

- [ ] **7.3** La session continue sur l'écran restant
      FAIRE : après le débranchement, tracer encore une marque sur l'écran interne,
      puis fermer.
      REGARDER : le journal.
      ATTENDU : la marque est acceptée, et la session se ferme normalement.

- [ ] **7.4** Les marques de l'écran débranché ont leur image
      FAIRE : ouvrir le dossier de la session.
      REGARDER : les fichiers `marque-NN.png`.
      ATTENDU : **toutes** les marques ont leur image, y compris celles de l'écran
      parti.
      SI ÇA RATE : c'est un point du critère du lot. Le motif est dans le journal,
      marque par marque.

## 8. Les budgets — l'outil ne doit pas gêner

- [ ] **8.1** Lancer le relevé
      FAIRE : `./Tools/lot3-budgets.sh` avec **deux écrans branchés**, puis suivre ses
      instructions (une session de dix minutes avec du mouvement à l'écran).
      REGARDER : le tableau final du script.
      ATTENDU : le script accepte de démarrer — s'il refuse, il dit pourquoi.

- [ ] **8.2** La mémoire tient
      REGARDER : la ligne `RSS crête`.
      ATTENDU : **sous 200 MiB**.
      SI ÇA RATE : l'anneau d'images pèse environ 120 MiB par écran. Un dépassement à
      deux écrans veut dire qu'il n'est pas vidé.

- [ ] **8.3** Le processeur tient
      REGARDER : la ligne `CPU moyen`.
      ATTENDU : **sous 3 %**.

- [ ] **8.4** Le disque tient
      REGARDER : la ligne `disque / 10 min`.
      ATTENDU : **sous 500 MiB**.

- [ ] **8.5** La fin de session est rapide
      REGARDER : dans le bloc `EXTRACTION`, la ligne `durée`.
      ATTENDU : **sous 3 secondes**.
      SI ÇA RATE : au-delà, le gain de temps que l'outil promet est déjà mangé par
      l'attente en fin de session.

- [ ] **8.6** Rien ne plante sur une longue session
      FAIRE : laisser tourner une session **vingt minutes** sur du contenu très animé,
      en traçant de temps en temps.
      REGARDER : l'application est-elle toujours là.
      ATTENDU : aucun plantage.
      SI ÇA RATE : c'est le bug B2. Il n'est pas reproductible à la demande — sa
      fréquence dépend de l'activité de l'écran — et vingt minutes sous charge est le
      seul filet qu'on ait.

## 9. C3b — la dette du lot 0

- [ ] **9.1** Lancer la campagne de mesure
      FAIRE : `./Tools/lot3-temoin.sh --duree 60` témoin en plein écran natif.
      REGARDER : la sortie du script.
      ATTENDU : il va jusqu'au bout et dépose ses fichiers.

- [ ] **9.2** Les relevés sont comparables entre eux
      REGARDER : le récapitulatif final, colonne `charge`.
      ATTENDU : **la même valeur** sur tous les relevés.
      SI ÇA RATE : deux relevés à charge différente ne se comparent pas. Si la valeur
      change, la page a été rechargée en cours de campagne.

- [ ] **9.3** Le calque ne coûte rien au repos, et peu pendant le tracé
      REGARDER : les écarts publiés pour l'état 2 et l'état 3.
      ATTENDU : état 2 **sous 1 %**, état 3 **sous 5 %**.

- [ ] **9.4** La machine peinait vraiment pendant la mesure
      REGARDER : le champ `chargeInsuffisante`.
      ATTENDU : **faux** sur tous les relevés.
      SI ÇA RATE : le calibrage a atteint sa butée sans faire peiner le GPU. Une
      couche de composition supplémentaire ne coûte alors rien de mesurable, et C3b
      serait déclaré bon sans avoir été mesuré.

- [ ] **9.5** La cadence reste dans la fenêtre pendant les relevés
      REGARDER : la cadence effective de chaque relevé, rapportée au rafraîchissement
      natif.
      ATTENDU : entre **70 et 90 %** du natif, pendant le relevé et pas seulement au
      calibrage.
      SI ÇA RATE : un relevé du 21 août est sorti à 58 %. L'hypothèse consignée est
      thermique — le calibrage converge sur une seconde, le relevé dure soixante fois
      plus. Si vous le revoyez, notez le rafraîchissement natif et le relevé apparié
      pris sans réglette : ce sont les deux chiffres qui manquent pour trancher.
