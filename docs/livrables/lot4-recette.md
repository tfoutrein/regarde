# Recette du lot 4 — tests manuels

Ce que vous validez : **la boucle complète, du geste au diff** — la session se
publie dans le bon projet, la phrase attend au presse-papiers sans avoir rien
écrasé, le ⏎ la porte à l'agent, et rien de ce que les lots 2 et 3 ont livré ne
s'est cassé en route.

Comptez **35 à 45 minutes**. La section 1 est bloquante.

> **Chaque test se lit en quatre temps** : ce que vous **faites**, où vous
> **regardez**, ce que vous devez **voir**, et quoi faire **si ça rate**. Si un test
> vous demande de regarder au mauvais endroit, ou décrit quelque chose qui n'existe
> pas, c'est le test qui est faux — notez-le, il vaut un défaut.

---

## Avant de commencer

**Deux terminaux.** Le journal se lance **avant** l'application :

- Terminal 1 : `tail -F ~/Regarde/journal.txt`
- Terminal 2 : `cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app && ./Tools/build-app.sh`

**Un projet d'essai**, jetable et à vous :

- `mkdir -p ~/recette-lot4 && git -C ~/recette-lot4 init -q && echo test > ~/recette-lot4/lisez-moi.txt`
- puis **un shell qui y reste** : ouvrez un onglet de terminal et `cd ~/recette-lot4`

Ce lot ne mesure aucune cadence : le papier peint vidéo et les écrans à dégâts
fantômes du lot 3 ne gênent pas ici.

---

## 1. Ne rien casser — bloquante

- [ ] **1.1** Les neuf suites d'autotest sont vertes
      FAIRE : `cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app && for f in --capture-test --marks-test --reglette-test --icone-test --geometry-test --append-test --render-test --publier-test --projet-test --boucle-test --papiers-test; do ./.build/debug/Regarde $f | tail -1; done`
      REGARDER : la dernière ligne de chaque suite.
      ATTENDU : **0 échouée** partout.
      SI ÇA RATE : la suite en échec nomme ses vérifications rouges — c'est un défaut
      avant même de commencer, rien d'autre ne se teste par-dessus.

- [ ] **1.2** Le livrable du lot 2 tient encore
      FAIRE : `./Tools/lot2-livrable.sh` et suivre ses instructions.
      REGARDER : sa sortie.
      ATTENDU : ses contrôles passent — marques multi-outils, deux écrans, aucun
      pixel du calque dans les images.
      SI ÇA RATE : une régression du socle — elle prime sur tout le reste du cahier.

- [ ] **1.3** Le livrable du lot 3 tient encore
      FAIRE : une session courte sur du contenu animé (une vidéo, un défilement),
      deux marques ⌥⌘, fermer par ⌃⌥F.
      REGARDER : le bloc `EXTRACTION` du journal.
      ATTENDU : `depuis le fichier 2` et `servies par le filet 0`.
      SI ÇA RATE : les images reviennent au relâchement — c'est B1, le défaut que le
      lot 3 a tué. Bloquant.

## 2. Le mode éclair — sa section propre

Le mode majoritaire n'ouvre ni session, ni sélecteur, ni publication projet : sa
sobriété **est** le comportement à valider.

- [ ] **2.1** Un éclair reste un éclair
      FAIRE : hors session, un `⌥⌘ + glisser` sur une fenêtre suivie.
      REGARDER : le journal, et votre presse-papiers.
      ATTENDU : un bloc `ÉCLAIR` avec son dossier.
      ATTENDU : **aucun** bloc `PUBLICATION PROJET`, **aucun** sélecteur ouvert.
      ATTENDU : le presse-papiers n'a **pas** changé — collez quelque part pour le
      prouver.
      SI ÇA RATE : un éclair qui publie dans un projet ou touche le presse-papiers a
      hérité du chemin de session — c'est une fuite de la boucle de S53.

- [ ] **2.2** L'éclair ne contamine pas la session suivante
      FAIRE : un éclair, puis ⌃⌥S, une marque, ⌃⌥F.
      REGARDER : le bloc `MARQUES` de la session.
      ATTENDU : **une seule** marque — celle de la session, pas celle de l'éclair.

## 3. Le sélecteur et les trois états

- [ ] **3.1** Les trois teintes sont indiscutables
      FAIRE : `./.build/debug/Regarde --projet-test`
      REGARDER : le bloc « Les trois teintes, mesurées sur captures ».
      ATTENDU : les trois paires à **ΔE*ab ≥ 20** — c'est le seuil n°8 de
      `lot4-seuils.md`, mesuré sur pixels rendus, pas sur les constantes.
      SI ÇA RATE : le test refuse de conclure en nommant la paire illisible — R2 dit
      pourquoi : trois états qui se ressemblent redeviennent un réflexe.

- [ ] **3.2** Le sélecteur s'ouvre à l'arming, candidats et motifs
      FAIRE : avec votre shell dans `~/recette-lot4`, ⌃⌥S.
      REGARDER : l'écran, et le bloc `PROJET` du journal.
      ATTENDU : le panneau « Projet de la session » s'ouvre, `~/recette-lot4` dans la
      liste, chaque candidat **avec son motif** (« cwd de zsh (pid … » ou « session
      d'agent vivante… »).
      ATTENDU : au journal, une ligne `projet — certain|probable|ambigu` avec le
      motif complet.
      SI ÇA RATE : un candidat sans motif est une assertion, pas une détection.

- [ ] **3.3** ⏎ confirme, et le journal le dit
      FAIRE : dans le panneau, ↑↓ jusqu'à `~/recette-lot4`, puis ⏎. Fermez la session
      (⌃⌥F) sans marque.
      REGARDER : le journal.
      ATTENDU : `projet confirmé — /Users/…/recette-lot4`.
      ATTENDU : sans marque, **aucune** publication — une session vide ne fabrique
      pas de feedback.

- [ ] **3.4** Échap laisse ambigu, et l'ambigu ne publie pas
      FAIRE : ⌃⌥S, Échap sur le panneau, une marque ⌥⌘, ⌃⌥F.
      REGARDER : le journal.
      ATTENDU : `projet laissé ambigu — aucun candidat confirmé`, puis à la
      publication `⚠ projet ambigu — rapport non publié dans un projet, dossier
      ~/Regarde seul`.
      ATTENDU : **aucun** `.regarde/` créé nulle part.
      SI ÇA RATE : publier sur un verdict ambigu est LE bug que les pastilles
      existent pour empêcher — un rapport dans le mauvais dépôt se découvre dans une
      pull request, des jours plus tard.

- [ ] **3.5** Plusieurs projets crédibles — jamais tranché
      FAIRE : ouvrez un second shell dans un AUTRE dossier-projet (par exemple
      `mkdir -p ~/recette-lot4-bis && cd ~/recette-lot4-bis`), puis ⌃⌥S.
      REGARDER : le bloc `PROJET`.
      ATTENDU : `état ambigu` avec les deux candidats listés — le produit REFUSE de
      deviner entre deux répertoires crédibles. Échap, ⌃⌥F, fermez le shell bis.

## 4. La publication dans le projet

- [ ] **4.1** La boucle complète, du raccourci au dossier
      FAIRE : ⌃⌥S, ⏎ sur `~/recette-lot4` dans le sélecteur, **deux marques** ⌥⌘,
      ⌃⌥F.
      REGARDER : le journal, à la fin de la publication.
      ATTENDU : un bloc `PUBLICATION PROJET` avec `projet`, `feedback #1 — 0001-…`,
      `presse-papiers  phrase déposée, sauvegarde armée à 60 s`, `porteur  ⏎ armé
      pour 8 s`.
      ATTENDU : `ls ~/recette-lot4/.regarde/sessions/` montre un dossier `0001-…`
      avec `manifest.json`, `report.md`, `paste-web.md` et `frames/crop-01.png`,
      `crop-02.png`.

- [ ] **4.2** git ne voit que ce qui se versionne
      FAIRE : `git -C ~/recette-lot4 status --porcelain -uall`
      REGARDER : la liste, ligne à ligne.
      ATTENDU : **exactement quatre** chemins — `.regarde/.gitignore`,
      `.regarde/index.jsonl`, `.regarde/sessions/0001-…/manifest.json`,
      `.regarde/sessions/0001-…/report.md`. Ni frames, ni paste-web, ni state.
      SI ÇA RATE : un fichier de trop ici finira dans un commit d'un dépôt client —
      c'est le critère du lot pris au mot.

- [ ] **4.3** Le rapport a ses six sections
      FAIRE : `./Tools/lot4-conformite.sh ~/recette-lot4/.regarde/sessions/*/report.md`
      REGARDER : sa sortie.
      ATTENDU : les six sections cochées, `empreinte non exigée — ce n'est pas le
      rapport de référence`, verdict `conforme`.
      REGARDER ensuite le rapport lui-même dans un éditeur : le Contexte porte ses
      **sept lignes**, la détection avec son motif complet, le git avec branche et
      sha.

- [ ] **4.4** Le numéro s'incrémente sous verrou
      FAIRE : une seconde session publiée dans le même projet (⌃⌥S, ⏎, une marque,
      ⌃⌥F).
      REGARDER : le bloc `PUBLICATION PROJET`, et `cat ~/recette-lot4/.regarde/index.jsonl`
      ATTENDU : `feedback #2`, et deux lignes d'index, numéros 1 et 2, chacune JSON
      entière.

- [ ] **4.5** L'état vit hors de git
      FAIRE : `cat ~/recette-lot4/.regarde/state.jsonl`
      ATTENDU : une ligne `"event":"published"` par session publiée — et ce fichier
      n'apparaissait **pas** au 4.2 : il est d'état, pas de contenu.

## 5. Le presse-papiers et le dernier mètre

- [ ] **5.1** La phrase du § 9.10, au caractère
      FAIRE : après le 4.1, collez le presse-papiers dans un éditeur de texte.
      ATTENDU : **une seule ligne** : `Lis le feedback #1 avec regarde (get_feedback
      number=1) puis applique les corrections. Si l'outil n'est pas disponible, lis
      /Users/…/report.md`.
      ATTENDU : la clause `puis applique les corrections` — sans elle l'agent lit et
      résume quand vous voulez qu'il code.

- [ ] **5.2** Un contenu riche revient avec ses variantes
      FAIRE : copiez un contenu RICHE (un paragraphe mis en forme depuis Notes ou
      une page web, avec gras et lien). Puis une session publiée (⌃⌥S, ⏎, une
      marque, ⌃⌥F). Attendez **60 secondes sans rien copier**.
      REGARDER : le journal à l'échéance, puis collez dans Notes.
      ATTENDU : un bloc `PRESSE-PAPIERS RESTAURÉ` — items, types vus, types
      restaurés, et **tout écart nommé**.
      ATTENDU : le collage rend votre contenu riche **avec sa mise en forme**, pas
      une version texte appauvrie.
      SI ÇA RATE : une restauration au premier type venu perd les variantes — c'est
      le défaut précis que « item par item et type par type » corrige.

- [ ] **5.3** Ce que vous copiez entre-temps est sacré
      FAIRE : rejouez le 5.2, mais copiez **autre chose** dans les 60 secondes.
      REGARDER : le journal à l'échéance.
      ATTENDU : `presse-papiers réécrit entre-temps — restauration abandonnée`, et
      votre nouveau contenu **intact**.
      SI ÇA RATE : restaurer par-dessus votre nouvelle copie serait le bug inverse de
      celui du 5.2.

- [ ] **5.4** Le porteur du ⏎, dans sa fenêtre de grâce
      FAIRE : un agent CLI vivant quelque part (une session Claude Code ouverte
      suffit). Session publiée, puis — dans les 8 secondes du HUD « ⏎ Envoyer à
      l'agent » — pressez ⏎.
      REGARDER : le journal, et la fenêtre de l'agent.
      ATTENDU : l'application de l'agent passe au premier plan, et l'une de ces deux
      lignes : `porteur — phrase injectée par AX` ou `porteur — repli ⌘V
      synthétique`. C'est du best-effort : l'une OU l'autre, et au pire la phrase
      reste au presse-papiers — jamais d'erreur bruyante.
      ATTENDU : un ⌘⏎ pendant la grâce passe à l'application, lui.

- [ ] **5.5** Hors de la grâce, le ⏎ est intouchable
      FAIRE : après les 8 secondes, tapez du texte avec des ⏎ dans n'importe quel
      éditeur.
      ATTENDU : chaque ⏎ fait exactement ce qu'il a toujours fait.
      SI ÇA RATE : une touche volée hors de sa fenêtre est le défaut n°11 de la
      recette du lot 2 (le ⌘Z) — le critère du plan dit « aucun ⏎ avalé hors de la
      fenêtre de grâce ».

- [ ] **5.6** L'historique rattrape une phrase perdue
      FAIRE : copiez n'importe quoi (la phrase est perdue), puis barre de menus →
      icône Regarde → **Feedbacks récents** → `#2 — recette-lot4 — copier la phrase`.
      REGARDER : le journal, puis collez.
      ATTENDU : `phrase recopiée depuis l'historique`, et la phrase du #2 revient.
      ATTENDU : l'historique montre les **trois** derniers au plus.

## 6. Les métriques et le GO/NO-GO

- [ ] **6.1** Le repli se déclare en deux clics
      FAIRE : barre de menus → **J'ai préféré une capture manuelle**.
      REGARDER : le HUD, le journal, et
      `tail -2 ~/Library/Application\ Support/Regarde/metrics.jsonl`
      ATTENDU : HUD « Repli noté », journal `repli déclaré — capture manuelle
      préférée à une session`, et une ligne `"event":"repli"` horodatée.

- [ ] **6.2** Le verdict d'un diff se persiste depuis l'historique
      FAIRE : Feedbacks récents → `verdict du #2…` → **diff pertinent**.
      REGARDER : le journal et les métriques.
      ATTENDU : `verdict persisté — #2 : pertinent`, et une ligne
      `"event":"verdict"`.

- [ ] **6.3** L'instrument refuse de conclure — et c'est le bon comportement
      FAIRE : `./Tools/lot4-gonogo.sh`
      REGARDER : sa sortie entière.
      ATTENDU : les **quatre nombres** imprimés face à leurs seuils, PUIS `LE SCRIPT
      REFUSE DE CONCLURE` avec ses portes nommées — moins de dix jours de relevé,
      moins de vingt injections, pas assez de verdicts. Aujourd'hui, le refus est la
      seule conclusion honnête : le GO/NO-GO se joue sur dix jours d'usage réel,
      pas sur une recette.

## 7. Les cinq environnements — la matière du passage

Le critère du lot : projet correct sur dix sessions dans cinq environnements, ou
**affiché ambigu quand il l'est** — et le seuil n°9 est impitoyable : zéro
« certain » erroné. Un « ambigu » sur une situation ambiguë est un succès.

Pour chaque environnement : un shell dans un projet, ⌃⌥S, lire le bloc `PROJET`,
Échap, ⌃⌥F.

- [ ] **7.1** Warp, plusieurs onglets sur plusieurs projets
      ATTENDU : tous les cwd en candidats ; état `ambigu` si plusieurs crédibles.

- [ ] **7.2** Terminal ou iTerm
      ATTENDU : le cwd du shell en candidat, motif nommé.

- [ ] **7.3** tmux (si vous l'utilisez)
      ATTENDU : les panes sont des shells comme les autres — leurs cwd apparaissent.
      SI ÇA RATE : notez le motif absent — les descendants de tmux sont le cas que
      S52 cible avec « tous les descendants du terminal ».

- [ ] **7.4** Un IDE (VS Code, Cursor) avec son terminal intégré
      ATTENDU : le shell intégré compte comme un shell ; si l'agent de l'IDE tourne,
      il compte comme provider.

- [ ] **7.5** Un dépôt sous ~/Documents
      FAIRE : `mkdir -p ~/Documents/recette-tcc && git -C ~/Documents/recette-tcc init -q`,
      un shell dedans, session publiée (⏎ au sélecteur, une marque, ⌃⌥F).
      REGARDER : le journal — et toute invite système.
      ATTENDU : la publication aboutit. Si macOS présente une invite « fichiers et
      dossiers », elle est au nom de **Regarde** — notez-la : c'est le comportement
      TCC que le lot 6 devra documenter pour le sidecar.
      SI ÇA RATE : `publication projet — …` au journal avec l'erreur nommée — un
      refus TCC silencieux serait le vrai défaut.

---

Défauts trouvés : les corriger, puis étiqueter `v0.4.1` — c'est le chemin de S57.
