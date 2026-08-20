# Recette du lot 2 — tests manuels

Ce que vous validez : **tracer sur une application qui tourne, sans la perturber, et obtenir des
images gravées.** Ni voix, ni rapport texte, ni MCP — ce sont les lots 3 à 5.

Comptez **35 à 45 minutes**. Les sections 1 et 2 sont bloquantes.

> **Cette recette a été relue contre le code.** Sa première version comptait 43 tests faux ou
> infaisables — des lignes de journal illisibles au moment où on les demandait, des comportements
> décrits à l'envers, des gestes sans rien à observer. Chaque test ci-dessous nomme ce qu'on
> regarde et où.

---

## Avant de commencer

```bash
# 1. Le journal, dans un terminal — AVANT de lancer l'application
tail -F ~/Regarde/journal.txt

# 2. L'application, dans un autre terminal
cd ~/DEV/PERSO/AI-DEV/TOOLS/regarde/app && ./Tools/build-app.sh --run
```

`-F` majuscule, et lancé **avant** : le journal est effacé et recréé à chaque démarrage, un `-f`
minuscule resterait accroché au fichier supprimé et n'afficherait plus rien, en silence.

Prenez une application de test **qui bouge** et **qui a une vraie fenêtre** : une page web animée,
une vidéo, un terminal qui défile. Ni le Bureau ni une fenêtre figée.

**Deux règles à connaître avant tout**, sans quoi la moitié des tests échouera sans raison
apparente :

- `⌥⌘` n'arme **que si le curseur est dans la fenêtre au premier plan**. Curseur sur le bureau ou
  sur le terminal du journal, il ne se passe rien — c'est voulu.
- Hors session, une observation est **publiée automatiquement 0,8 s** après le relâchement de
  `⌥⌘`, et le modèle est vidé. Plusieurs tests exigent de **ne pas relâcher** entre deux gestes.

Votre clavier est détecté comme **French**. Trois familles de touches, trois règles :

| Raccourci | Touche à presser | Résolution |
|---|---|---|
| `⌃⌥S` `⌃⌥F` `⌃⌥M` `⌃⌥L` | les touches marquées S, F, M, L | par caractère |
| `⌥⌘F` `⌥⌘C` `⌥⌘P` `⌥⌘S` | les touches marquées F, C, P, S | par caractère |
| `⌥⌘Z` | la touche marquée **Z** — le W du QWERTY | par caractère |
| `⌥⌘ + 1..6` | les **six premières touches de la rangée du haut**, sans `⇧` | par **position physique** |

Sur un clavier « Français – PC » ce sont `& é " ' ( -` ; sur le clavier « Français » d'Apple, la
sixième porte `§`. C'est la **position** qui compte, pas le caractère imprimé. Dites-moi si c'est
pénible à l'usage — c'est le point le plus discutable du lot.

---

## 1. Le socle — bloquant

- [ ] **1.1** L'icône apparaît dans la barre de menus.
      *Si elle manque : `grep -A 12 "Barre de menus" ~/Regarde/journal.txt`. La section donne
      `visible`, la position, et le cas échéant `⚠ L'ÉLÉMENT EST SOUS L'ENCOCHE`. Le remède est de
      libérer une place dans la barre, pas de débrancher un écran.*
- [ ] **1.2** Menu → **Diagnostic…** : les quatre lignes **sans l'étiquette « facultatif »** portent
      une pastille verte, et le bandeau du haut affiche **« tout est en place »**.
      *Des lignes orange « facultatif » sont normales : « Microphone — jamais demandé » (lot 5) et
      « Périphériques d'entrée audio » si Teams ou Zoom est installé.*
- [ ] **1.3** `grep "tap démarré" ~/Regarde/journal.txt` renvoie
      `tap démarré — ⌥⌘ + glisser trace, ⌃⌥S ouvre une session`.
      *Si c'est `⚠ tap non démarré`, arrêtez-vous : rien de la suite n'a de sens.*
- [ ] **1.4** `grep -A 5 "^Raccourcis" ~/Regarde/journal.txt` liste les quatre raccourcis, chacun
      avec un `✓` et un code, sur le modèle `✓ ⌃⌥S — ouvrir une session  (code 1)`.
      *Un `✗` nomme sa raison : touche introuvable, ou déjà prise par une autre application.*
- [ ] **1.5** `grep "cible suivie" ~/Regarde/journal.txt` nomme l'application au premier plan.
      Passez d'une application à l'autre — **chacune ayant une fenêtre ouverte** — et une nouvelle
      ligne apparaît à chaque changement.
      *Une application sans fenêtre listable (Finder sans fenêtre) n'écrit rien et laisse Regarde
      sans cible : `⌥⌘` n'arme alors nulle part. C'est voulu.*

## 2. Ne rien casser — bloquant

Un échec ici invalide le produit, pas seulement le lot.

- [ ] **2.1** Sans rien presser : cliquez, glissez, sélectionnez du texte, actionnez des boutons.
      **Tout se comporte comme d'habitude.**
- [ ] **2.2** L'animation propre de l'application (vidéo, CSS, terminal) ne marque **aucun à-coup**
      quand vous tenez `⌥⌘`, puis quand vous tracez.
      *En revanche, tant que `⌥⌘` est tenu au-dessus de la fenêtre cible, les effets de SURVOL
      gèlent : boutons qui ne s'éclairent plus, infobulles absentes. C'est voulu — Regarde consomme
      les déplacements du curseur pour dessiner. Vérifiez que tout redevient normal au relâchement.*
- [ ] **2.3** Le curseur de saisie continue de clignoter dans un champ de texte pendant que vous
      tracez. **Le focus n'est jamais volé.**
- [ ] **2.4** Trois clics droits, dans cet ordre :
      **a.** hors tracé, avant toute marque → le menu contextuel s'ouvre ;
      **b.** en plein tracé, bouton gauche toujours enfoncé → le trait est annulé, **aucun menu** ;
      **c.** hors tracé, juste après → le menu contextuel s'ouvre **de nouveau**.
      *C'est (c) qui compte : un verrou du bouton droit resté levé ferait disparaître le menu
      contextuel pour de bon, sans aucun message.*
- [ ] **2.5** Tapez du texte, puis `⌘Z` **seul** : l'application testée annule sa propre frappe.
      *Régression trouvée et corrigée pendant l'écriture de cette recette.*
- [ ] **2.6** `⌘S`, `⌘C`, `⌘P` seuls : l'application testée les reçoit normalement.
- [ ] **2.7** Commencez un tracé `⌥⌘` + glisser **au-dessus d'un paragraphe sélectionnable**,
      relâchez `⌥⌘` **sans lâcher le bouton**, continuez à glisser, puis relâchez le bouton.
      Le trait **continue de suivre le curseur** jusqu'au relâchement du bouton, et la marque est
      posée — le verrou tient, c'est voulu. Et l'application testée n'a rien reçu : **aucun texte
      n'est sélectionné**.
- [ ] **2.8** Après un tracé, le premier clic ordinaire suivant fonctionne du premier coup.

## 3. Le mode éclair

- [ ] **3.1** Sans avoir pressé `⌃⌥S` : curseur **dans** la fenêtre testée, tenez `⌥⌘` et glissez.
      Le trait apparaît — aucune session n'a été ouverte.
      *Le calque est transparent : il n'y a rien à voir avant le premier tracé.*
- [ ] **3.2** L'outil actif au démarrage est la **flèche** : un segment droit relie votre point
      d'appui au curseur, et son extrémité suit **sans retard perceptible**.
      *Rien ne s'affiche tant que le glissement n'a pas dépassé ~4 points.*
- [ ] **3.3** Regardez les **deux** extrémités : la queue reste exactement au point d'appui, la
      pointe exactement sous le curseur. Ni l'une ni l'autre décalée — et surtout pas du double.
      *C'est le test qui attrape une erreur d'échelle Retina. À refaire sur l'écran externe en 9.1.*
- [ ] **3.4** Relâchez `⌥⌘` : l'encre reste un court instant (≈ 0,35 s) puis disparaît d'un coup.
      *Ce délai est voulu — represser `⌥⌘` avant qu'il ne s'écoule laisse tout en place.*
- [ ] **3.5** ≈1 s après, le HUD annonce `N marque(s) publiée(s)` et un nom de dossier. **Puis
      lisez le journal** : `éclair — N marque(s), M image(s)` doit porter **deux nombres égaux**.
      *Le HUD compte les marques, pas les fichiers. `1 marque` au HUD avec `0 image` au journal est
      une gravure perdue, et le journal est le seul endroit où ça se voit.*
- [ ] **3.6** `ls -t ~/Regarde/sessions | head -1 | xargs -I{} ls -l ~/Regarde/sessions/{}/frames`
      → au moins un `marque-01.png` de taille non nulle.
      *Un `frames/` vide est un échec : le dossier est créé avant la gravure.*
- [ ] **3.7** **Rafale** : trois marques en relâchant `⌥⌘` entre chacune, en repressant **en moins
      de 0,8 s** et **sans sortir le curseur de la fenêtre**. Les trois dans **un seul** dossier.
      *Au-delà de 0,8 s — ou si le curseur quitte la fenêtre — la publication part et la
      numérotation repart à 1 dans un second dossier. Ce n'est pas un défaut, c'est le seuil.*

## 4. Les quatre outils

`⌥⌘` tenu, appuyez sur la lettre : le HUD annonce l'outil.

- [ ] **4.1** `⌥⌘F` → flèche. La **pointe** est là où vous relâchez, la **queue** là où vous avez
      appuyé, et le numéro se range **à la queue** — jamais sur la pointe.
- [ ] **4.2** `⌥⌘C` → cadre. Un rectangle vide.
- [ ] **4.3** `⌥⌘P` → point. Cliquez sans bouger : un disque plein.
- [ ] **4.4** `⌥⌘S` → surlignage. Un aplat translucide **qui laisse lire ce qu'il recouvre**, bordé
      d'un liseré net.
- [ ] **4.5** Choisissez `⌥⌘C`, relâchez `⌥⌘` **sans rien tracer**, repressez et tracez : c'est bien
      un cadre.
- [ ] **4.6** Choisissez `⌥⌘C`, **tracez**, relâchez, attendez la publication, puis tracez de
      nouveau : **c'est toujours un cadre**.
      *L'outil était réinitialisé en silence par la publication ; corrigé pendant cette recette.*

## 5. Numérotation et annulation

Toute cette section se fait **sans relâcher `⌥⌘`** : un relâchement de plus de 0,8 s publie
l'observation et renumérote à partir de 1.

- [ ] **5.1** Le numéro apparaît **pendant** le tracé, avant de relâcher le bouton.
- [ ] **5.2** Le numéro ne bouge plus une fois la marque posée.
- [ ] **5.3** `Échap` en plein tracé : le trait disparaît, rien n'est posé.
- [ ] **5.4** **Clic droit** pendant le tracé, bouton gauche toujours enfoncé — un vrai clic
      secondaire. *Control+clic ne convient pas : macOS l'envoie comme un clic gauche.* Le trait
      disparaît, **aucun menu contextuel**.
- [ ] **5.5** Relâchez `⌥⌘`, laissez la publication se faire, la numérotation repart de 1. Puis
      **sans relâcher** : posez une marque (badge `1`), commencez un second tracé (badge `2`
      pendant le geste), annulez par `Échap`, retracez : la nouvelle marque reprend le **`2`**.
- [ ] **5.6** `⌥⌘Z`, **`⌥⌘` tenu sans interruption** : la marque `2` disparaît et le journal écrit
      `marque 2 supprimée — le numéro n'est pas réattribué`.
      *Après une publication, il n'y a plus rien à annuler : `⌥⌘Z` est alors sans effet et sans
      message. C'est normal.*
- [ ] **5.7** Toujours sans relâcher, tracez une marque : elle porte **`3`**, pas `2`. Le calque
      montre `1` et `3`.
      *C'est voulu : vous avez pu prononcer ce numéro à voix haute.*

## 6. Les intentions

- [ ] **6.1** Posez une marque puis, `⌥⌘` toujours tenu, pressez la **1re** touche de la rangée du
      haut : le badge devient `1 · mal aligné`.
- [ ] **6.2** Toujours sans relâcher, frappez les six **par leur position** : mal aligné, erreur,
      manque un état, lent, texte à corriger, ne marche pas. Elles s'appliquent **toutes à la même
      marque**, chacune remplaçant la précédente.
- [ ] **6.3** `⌥⌘` tenu, pressez la **7e** touche : le HUD dit `7 — hors palette` et le journal
      écrit `chiffre 7 sans effet`. **Ces deux traces sont la preuve que la frappe a été avalée** —
      sans elles, elle serait partie à l'application testée.
- [ ] **6.4** Relâchez `⌥⌘`, **attendez l'annonce de publication**, reprenez `⌥⌘` et pressez la 1re
      touche : le HUD dit `Aucune marque à qualifier`.
- [ ] **6.5** **Le cas qui comptait.** `⌃⌥S` d'abord — sans session, la publication partirait avant
      que vous ayez frappé. `⌥⌘F` pour reprendre la flèche. Tracez **vers le bord de la fenêtre**,
      curseur finissant dehors. Relâchez le bouton, `⌥⌘` toujours tenu, frappez la 1re touche : le
      journal écrit `marque N : mal aligné`. **L'intention s'applique alors que le curseur est hors
      de la cible.** Refermez par `⌃⌥F`.
- [ ] **6.6** `⌃⌥S` sur l'application testée, puis passez dans un autre programme : le journal écrit
      `application active : … — les touches lui reviennent`. Tenez `⌥⌘` et pressez la 1re touche :
      **le HUD ne dit rien, le journal n'écrit rien** — la frappe est partie à l'autre programme.
      Revenez, refermez par `⌃⌥F`.
      *Hors session, la cible SUIT l'application au premier plan : `⌥⌘` + chiffre appartient alors à
      Regarde partout. C'est voulu.*

## 7. La fenêtre cible

- [ ] **7.1** D'abord le contrôle positif : `⌥⌘` + glisser **dans** la fenêtre testée → un trait.
      Puis `⌥⌘` + glisser **hors** de cette fenêtre → **aucun trait**, et le clic part à
      l'application dessous, qui passe au premier plan.
      **Recliquez ensuite sur la fenêtre testée** : tout le reste des sections 7 et 8 en dépend.
- [ ] **7.2** `⌥⌘⇧` + glisser hors de la fenêtre : **la marque est posée**. C'est l'échappatoire.
- [ ] **7.3** Déplacez la fenêtre d'au moins la moitié de sa largeur, comptez une seconde, puis
      `⌥⌘` + glisser **au nouvel emplacement** : le trait apparaît. Même geste **à l'ancien
      emplacement** : aucun trait.
- [ ] **7.4** Passez à une autre application **ayant une vraie fenêtre** : le journal écrit
      `cible suivie : …`. `⌥⌘` + glisser dans sa fenêtre : le trait apparaît. Repassez sur
      l'application testée.
      *Basculer sur le Bureau n'écrit volontairement aucune ligne.*

## 8. La session explicite

- [ ] **8.1** **Cliquez d'abord dans l'application testée** (surtout pas dans le terminal du
      journal), puis `⌃⌥S`. Le journal écrit `cible figée : <application testée> — cadre …`.
      **Si le nom n'est pas le bon, `⌃⌥F` et recommencez** : tout le reste porterait sur la
      mauvaise fenêtre.
- [ ] **8.2** Posez trois marques en relâchant `⌥⌘` entre chacune. **Rien n'est publié** : aucune
      ligne `éclair —`, et le `frames/` de la session reste **vide**.
      *Le dossier de session, lui, est créé dès `⌃⌥S` : le voir apparaître est normal.*
- [ ] **8.3** Passez dans un autre programme : le journal écrit `application active : … — les
      touches lui reviennent`, et **aucune ligne `cible suivie :`**. Là, `⌥⌘` + touche `Z` :
      le journal **n'écrit pas** `marque … supprimée`. Puis `⌥⌘` + glisser au-dessus de la fenêtre
      testée restée visible : le trait apparaît — la cible n'a pas bougé. `Échap` avant de relâcher.
- [ ] **8.4** `⌃⌥F` : le HUD annonce `Session terminée — 3 marques`, le journal liste les marques et
      le nombre d'images.
- [ ] **8.5** Ouvrez le dossier nommé par la dernière ligne du journal. Son sous-dossier
      **`frames/`** contient **exactement trois PNG**.
- [ ] **8.6** **Attendez que le HUD soit revenu à `Prêt`** (journal : `cible : dégelée, retour au
      suivi`). Alors seulement, `⌥⌘` + glisser puis relâchez : le HUD annonce `1 marque publiée` et
      un **nouveau** dossier apparaît.
- [ ] **8.7** `⌃⌥S`, posez **deux** marques, `⌥⌘Z` : la seconde disparaît et le journal écrit
      `marque 2 supprimée`. `⌃⌥F` : le `frames/` ne contient que `marque-01.png` — **aucun
      `marque-02.png`**.

## 9. Les écrans

Vos deux écrans n'ont pas la même échelle — @2× et @1×. C'est la disposition qui casse un code
supposant un facteur global.

- [ ] **9.1** Faites glisser la fenêtre testée sur l'écran externe, cliquez dedans, attendez une
      seconde. Tracez **à l'intérieur** : le trait démarre exactement sous le curseur, pas au double
      de la distance depuis le coin.
      *Sans déplacer la fenêtre, `⌥⌘` n'arme pas sur l'écran externe — c'est le test 7.1.*
- [ ] **9.2** Commencez un tracé sur un écran et poursuivez sur l'autre. L'encre **s'arrête net au
      bord de l'écran de départ** et n'apparaît jamais sur le second — la marque appartient à son
      écran d'origine. Le journal ne doit annoncer qu'**une seule** ligne `marque N — …`.
      *Deux lignes pour un seul geste seraient le défaut.*
- [ ] **9.3** Débranchez l'écran externe. Journal : une section `Panneaux` avec
      `raison  changement d'écrans`, le compte décrémenté, et les identifiants `retirés`. L'icône
      reste cliquable, le Diagnostic s'ouvre encore.
- [ ] **9.4** Rebranchez. Journal : nouvelle section `Panneaux`, l'écran réapparaît avec sa taille
      et son échelle. Ramenez la fenêtre dessus, attendez une seconde, tracez : même épaisseur
      qu'avant, ni décalé ni deux fois trop grand.

## 10. Les images produites

**Mise en place** : application testée au premier plan, `⌃⌥S`, puis **quatre marques sans fermer la
session** — une flèche pointant un petit détail, un cadre, un point, un surlignage — dont au moins
une qualifiée par une intention. Puis `⌃⌥F`. Ouvrez le dossier que le HUD vient de nommer.

- [ ] **10.1** Un PNG par marque, nommé `marque-NN.png` où **NN est le numéro, pas le rang** : après
      un `⌥⌘Z`, la suite comporte un trou. C'est voulu.
- [ ] **10.2** Sur l'image de la **flèche** : ce qu'elle **désigne** est au centre, pas le milieu du
      trait. La flèche entre par un bord et pointe vers le centre.
      *Corrigé pendant cette recette, après votre remarque.*
- [ ] **10.3** Sur l'image du **cadre** et du **surlignage** : la forme est centrée avec son contexte
      autour.
- [ ] **10.4** Le badge porte le bon numéro et la bonne intention, **au même endroit que sur votre
      écran pendant le tracé**, et ne recouvre pas ce que la marque désigne.
- [ ] **10.5** Le trait est cerné d'un halo : **sombre sur fond clair, clair sur fond sombre**.
      Testez sur une fenêtre en thème sombre.
- [ ] **10.6** **R12** — sur l'image de la **quatrième** marque, les trois premières étaient à
      l'écran au moment de la capture. **Aucune ne doit y figurer.**
- [ ] **10.7** Lancez `screencapture -T 5 ~/Desktop/regarde-r12.png`, revenez dans l'application,
      tracez et **gardez `⌥⌘` enfoncé** jusqu'au déclenchement. Ouvrez le PNG : **aucune encre**.
      *Sans maintenir `⌥⌘`, le calque est retiré avant la capture et le test passerait quel que soit
      l'état de R12.*

---

## Ce qui n'existe pas encore

| Absent | Lot |
|---|---|
| Micro, transcription, fenêtre de parole | 4 et 5 |
| Rapport texte, `feedback.md`, JSON | 3 |
| Serveur MCP, `get_feedback` | 6 |
| Presse-papiers, envoi à Claude Code | 3 |
| Détection du projet cible | 3 |
| Mode annotation verrouillé `⌃⌥L`, verrou du micro `⌃⌥M` | ultérieur, 5 |
| Réglages, modificateur personnalisable | ultérieur |
| Application signée et distribuable | 8 — bloqué |

## Ce que je veux savoir en retour

1. **Tout échec**, avec le numéro du test et ce que disait le journal au même moment.
2. **Les intentions sur AZERTY** : utilisable, ou insupportable ?
3. **La latence du trait** : imperceptible, ou vous la sentez ?
4. **Le gel du survol** pendant que `⌥⌘` est tenu (test 2.2) : acceptable, ou gênant ?
5. **Le délai de 0,8 s** du mode éclair : trop court pour enchaîner, trop long pour être réactif ?
6. Tout ce qui vous a fait **hésiter**, même sans être un bug.
