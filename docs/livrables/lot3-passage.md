# Lot 3 — passage du livrable

**Date** : 24 août 2026
**Critère du plan** (§ 7.4, S42) : « Sur une page animée, 8 marques pendant
l'animation : les 8 images montrent l'état exact désigné, vérifié contre un
enregistrement témoin. Traitement final < 3 s. RSS < 200 MiB, CPU < 3 %, disque
< 500 MiB pour 10 min. Débranchement d'écran en pleine session : les marques de cet
écran ont leur image. »

La version précédente de ce document disait : « le code est complet, le livrable
n'est pas passé », et donnait le tableau des mesures à faire. Le voici rempli. Les
campagnes ont couru sur deux jours et deux postes — l'installation de la maison
(ultrawide natif) le 23, le poste de bureau (moniteur 1080p en HDMI direct) le 24 —
en exécution **mixte** : les gestes par l'utilisateur, l'orchestration, les
raccourcis et le dépouillement par l'agent, chaque verdict tiré du journal ou d'un
dépôt de banc, jamais d'une impression.

---

## Le critère du plan, point par point

| Point du critère | Verdict | Ce qui l'établit |
|---|---|---|
| 8 marques sur page animée, état exact désigné, vérifié contre un enregistrement témoin | **✅** | Campagne `lot3-c11.sh` du 23 août : 8 marques sur le témoin en mode compteur, **8 images sur 8 depuis le fichier**, 0 par le filet. La vérification contre le témoin est **machine** : la réglette gravée dans chaque image porte le numéro de frame du témoin, les 8 numéros lus sont **strictement croissants** (écarts 43 à 150 images), et le banc conclut « aucun refus opposable » — pont d'horloge apparié par amas (9 clics sur les intrus des deux côtés), `fallbackCount` immobile, capture invisible. |
| Traitement final < 3 s | **✅** | Ligne `durée` du bloc `EXTRACTION`, mesures des 23-24 août : **121 à 195 ms** en usage courant (1 à 6 marques), 2 632 ms au pire mesuré (10 marques × 3 candidats, GOP 0,5 s, instants triés). Budget tenu avec un facteur 15 en usage courant. |
| RSS < 200 MiB | **✅** | `lot3-budgets.sh`, deux écrans, 10 min : **149,9 MiB** de crête (campagne du 24 août, 20 h 24). Une campagne antérieure à 198,0 MiB avec cinq marques Retina en attente documente la marge réelle — voir les réserves. |
| CPU < 3 % | **✅** | Même campagne : **1,4 %** de moyenne. Les deux campagnes précédentes du même jour (5,2 % puis 3,4 %) mesuraient en réalité les *dégâts fantômes* du compositeur — voir « ce que la recette a trouvé », S45. |
| Disque < 500 MiB / 10 min | **✅** | Même campagne : **158,6 MiB**. Là aussi, 970 MiB au matin avant l'épreuve d'identité — la différence est le produit de la recette, pas une variation de conditions. |
| Débranchement : les marques de l'écran parti ont leur image | **✅** | `lot3-debranchement.sh` du 24 août, câble tiré à chaud : `display 3 débranché — finalisation immédiate de son segment`, motif `deconnexion`, 440 frames intactes ; marque posée **après** le débranchement acceptée ; session close normalement ; **3 images sur 3 depuis le fichier, y compris la marque de l'écran débranché**. Les trois contrôles du script passent. |

**359 vérifications d'autotest** dans les cinq suites chiffrées (capture 151,
marques 97, réglette 40, icône 13, géométrie 58), toutes vertes, plus l'autotest
mécanique de la porte (`--selftest`). Zéro avertissement de compilation.

---

## La recette — 45 tests sur deux jours

La recette manuelle du lot 3 (`lot3-recette.md`, 45 tests en neuf sections) a été
déroulée intégralement. Sections 1 à 3 le 23 août, sections 4 à 9 le 24. Trois tests
ont changé de forme en cours de route, chaque fois **par la mesure** :

- **4.3** (burst retenu sur changement minuscule) — jugé par l'autotest sur entrées
  mesurées : l'exécution de bout en bout exige un écran au repos, et ce poste n'en a
  aucun (moniteur HDMI aux dégâts fantômes, papier peint vidéo). Les deux classes
  sont nommées dans le test, diagnosticables en une ligne de journal.
  **Abandon de la forme e2e décidé par l'utilisateur le 24 août.**
- **4.4** (bornes du plan de burst) — jugé par l'autotest, les deux bornes : la
  borne de fin exigerait de fermer la session moins de 0,4 s après la pression, la
  borne de début une pression sous ~1,2 s de session. Meilleur essai humain mesuré,
  utilisateur préparé et guidé à la voix : **1,298 s**. Aucune des deux bornes n'est
  à portée d'un geste ; le test le dit désormais, mesure à l'appui.
- **5.4** (écran pivoté) — **non applicable** : le moniteur ne pivote pas. La
  décision de refus est couverte par l'autotest de géométrie.

**Validation utilisateur : 24 août 2026.**

---

## Ce que la recette a trouvé

Le lot 2 avait établi qu'une recette trouve ce qu'aucun scénario automatisé ne voit
— onze défauts. Le lot 3 confirme, et double la mise : **une vingtaine de défauts**,
dont plusieurs auraient invalidé le produit en silence, et dont quatre nés de
correctifs de la veille.

### Dans le produit

| Défaut | Ce qu'il produisait |
|---|---|
| Tolérance d'extraction `before = .positiveInfinity` (celle de la spec) | le générateur rendait l'**image clé** précédente : 812,8 ms d'erreur mesurée — **B1 vivant dans le fichier écrit pour le tuer**. Tolérances nulles, § 5.2 amendé |
| Le mouvement n'atteignait jamais la marque (`reclamer` sans appelant, paramètre par défaut à zéro) | le plan de burst du § 5.4 **inerte depuis S40**, et son journal l'annonçait sans qu'on lise le zéro comme une panne |
| Surface salie **sommée** au lieu de moyennée | un spinner de 86×86 px franchissait le seuil — le cas que le double critère existe pour écarter |
| Curseur de lecture **partagé** des demandes d'instantané | à deux écrans actifs, chacun volait les instantanés de l'autre : une marque sur deux sans mouvement, symptôme illisible (« écran figé ») |
| `dirtyRects` en pixels divisés par une surface en **points** | mesure gonflée ×4 sur Retina : burst permanent sur écran immobile |
| Tolérance nulle sans repli | `Cannot Decode` sur écran calme → retour au filet du relâchement — **B1 par la porte de derrière**. Second passage ajouté, § 5.2 amendé |
| Le repli écrasait l'image exacte déjà obtenue | image 1,40 s trop tôt sur une marque — **attrapé par la réglette seule**, aucun compteur interne ne bougeait |
| GOP 1 s sous tolérances nulles | extraction à 3 659 ms (budget 3 s) ; GOP 0,5 s + instants triés → 2 632 ms au pire |
| La chaîne C11 lisait les **recadrages** | la réglette fait 2 176 px, le plus large recadrage 1 120 : le test qui décide du lot ne pouvait pas conclure. Le mode banc écrit l'image entière (`plein-NN.png`) |
| « Mots de passe » absent de la liste noire | une session a **capturé le gestionnaire de mots de passe d'Apple** sans obstacle — trouvé par l'utilisateur au 6.1, avec l'application qu'un utilisateur réel ouvre |
| Microsoft Teams absent de la liste noire | même motif que Slack, découvert quand une session de banc s'est ouverte sur le Teams de l'utilisateur en plein travail |
| **Dégâts fantômes** : le compositeur déclare la dalle entière sale à chaque frame sur un moniteur 1080p en HDMI direct (pixels immobiles à 0,03 % près) | 7,95 Mb/s pour un Bureau figé, 970 MiB/10 min, 5,2 % CPU — deux budgets crevés par du vide. **S45, l'épreuve d'identité** : ~2 000 mailles tournantes par frame, § 5.1 bis. CPU 5,2 → 1,4 %, disque 970 → 159 MiB |

### Dans les bancs et le témoin (l'instrument aussi se recette)

| Défaut | Ce qu'il produisait |
|---|---|
| Pont d'horloge apparié **par rang** puis **par fenêtre contiguë** | 16 993 ms puis 9,6 s de dispersion sur des ponts sains — l'appariement par **amas de décalages**, estimé au **plancher**, éprouvé contre les deux dépôts réels |
| Dépôt du témoin suspendu à un ⌃⌥D bien visé | trois campagnes perdues (plan clos trop tôt, onglet résiduel d'un autre port, clics sur le mauvais témoin) — la page **dépose d'elle-même** en passant en arrière-plan |
| Détecteur de plein écran sur `screen.height` | impossible à satisfaire sur **tout MacBook à encoche** — `screen.availHeight`, mesuré 1084/1117 |
| Garde « réglette inactive » du témoin | refusait la réglette **volontairement éteinte** — l'état que la paire de coût mesure en premier : le protocole C3b n'avait jamais pu tourner |
| `lire`/`attendre` sur dépôts **versionnés** | la boucle de calibrage a relu 40 fois la première photo d'un état qui avait convergé au cinquième dépôt |
| Frappes sans garantie de focus | une application relancée en arrière-plan volait le premier plan à l'instant de la frappe — `verbe()` garantit Chrome au premier plan avant chaque touche |
| `find` sur tout `$TMPDIR` sous `set -e` | `lot3-debranchement.sh` mourait **avant ses propres contrôles**, sans verdict ni bruit |
| ⌥⌘⇧ nulle part documenté | « une marque sur chaque écran » du protocole de débranchement était impossible telle qu'écrite — le refus hors cadre est **silencieux**, et l'utilisateur a légitimement cru à un bug |
| Rupture de monotonie tuait le script (`set -e`) | le cinquième refus opposable — la monotonie des numéros lus — n'aurait jamais rendu son verdict sur une campagne cassée |
| Générateur de recette : émphase à travers les segments de code | le bouton « copier » du 6.3 fabriquait la faute de frappe qu'il devait éviter (`</em>` dans la commande) |

**Un mode `--depouiller`** est né de ces campagnes : rejouer monotonie et verdict
sur les artefacts d'une campagne déjà faite, sans témoin, sans session, sans clic.
C'est lui qui a rendu le verdict officiel de la campagne du 23 août — et révélé le
bug du `set -e` ci-dessus.

### Ce que l'environnement a enseigné

Trois configurations parfaitement banales ont d'abord été qualifiées de « hors
norme » avant que la mesure n'inverse la charge : un moniteur 1080p en **HDMI
direct** (dégâts fantômes), un **papier peint vidéo**, l'**encoche** d'un MacBook.
L'utilisateur a refusé le qualificatif, et il avait raison les trois fois : c'est la
spécification qui supposait des écrans honnêtes et des dalles sans encoche. Chaque
cas est maintenant soit traité (S45), soit nommé et diagnosticable en une ligne de
journal.

---

## Réserves ouvertes, toutes documentées

- **9.5 — sensibilité C3b.** Les trois relevés sortent à 120,00 fps = 99,6 % du
  natif, hors de la fenêtre 70-90 % : la machine avale la butée de charge du témoin
  sans plier, et un coût de calque inférieur à la marge y est invisible. Les écarts
  de 0,00 % entre états sont une borne vraie mais grossière — « coût sous la
  marge », pas « sous 1 % ». La garde `chargeInsuffisante` a un trou (convergence
  « par stabilité » à pleine cadence). Dette lot 0, au lot 4.
- **RSS et le filet.** Chaque marque en attente retient son image de filet plein
  écran (~31 MiB en Retina) : cinq marques ≈ 155 MiB tenus jusqu'à la publication,
  crête mesurée à 198 MiB. Sept marques Retina creveraient le plafond. Au lot 4 :
  déposer le filet sur disque plus tôt.
- **C12 — un horodatage en repli** observé sur deux jours (marque tracée pendant que
  « Mots de passe » tenait la saisie sécurisée). Le chemin de repli a fait
  exactement son travail ; à surveiller s'il se reproduit hors gestionnaire de mots
  de passe.
- **S16** — Developer ID et notarisation, toujours bloqué sur le compte Apple
  Developer.

---

## La position

Le lot 3 est **validé** : critère du plan tenu sur les six points, recette de
45 tests déroulée et close, réserves nommées et bornées. La différence avec le
20 août n'est pas que le code a changé — il a changé vingt fois — c'est que chaque
chiffre de ce document a été **mesuré sur machine**, la plupart deux fois, et que
les échecs intermédiaires sont écrits ici avec leurs causes.

`v0.3.0` se pose sur ce commit.
