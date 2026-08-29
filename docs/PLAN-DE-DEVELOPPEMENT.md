# Plan de développement — Regarde

Version du 19 août 2026. Compagnon opérationnel de [`SPECIFICATION.md`](SPECIFICATION.md)
et des [décisions d'architecture](adr/README.md).

> **Périmètre engagé : lots 0 à 4.**
> L'auteur a arrêté le 19 août 2026 de n'engager que les lots 0 à 4 — soit environ 22,5 jours
> nominaux, le geste validé, les marques, la capture continue, le rapport et la boucle complète
> vers l'agent. À ce stade l'outil fonctionne sans voix ni MCP.
>
> Les lots 5 à 8 (voix, MCP, robustesse, distribution) ne sont **pas engagés**. Ils sont décrits
> ici en entier parce qu'ils conditionnent des choix faits en amont — le protocole des providers,
> le format du manifeste, la bibliothèque de rendu partagée — mais leur lancement dépend du
> **GO/NO-GO n°2** (§ 3.2), qui se joue sur dix jours d'usage réel après le lot 4.
>
> Conséquence pratique : tout arbitrage qui ne concerne que les lots 5 à 8 peut attendre. Tout
> choix des lots 0 à 4 qui **contraindrait** les lots suivants doit être pris maintenant, et le
> § 6 signale lesquels.

---

## 1. Ce que ce document ajoute à la spécification

La spécification décrit **quoi** construire et **pourquoi** chaque choix technique a été tranché.
Elle ne dit pas dans quel ordre attaquer, ni ce qu'on fait le samedi matin quand on ouvre Xcode
avec deux heures devant soi.

Ce plan couvre trois choses que la spécification laisse ouvertes :

- **L'ordre et les points d'arrêt.** Deux GO/NO-GO explicites, avec des critères qu'on peut lire
  sans se mentir, et une conduite à tenir si la réponse est non.
- **La préparation de chaque lot.** Ce qu'il faut avoir lu et compris *avant* d'ouvrir l'éditeur,
  pour un développeur dont l'écosystème natif est React/TypeScript et pas AppKit.
- **Le découpage en sessions courtes.** Un projet personnel se construit par tranches de deux à
  quatre heures, séparées par des jours d'oubli. Chaque tranche doit produire quelque chose de
  vérifiable, sinon elle est perdue.

Ce document ne rediscute aucune décision. Les arbitrages A1 à A5 de la spécification (§ 13) sont
tranchés selon leur recommandation par défaut et ne se rouvrent pas en cours de lot.

---

## 2. Réalité du calibrage

### 2.1 Les 40 journées-homme

Le chiffre de la spécification (§ 11.1) est **déjà calibré pour ce développeur-là** : les
multiplicateurs sont appliqués, ce ne sont pas 40 jours de praticien Swift à majorer ensuite.

| Nature de la tâche | Multiplicateur | Où ça mord |
|---|---|---|
| Logique métier, JSON, MCP | ×1,0 | Lots 4 et 6 — terrain connu |
| SwiftUI | ×1,2 | HUD, doctor, revue |
| AppKit | ×1,8 | Panneaux, `NSStatusItem`, `NSTextView` hors écran |
| `CGEvent` tap et callbacks C | ×2,0–2,5 | **Lot 0 entier**, watchdog du lot 7 |
| ScreenCaptureKit + `CMTime` | ×2,0 | **Lot 3 entier** |
| Concurrence Swift 6 stricte | ×1,5 transverse | Partout : acteurs, `Sendable`, files série |
| Signature et TCC | ×2,0 | Lots 1 et 8 |

Deux lots concentrent le risque de dérapage : le **lot 0** (2,5 j, tap et callbacks C) et le
**lot 3** (6,5 j, ScreenCaptureKit et temps). Ce sont aussi les deux seuls qui décident si le
produit est possible. Ce n'est pas une coïncidence, c'est la définition d'un prototype de risque.

### 2.2 Les trois pertes de temps structurelles

Elles ne sont pas des imprévus : elles sont certaines, il faut les budgéter comme des postes.

**Pas de hot reload.** Une itération sur le calque coûte 20 à 40 s (build, signature, relance,
repositionnement de l'application témoin) contre 2 s en React. Sur les cent itérations qu'exige
le réglage d'un rendu d'encre, ce sont 50 minutes de compilation pure. *Parade* : régler la
géométrie et les couleurs dans une scène de test statique (une `NSView` avec des chemins codés en
dur, relancée sans le tap), pas dans la boucle complète.

**Le débogage TCC est aveugle.** `CGEvent.tapCreate` renvoie `nil`, la capture sort noire, la
transcription ne renvoie rien — sans exception, sans log, sans message. On peut y perdre une
soirée entière en cherchant un bug qui n'existe pas. *Parade* : le doctor du lot 1 existe pour ça,
mais dès le lot 0 chaque appel qui dépend d'une permission est encadré d'un `guard … else` qui
imprime la permission concernée et l'état de son preflight.

**La re-signature peut désactiver le tap.** Chaque build produit un binaire dont l'empreinte
change ; l'autorisation Input Monitoring accordée au binaire précédent ne suit pas forcément.
Le symptôme est « ça marchait il y a dix minutes ». *Parade* : signer avec un certificat
auto-signé **stable** du trousseau plutôt qu'en ad hoc anonyme, lancer l'application depuis un
chemin fixe (`~/Applications/Regarde.app`) et non depuis `DerivedData`, et adopter dès le premier
build le rituel décrit en § 4.2.

### 2.3 Une quatrième perte, propre au travail fractionné

La ré-immersion. Reprendre un fichier `CGEventTap` abandonné six jours plus tôt coûte 15 à 25
minutes avant la première ligne utile — relire son propre code, retrouver quelle permission on
avait révoquée pour tester, remonter la configuration à deux écrans.

Sur environ 93 sessions de trois heures, c'est **une trentaine d'heures**, soit 4,5 journées qui
ne sont pas dans les 40. **Budget réaliste en travail fractionné : 45 journées-homme.**

### 2.4 Ce que ça donne en soirées et week-ends

| Rythme tenu | Heures/semaine | Durée pour 45 j (315 h) |
|---|---|---|
| 2 soirées de 2 h | 4 h | 78 semaines — **18 mois** |
| 2 soirées + une demi-journée de week-end | 8 h | 39 semaines — **9 mois** |
| 3 soirées + une demi-journée | 11 h | 29 semaines — **7 mois** |
| 3 soirées + un week-end complet | 15 h | 21 semaines — **5 mois** |

Les « 4 à 5 mois » de la spécification supposent la dernière ligne, tenue sans interruption. Un
projet personnel ne tient presque jamais ce rythme sur vingt semaines : il y a des vacances, des
semaines chargées, des soirées où on n'a pas la tête à débuguer un callback C.

**Le repère honnête est de 7 à 9 mois.** Ce qui rend cette durée acceptable, et c'est le sens du
séquencement : le produit est utilisable au **lot 2**, atteint au bout d'environ un tiers du
chemin, et la boucle complète au **lot 4**, à peu près à mi-parcours.

---

## 2.5 Une release GitHub par lot

Chaque lot terminé donne lieu à un tag et à une release sur
[github.com/tfoutrein/regarde](https://github.com/tfoutrein/regarde/releases).

| Lot | Version | Contenu |
|---|---|---|
| 0 | `v0.0.1` | prototype de risque, jeté ensuite |
| 1 | `v0.1.0` | socle et vérité sur les permissions |
| 2 | `v0.2.0` | marques et export — premier lot utilisable |
| … | `v0.N.0` | un mineur par lot |
| 8 | `v1.0.0` | distribuable |

Les notes de release disent ce que le lot a livré, **ce qu'il a coûté**, et ce qui reste
ouvert. Un lot dont les notes ne mentionnent aucune difficulté est un lot dont on a oublié
les difficultés : elles sont la partie réutilisable.

Le tag se pose sur le commit qui atteint le critère de fin du lot, pas sur le dernier
commit en date — les corrections de documentation qui suivent appartiennent au lot suivant.

## 3. Les deux points d'arrêt

### 3.1 GO/NO-GO n°1 — après le lot 0

**Question posée :** le geste fonctionne-t-il réellement, et à quel coût de composition ?

**Critères objectifs.** C1 à C6 et C3b doivent passer, mesurés contre les trois applications
témoins (§ 4.3). Ce ne sont pas des impressions : chaque critère a une manipulation et un
résultat écrit dans le dépôt.

**Si la réponse est non**, tout ne se vaut pas :

| Échec | Gravité | Conduite |
|---|---|---|
| **C2** — les événements atteignent quand même l'application testée | **Fatal** | Le `.headInsertEventTap` avec `.defaultTap` est la seule voie pour consommer un événement. S'il ne consomme pas, il n'y a pas de produit : le développeur annoterait par-dessus une application qu'il manipule en même temps. Arrêt. |
| **C1** — les clics n'atteignent plus l'application hors modificateur | Corrigible | Bug de la porte à verrou, pas d'architecture. Relire § 6.2 ligne à ligne. |
| **C3b** — plus de 5 % de dégradation de cadence | Sérieux, corrigible | L'ordonnancement du calque à la demande ([ADR-0010](adr/0010-calque-ordonne-pendant-le-trace-seulement.md)) **est déjà la parade**. Il faut vérifier que la dégradation n'existe que pendant le tracé et pas au repos. Voir § 10.2 pour les seuils de décision. |
| **C4** — le focus est perdu | Corrigible | `.nonactivatingPanel`, `canBecomeKey = false`, politique `.accessory`. Si les trois sont en place et que le focus part quand même, c'est le tap qui active l'application : vérifier qu'aucun appel AppKit ne traîne dans le callback. |
| **C5** — le premier point est perdu | Corrigible | Symptôme d'une décision prise ailleurs qu'au `mouseDown`, ou d'un calque ordonné avant bufferisation des points. |
| **C6** — événements orphelins au relâchement du modificateur | Corrigible | Le verrou `strokeActive` ne tient pas jusqu'au `mouseUp`. |

Un seul échec est fatal, et il est fatal tout de suite. C'est exactement pour ça que le lot 0
coûte 2,5 jours et pas une seule : **on paie 2,5 jours pour ne pas en perdre 40.**

### 3.2 GO/NO-GO n°2 — après le lot 4

**Question posée :** après deux semaines d'usage quotidien réel, le rapport fait-il gagner du
temps par rapport à une capture d'écran collée dans l'agent ?

**Critères objectifs**, relevés sur dix jours ouvrés d'usage réel, pas simulé :

- **Fréquence spontanée.** Combien de sessions ouvertes sans se forcer ? En dessous de **une
  session tous les deux jours**, l'outil n'est pas entré dans le geste.
- **Taux de repli.** Combien de fois a-t-on préféré ⌘⇧4 et un collage manuel ? Au-dessus de
  **la moitié des besoins de retour visuel**, le coût fixe de la session n'est pas amorti.
- **Qualité du diff.** Sur les dix derniers rapports, combien ont produit un diff pertinent sans
  qu'on ait à réexpliquer à l'agent ce qu'on voulait dire ? En dessous de **7 sur 10**, l'ancrage
  ne remplace pas la conversation, il s'y ajoute.
- **Coût de la fin de session.** Le budget dur est de 20 s entre le raccourci de fin et le
  presse-papiers (§ 6.6). S'il est dépassé en pratique, le calcul est déjà perdu.

**Si la réponse est non : on s'arrête, et c'est un résultat.** Un outil dont on a établi
expérimentalement qu'il ne fait pas gagner de temps sur son propre usage est une information
qu'on n'avait pas avant, obtenue pour environ vingt journées au lieu de quarante-cinq. Ce qui
reste alors n'est pas rien :

- une application qui marque, capture et exporte, utilisable telle quelle en mode éclair ;
- vingt ADR qui documentent des faits système établis par sondes et non par lecture de
  documentation — la valeur la plus durable du projet ;
- une compétence AppKit / ScreenCaptureKit / `CGEvent` qui ne s'obtient pas en lisant.

Ce qu'il ne faut **pas** faire dans ce cas : enchaîner sur les lots 5 et 6 en espérant que la voix
ou le MCP changent la réponse. La spécification est explicite : si le rapport ne fait pas gagner
de temps, ni la voix ni le MCP n'y changeront rien. Ils rendent le rapport plus riche, pas plus
utile.

---

## 4. Lot 0 en détail — les deux jours et demi qui décident du projet

**2,5 jours.** C'est le seul lot détaillé à ce niveau, parce que c'est celui qu'on est tenté de
bâcler : il ne produit rien qu'on puisse montrer, et sa version « ça a l'air de marcher » se
fabrique en trois heures. Cette version-là ne répond à aucune des questions posées.

### 4.1 Ordre de réalisation

L'ordre compte. Chaque tâche est vérifiable seule, et chacune supprime une classe entière de faux
diagnostics pour la suivante.

| # | Tâche | Durée | Fini quand |
|---|---|---|---|
| **T0.1** | Les trois applications témoins et la page de mesure (§ 4.3). Pur HTML/JS. | 2 h | La page affiche son numéro de frame et vide son histogramme de deltas dans la console. |
| **T0.2** | Bundle `.app` minimal : `LSUIElement = 1`, politique `.accessory`, certificat auto-signé stable, lancement depuis `~/Applications/`. Un `NSStatusItem` qui ne fait rien. | 3 h | L'application tourne, aucune icône dans le Dock, l'icône de barre de menus apparaît. Le rituel de re-signature (§ 4.2) est écrit dans le `README`. |
| **T0.3** | Preflights des quatre permissions, imprimés au lancement. `CGPreflightListenEventAccess`, `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, statut micro. | 2 h | On révoque une permission dans Réglages, on relance, le log **nomme** la permission manquante. |
| **T0.4** | `CGEventTap` sur thread dédié avec sa propre run loop. Écoute souris **et `keyDown` et `flagsChanged`**. Passe-plat intégral, compteur d'événements. | 4 h | Le compteur monte, et l'application testée se comporte **exactement** comme sans le tap. |
| **T0.5** | Une `NSPanel` par `NSScreen`, § 6.1 à la lettre. `CAShapeLayer` avec un chemin codé en dur. Ordonnancement par `orderFrontRegardless()`. | 4 h | Un trait rouge est visible au-dessus de Safari en plein écran natif, sur les deux écrans, y compris après un changement de Space. |
| **T0.6** | La porte à verrou du § 6.2, littéralement. Ring lock-free alimenté par le tap, vidé par un display link. Ordonnancement du calque à la pression du modificateur, retrait au relâchement. | 5 h | ⌥⌘-glisser dessine et ne sélectionne aucun texte ; sans ⌥⌘, tout passe. |
| **T0.7** | Instrumentation de latence : de `CGEvent.timestamp` au commit du `CAShapeLayer`. Histogramme, p50/p95 imprimés à la demande. | 2 h | Un p95 chiffré s'affiche après 500 points tracés. |
| **T0.8** | Ré-armement sur `tapDisabledByTimeout` / `tapDisabledByUserInput` + watchdog 5 s vérifiant `tapIsEnabled` **et** l'activité récente. | 2 h | On force une désactivation (saisie dans un champ de mot de passe, ou une pause artificielle de 2 s dans le callback), le tap revient seul. |
| **T0.9** | Le banc de mesure C3b et C11 (§ 4.4 et § 4.5). | 3 h | Deux nombres écrits dans le dépôt. |
| **T0.10** | Passage des douze critères contre les trois témoins, résultats consignés. | 3 h | Le tableau du § 4.6 est rempli, ligne par ligne. → **GO/NO-GO n°1** |

### 4.2 Le rituel de re-signature

À adopter au premier build, pas au dixième soir de débogage :

1. Créer une fois un certificat de signature de code auto-signé dans le trousseau, nommé
   `Regarde Dev`, et signer **avec lui** (jamais `codesign -s -`).
2. Installer l'application à un chemin fixe. Le chemin `DerivedData` change et emmène
   l'autorisation avec lui.
3. Après chaque build, vérifier l'état du tap avant de conclure quoi que ce soit sur un bug :
   le compteur d'événements de T0.4 reste en place pour toute la durée du lot 0 et sert de
   témoin permanent.
4. Quand l'autorisation saute : retirer puis remettre l'entrée dans Réglages > Confidentialité >
   Surveillance de la saisie, et relancer. Trente secondes, à condition de savoir que c'est ça.

**La règle de survie : ne jamais déboguer plus de dix minutes sans avoir revérifié que le tap
est vivant.** La quasi-totalité des « bugs » de cette phase n'en sont pas.

### 4.3 Les trois applications témoins

Elles ne sont pas interchangeables : chacune couvre un chemin de composition différent du
WindowServer.

**Témoin 1 — page web animée plein écran dans Chrome.** Une page unique servie en local, qui
porte trois fonctions dans trois modes sélectionnables :

- *mode horloge* : une trotteuse en `requestAnimationFrame`, contrôle visuel de C3 ;
- *mode charge* : un canvas WebGL avec une boucle de rendu réglée pour tourner juste sous 60 fps
  (assez de travail GPU pour que toute couche de composition supplémentaire se voie), et qui
  enregistre tous ses deltas de `rAF` — c'est l'instrument de **C3b** ;
- *mode compteur* : le numéro de frame en très gros chiffres au centre, plus un journal
  `(numéro, performance.now())` — c'est l'instrument de **C11**.

Un champ de texte est présent dans tous les modes : c'est lui qui prouve C2 (⌥⌘-glisser ne
sélectionne pas) et C4 (le caret continue de clignoter).

**Témoin 2 — Simulateur iOS en animation.** Couvre le cas d'une fenêtre à composition accélérée
d'un processus tiers, avec ses propres surfaces Metal. C'est aussi la cible d'usage réelle la
plus probable après le navigateur.

**Témoin 3 — Terminal avec `top`.** Couvre le rendu texte à cadence lente. C'est le seul témoin
sur lequel une frame perdue ou décalée se voit à l'œil nu dans le contenu lui-même.

À ces trois-là s'ajoutent deux manipulations obligatoires qui ne demandent pas d'application
dédiée : **le Finder** (glisser un fichier, pour C6) et **Safari en plein écran natif** (C8).

### 4.4 Mesurer C3b concrètement

Le critère est « moins de 5 % de dégradation de cadence ». Il n'a de sens que si on mesure trois
états, pas deux.

**Protocole**, dans l'ordre, sur le témoin 1 en mode charge, plein écran, écran de référence :

1. **Référence.** 30 s de mesure, application Regarde **non lancée**. On note la médiane et le
   p95 des deltas de `rAF`.
2. **Regarde lancé, calque non ordonné.** 30 s. Le tap tourne, les panneaux existent, aucun n'est
   à l'écran. C'est l'état majoritaire d'une session : il doit coûter **zéro**.
3. **Calque ordonné, tracé continu.** 30 s en maintenant ⌥⌘ et en traçant sans discontinuer.

**Lecture du résultat :**

| Mesure | Seuil | Signification |
|---|---|---|
| État 2 vs 1 | doit être **< 1 %** | Au-delà, l'ordonnancement à la demande de l'[ADR-0010](adr/0010-calque-ordonne-pendant-le-trace-seulement.md) ne suffit pas : quelque chose reste composité en permanence. C'est un défaut d'implémentation, pas un arbitrage. |
| État 3 vs 1 | doit être **< 5 %** | C'est le critère C3b de la spécification. |

Trois précautions sans lesquelles la mesure ment : la page doit garder le focus pendant toute la
mesure (Chrome bride `rAF` sur un onglet inactif — et si elle le perd, c'est C4 qui a échoué, pas
C3b) ; il faut jeter les deux premières secondes de chaque relevé ; il faut refaire les trois
états dans l'ordre inverse, parce que la thermique de la machine dérive et fausse un relevé
unique.

### 4.5 Mesurer C11 concrètement

Au lot 0, il n'y a pas encore de flux continu : l'appariement marque ↔ frame de
l'[ADR-0008](adr/0008-temps-asset-distinct-du-temps-session.md) n'existera qu'au lot 3. **Ce qu'on
fait au lot 0 est l'étalonnage du banc, pas le verdict.**

Le banc : au `mouseDown` capturé, déclencher un `SCScreenshotManager.captureImage` synchrone
(c'est le filet du § 5.1, qui sera de toute façon nécessaire au lot 2), et écrire le PNG avec le
`SessionTime` de la marque dans son nom.

La mesure : le témoin 1 en mode compteur affiche son numéro de frame. On lit le numéro **gravé
dans l'image** et on le compare au numéro que la page a journalisé à cet instant hôte. Il faut
aligner les horloges une fois : un clic sur la page déclenche simultanément un marqueur applicatif
et une entrée dans le journal de la page, ce qui donne le décalage entre `performance.now()` et
`CMClockGetHostTimeClock()` ([ADR-0007](adr/0007-horloge-maitresse-unique.md)).

**Tolérance : une frame à 60 fps, soit 16 ms.** Ce qu'on obtient au lot 0 est la latence propre du
chemin `captureImage` — utile à connaître pour le mode éclair du lot 2. Le vrai passage de C11 se
fait au lot 3, avec le même banc et le flux continu : c'est le seul test qui rend visible le
risque R5, invisible sur un écran statique.

**Ce seuil de 16 ms ne se transpose pas au lot 3**, et c'est une correction, pas une nuance. Il a
été écrit pour un `captureImage` ponctuel ; le flux continu tourne à 15 fps (§ 5.2 de la
spécification), soit 66,7 ms entre deux frames encodées. Aucune extraction ne peut être plus fine
que cet intervalle. Le critère d'acceptation du lot 3 se dit donc en unités de compteur du
témoin — voir § 7.4, « Le seuil de C11 s'écrit avant la mesure ».

### 4.6 Les douze critères

| # | Critère | Manipulation | Bloquant pour le GO ? |
|---|---|---|---|
| C1 | Clics normaux hors modificateur | Cliquer un bouton, sélectionner du texte dans le témoin 1 | **Oui** |
| C2 | Aucun événement souris ne passe sous ⌥⌘ | ⌥⌘-glisser sur le champ de texte : aucune sélection | **Oui — fatal** |
| C3 | L'application testée continue de s'animer | La trotteuse tourne pendant le tracé | **Oui** |
| C3b | Cadence quantifiée | § 4.4 — trois états, < 5 % | **Oui** |
| C4 | Focus jamais perdu | Le caret continue de clignoter dans le témoin | **Oui** |
| C5 | Premier point jamais perdu | 20 tracés démarrent exactement sous le curseur | **Oui** |
| C6 | Pas d'événement orphelin au relâchement | Glisser un fichier dans le Finder, relâcher ⌥⌘ en plein tracé : aucun drag fantôme | **Oui** |
| C7 | Latence p95 | Instrumentation T0.7, < 33 ms, objectif < 16 ms | Non — mesuré, re-mesuré au lot 2 |
| C8 | Survie plein écran et changement de Space | Trait visible au-dessus de Safari plein écran | Non — parade au lot 7 (R10) |
| C9 | Non happé par Stage Manager | Stage Manager activé, le calque reste | Non |
| C10 | Tap actif après 30 min | Laisser tourner, vérifier le compteur | Non — parade au lot 7 (R9) |
| C11 | Appariement marque ↔ frame | § 4.5 — étalonnage ici, verdict au lot 3 | Non au lot 0, **oui au lot 3** |
| C12 | Événements synthétiques | Installer Karabiner, refaire C1/C2/C5 | Non — mais à faire avant le lot 2 |

Un critère non mesuré est un critère échoué. Les lignes non bloquantes se remplissent quand même :
elles sont la ligne de base contre laquelle les lots 2, 3 et 7 se compareront.

---

## 5. Les lots, avec leur préparation

### Lot 1 — Socle et vérité sur les permissions · 3,5 j

**Objectif.** Que l'application dise la vérité sur son propre état d'autorisation, avant qu'une
seule fonctionnalité en dépende.

**ADR incarnés.** [ADR-0002](adr/0002-hors-sandbox-developer-id.md) ·
[ADR-0020](adr/0020-confidentialite-capture-continue.md) ·
[ADR-0005](adr/0005-cgeventtap-arbitre-unique.md) (le doctor teste la création *effective* du tap)

**Livrable observable.** Sur un compte macOS vierge, les quatre permissions s'accordent en moins
de trois clics chacune et l'état passe au vert après relance. Le raccourci ⌃⌥S ouvre le doctor
sans aucune permission accordée.

**À avoir compris avant de commencer.**
- Les API de preflight et de requête : `CGPreflightListenEventAccess` /
  `CGRequestListenEventAccess`, `AXIsProcessTrustedWithOptions`,
  `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`,
  `AVCaptureDevice.authorizationStatus(for: .audio)`. Elles ne se comportent pas pareil : certaines
  déclenchent une invite, d'autres non, et certaines mentent tant que le processus n'a pas été
  relancé.
- Les URL `x-apple.systempreferences:` pour ouvrir directement le bon volet.
- `RegisterEventHotKey` (Carbon) : pourquoi il ne demande **aucune** permission TCC, contrairement
  aux moniteurs `NSEvent` globaux. C'est ce qui permet au doctor d'être atteignable même quand
  tout le reste est refusé.
- `IsSecureEventInputEnabled()`.
- Hardened Runtime, entitlements, `NSMicrophoneUsageDescription`, `NSTemporaryDirectory()`.
- `SCShareableContent.getShareableContent` : à appeler au lancement et au réveil, **jamais** au
  raccourci de session (R1).

**Piège principal.** Fabriquer un doctor qui ment. Une ligne verte parce que le preflight répond
« autorisé » alors que `tapCreate` renvoie `nil` en pratique est pire que pas de doctor du tout :
elle envoie chercher le bug ailleurs. **Chaque ligne du doctor exécute l'opération réelle**, pas
son preflight. Corollaire : le bouton « Relancer » par ligne doit vraiment refaire l'opération, et
les lignes qui exigent un redémarrage du processus doivent le dire au lieu d'afficher un état
périmé.

**Ce qu'on tire en avance du lot 8.** Obtenir le certificat Developer ID et faire **une**
notarisation à blanc dès ce lot. C'est administratif, lent, indépendant du code, et ça
dé-risque le lot 8 sans le commencer.

> **Reporté le 20 août 2026.** Cette avance exige un compte Apple Developer payant, que
> l'auteur n'a pas. Sans conséquence sur les lots 1 à 7 : le certificat auto-signé stable
> du § 4.2 couvre tout le développement, y compris la stabilité des autorisations TCC.
> Ce qui manque est la distribution à un tiers — sans notarisation, Gatekeeper bloque
> l'application sur une autre machine.
>
> **Le lot 8 est donc conditionné à l'ouverture d'un compte Apple Developer**, à prévoir
> avant de l'engager et non pendant. Le risque assumé en reportant est de découvrir un
> problème de notarisation tardivement — ce que cette avance devait justement éviter.

---

### Lot 2 — Marques et export : premier produit utilisable · 5,5 j

**Objectif.** Produire, à partir d'un geste, un PNG correct au bon endroit — le premier lot dont
la sortie a une valeur d'usage.

**ADR incarnés.** [ADR-0006](adr/0006-modificateur-option-commande.md) ·
[ADR-0013](adr/0013-numerotation-definitive-au-mousedown.md) ·
[ADR-0010](adr/0010-calque-ordonne-pendant-le-trace-seulement.md) ·
[ADR-0005](adr/0005-cgeventtap-arbitre-unique.md) ·
[ADR-0020](adr/0020-confidentialite-capture-continue.md)

**Livrable observable.** Session de 3 min sur une vraie application : 6 marques, 4 outils, 2
écrans dont un externe non-Retina **placé à gauche** (origine négative). 6 PNG au bon endroit, bon
numéro, **aucun pixel du calque ni du HUD**, aucun décalage ×2.

**À avoir compris avant de commencer.**
- **Les systèmes de coordonnées** (§ 3.3). AppKit a son origine en bas à gauche, Core Graphics en
  haut à gauche, et un écran placé à gauche de l'écran principal a des coordonnées **négatives**.
  `backingScaleFactor` est une propriété **par fenêtre**, pas globale.
- `NSPanel` : `styleMask` fixé à l'init et jamais muté, `collectionBehavior`,
  `hidesOnDeactivate = false`, `orderFrontRegardless()`.
- `NSApplication.didChangeScreenParametersNotification` et
  `NSWindow.didChangeOcclusionStateNotification`.
- `CAShapeLayer`, `CATransaction.setDisableActions(true)`, et pourquoi Core Animation anime
  implicitement `path` sans ça.
- Le display link sur macOS (`CADisplayLink` depuis macOS 14, `CVDisplayLink` avant).
- `SCScreenshotManager.captureImage` et `SCContentFilter(display:excludingApplications:)`.
- `CGWindowListCopyWindowInfo` pour le masquage des fenêtres tierces.
- Ramer-Douglas-Peucker pour la décimation du tracé.

**Piège principal.** Les coordonnées. Le décalage ×2 et l'origine négative ne se voient pas sur
une configuration mono-écran Retina — c'est-à-dire sur la machine de développement, en
permanence. **Écrire la fonction de conversion unique du § 3.3 en premier, avec une table de cas
de test explicite** (écran principal Retina, externe non-Retina à gauche, externe à droite,
changement d'échelle à chaud), et n'écrire aucun code de dessin avant qu'elle passe. Sinon le bug
apparaîtra au lot 3, mêlé aux bugs de temps, et sera trois fois plus cher.

**Second piège.** L'exclusion du calque des pixels capturés (R12). À vérifier **visuellement**, en
ouvrant un PNG exporté, dès la première image produite — pas en fin de lot.

---

### Lot 3 — Capture continue et ancrage exact · 6,5 j

**Objectif.** Que l'image jointe à une marque montre l'instant exact que le développeur désignait,
et pas celui d'après.

**ADR incarnés.** [ADR-0003](adr/0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md) ·
[ADR-0004](adr/0004-preroll-opt-in.md) ·
[ADR-0007](adr/0007-horloge-maitresse-unique.md) ·
[ADR-0008](adr/0008-temps-asset-distinct-du-temps-session.md) ·
[ADR-0009](adr/0009-geometrie-normalisee-sur-contentrect-de-frame.md)

**Livrable observable.** Sur une page animée, 8 marques pendant l'animation : les 8 images
montrent l'état exact désigné, vérifié contre un enregistrement témoin. Traitement final < 3 s.
RSS < 200 MiB, CPU < 3 %, disque < 500 MiB pour 10 min. Débranchement d'écran en pleine session :
les marques de cet écran ont leur image.

**À avoir compris avant de commencer.**
- ScreenCaptureKit : `SCStream`, `SCStreamConfiguration` (et le fait que sans `width`/`height`
  explicites la capture sort en 1920×1080 silencieusement), `SCStreamOutput`, le statut
  `SCFrameStatus.complete`, et les attachements `SCStreamFrameInfo` — `contentRect`,
  `contentScale`, `scaleFactor`, `dirtyRects`.
- `AVAssetWriter` / `AVAssetWriterInput`, `expectsMediaDataInRealTime`,
  `AVVideoMaxKeyFrameIntervalDurationKey`.
- **`CMTime` sérieusement.** `CMClockGetHostTimeClock()`, `CMSampleBufferGetPresentationTimeStamp`,
  et surtout le fait que le PTS du premier échantillon écrit n'est pas zéro : c'est tout l'objet
  de `firstSamplePTS` et `assetTime()`.
- `AVAssetImageGenerator.generateCGImagesAsynchronously(forTimes:)` et ses tolérances
  (`before = .positiveInfinity`, `after = .zero`).
- La sémantique de rétention de `CVPixelBuffer` et des pools : c'est de là que vient B2.

**Piège principal.** **B1, et il est invisible.** Confondre `SessionTime` et le temps de l'asset
produit des images décalées de quelques centaines de millisecondes. Sur un écran statique — donc
sur 90 % des tests qu'on fait spontanément — le résultat est parfait. Le bug ne se révèle que sur
contenu animé, c'est-à-dire exactement dans le cas d'usage qui justifie le produit. **Le témoin en
mode compteur du lot 0 est le seul instrument qui le rend visible : le passer avant d'écrire une
seule ligne d'extraction, pas après.**

**Second piège.** B2. La règle est absolue et ne souffre aucune exception d'optimisation : **le
thread du tap ne touche jamais un `CVPixelBuffer`.** Il pousse un triplet
`(SessionTime, point, type)` dans un ring lock-free, point final. L'appariement se fait sur
`encodeQueue`, seul propriétaire des frames. Un `EXC_BAD_ACCESS` intermittent dans
`CVPixelBufferRelease`, dont la fréquence dépend de l'activité de l'écran, coûte des soirées
entières à diagnostiquer parce qu'il n'est pas reproductible à la demande.

---

### Lot 4 — Rapport, projet, presse-papiers : boucle complète · 4,5 j

**Objectif.** Fermer la boucle : du geste jusqu'au diff produit par l'agent, sans intervention.

**ADR incarnés.** [ADR-0014](adr/0014-journal-append-only.md) ·
[ADR-0016](adr/0016-aucune-image-via-mcp.md) ·
[ADR-0017](adr/0017-detection-projet-trois-etats.md) ·
[ADR-0018](adr/0018-presse-papiers-et-injection-best-effort.md) ·
[ADR-0020](adr/0020-confidentialite-capture-continue.md)

**Livrable observable.** Cycle complet sans intervention : raccourci → 5 marques → raccourci → ⏎ →
l'agent lit et produit un diff pertinent. Projet correct sur 10 sessions dans 5 projets, ou
affiché ambigu quand il l'est. Zéro fichier hors du projet attendu.

**À avoir compris avant de commencer.**
- `Codable`, et le versionnement d'un format de manifeste qu'on va faire évoluer.
- La sémantique réelle de `O_APPEND` et de `write(2)` sur un fichier régulier (§ 3.7), l'écriture
  courte, `EINTR`, et quand `flock` devient nécessaire (dossier synchronisé).
- `proc_pidinfo` / `proc_pidpath` pour lire le `cwd` d'un processus voisin.
- `NSPasteboard` : `declareTypes`, l'énumération des types présents, et le fait qu'une
  restauration naïve perd les variantes riches.
- L'API Accessibilité côté client : `AXUIElementCreateApplication`,
  `kAXFocusedUIElementAttribute`, écriture de valeur et envoi de touches.

**Piège principal.** `report.md` **est un rendu, pas une source** (§ 9.3). Le sidecar du lot 6
doit préfixer un bandeau dynamique, filtrer par marques et honorer `include_context: false` : il
ne peut pas servir le fichier tel quel. Si le générateur de rapport est écrit ici comme du code
applicatif, le lot 6 le réécrit intégralement. **La bibliothèque de rendu partagée se conçoit dans
ce lot**, même si son second consommateur n'existe pas encore.

**Second piège.** La confirmation de projet qui se dégrade en réflexe (R2). Les trois états
doivent être **visuellement** distincts — pas trois libellés dans la même couleur. Un rapport
poussé dans le mauvais dépôt se découvre dans une pull request, des jours plus tard.

---

### Lot 5 — Voix et texte · 6 j

**Objectif.** Que ce qu'on dit pendant le geste se retrouve rattaché à la bonne marque.

**ADR incarnés.** [ADR-0011](adr/0011-micro-par-fenetre-de-parole.md) ·
[ADR-0012](adr/0012-speechanalyzer-avec-speechdetector.md) ·
[ADR-0007](adr/0007-horloge-maitresse-unique.md)

**Livrable observable.** Session de 3 min, micro interne, bureau bruyant : 6 observations, 6
rattachées à la bonne marque. Aucune perte des 3 dernières secondes. Texte brut toujours conservé.

**Préalable obligatoire.** La mesure de dictée réelle du § 10.1, faite **avant** d'ouvrir le lot.

**À avoir compris avant de commencer.**
- `AVAudioEngine`, les taps sur `inputNode`, `AVAudioConverter` créé **une fois** hors du tap.
- `AVAudioTime.hostTime` et pourquoi il date la remise du buffer et non l'arrivée du son au micro ;
  `presentationLatency`, `kAudioDevicePropertyLatency`, `kAudioDevicePropertySafetyOffset` (§ 3.6).
  Sur AirPods, 150 à 300 ms non compensés consomment tout le budget d'erreur d'ancrage.
- `AVCaptureDevice.DiscoverySession` et l'identification des pilotes de boucle.
- La notification `AVAudioEngineConfigurationChange`.
- `SpeechAnalyzer`, `SpeechTranscriber`, `SpeechDetector`, `AnalyzerInput(bufferStartTime:)`,
  `AssetInventory`.
- `NSTextView` hors écran pour la saisie clavier (arbitrage A2 : dans le MVP).

**Piège principal.** Deux faits non documentés se combinent en un piège parfait. Sans
`SpeechDetector` dans les modules, **il n'y a aucune segmentation** : toute la session revient en
un unique résultat final. Or sur un test de vingt secondes, un unique résultat final ressemble
exactement à un fonctionnement correct. Le défaut ne se manifeste qu'en session réelle. Second
fait : **alimenter plus vite que le temps réel effondre la segmentation** — donc jamais de file de
rattrapage, on pousse au fil de l'eau depuis le tap micro.

**Troisième piège, moins technique.** Attendre le drain complet
(`finalizeAndFinishThroughEndOfInput()` **et** l'attente) à la fermeture de chaque fenêtre de
parole. Les résultats finaux arrivent 1,3 à 2,7 s après la fin de la parole : couper avant, c'est
perdre systématiquement la fin de chaque commentaire, c'est-à-dire souvent sa conclusion.

---

### Lot 6 — Serveur MCP · 3,5 j

**Objectif.** Que trois agents différents lisent le même rapport correctement, application fermée.

**ADR incarnés.** [ADR-0015](adr/0015-sidecar-mcp-stdio-disque-source-de-verite.md) ·
[ADR-0016](adr/0016-aucune-image-via-mcp.md) ·
[ADR-0014](adr/0014-journal-append-only.md)

**Livrable observable.** Le même rapport lu correctement par Claude Code, Cursor et Zed,
application fermée. Aucun appel > 10 000 jetons. Une session `handled` n'est plus proposée à un
second agent.

**À avoir compris avant de commencer.**
- La spécification MCP : outils, JSON-RPC sur stdio, forme des résultats, le plafond de 25 000
  jetons par résultat d'outil.
- Le SDK MCP Swift 0.12.1 — et la raison de l'isoler derrière une couche interne mince (R14 : il
  est en 0.12.x, la spécification MCP bouge, l'un des deux cassera).
- MCP Inspector, à utiliser **avant** tout client réel.
- Comment chacun des trois clients déclare un serveur stdio (`claude mcp add --scope user`, la
  configuration de Cursor, les serveurs de contexte de Zed).

**Piège principal.** Le sidecar est un **binaire distinct**, mais il hérite de l'identité TCC du
processus qui le lance. Un projet placé sous `~/Documents` ou `~/Bureau` déclenche au premier
`resolve_feedback` une invite « fichiers et dossiers » **au nom de l'agent** — Claude Code, par
exemple — en plein tour d'agent, et l'appel échoue sur `EPERM` (§ 9.7).
**Test explicite obligatoire d'un projet sous `~/Documents`**, avant de conclure que le lot
fonctionne.

---

### Lot 7 — Robustesse · 5 j

**Objectif.** Qu'une session de dix minutes traversée d'incidents matériels ne perde aucune marque.

**ADR incarnés.** [ADR-0005](adr/0005-cgeventtap-arbitre-unique.md) (watchdog, ré-armement) ·
[ADR-0003](adr/0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md) (segments multiples) ·
[ADR-0011](adr/0011-micro-par-fenetre-de-parole.md) (fermeture en `suspended` et sur Secure Input) ·
[ADR-0010](adr/0010-calque-ordonne-pendant-le-trace-seulement.md) (gel du rendu sous Mission Control)

**Livrable observable.** Session de 10 min avec débranchement d'écran, veille de 30 s, deux
Mission Control, une saisie 1Password, un changement de micro : aucune marque perdue, interruptions
mentionnées dans le rapport, tap actif à la fin.

**À avoir compris avant de commencer.**
- Les notifications de veille et de réveil de `NSWorkspace`.
- La gestion d'erreur de `SCStream` et le redémarrage après `-3821`.
- La détection de Mission Control et le comportement des fenêtres `.screenSaver` pendant.

**Piège principal.** C'est le lot sans fonctionnalité visible, donc celui qu'on repousse
indéfiniment ou qu'on étend sans fin. **Il se traite comme une liste de contrôle fermée**, pas
comme un chantier ouvert : chaque ligne du livrable est une manipulation à faire, un
comportement à corriger, une case à cocher. Le second chemin d'entrée sans tap (1,5 j des 5) est
une **parade à la régression Apple**, pas un mode de permission dégradé
([ADR-0005](adr/0005-cgeventtap-arbitre-unique.md), § 4.2 de la spécification) : s'il commence à
ressembler à une seconde interface complète, il est hors sujet. Et si la régression FB21879057 ne
se reproduit pas sur la version de macOS courante, ces 1,5 j sont la première marge à récupérer.

---

### Lot 8 — Distribution · 3 j

**Objectif.** Qu'une autre machine installe l'application sans avertissement et la configure en
moins de trois minutes.

**ADR incarnés.** [ADR-0002](adr/0002-hors-sandbox-developer-id.md) ·
[ADR-0004](adr/0004-preroll-opt-in.md) (l'opt-in pré-roll s'expose ici, dans l'onboarding)

**Livrable observable.** DMG téléchargé depuis une autre machine, installé sans avertissement
Gatekeeper, onboarding complet en moins de 3 min sur un compte vierge.

**À avoir compris avant de commencer.**
- Le certificat Developer ID Application (obtenu au lot 1) et les entitlements du Hardened Runtime
  nécessaires : entrée audio, et ce que la capture d'écran exige.
- Pourquoi `codesign --deep` est un piège et pourquoi les binaires internes se signent
  individuellement, de l'intérieur vers l'extérieur.
- `notarytool submit --wait`, `stapler staple`, et la fabrication du DMG.

**Piège principal.** **Le sidecar doit être signé et notarisé lui aussi.** C'est un exécutable
distinct embarqué dans le bundle ; oublié, il fait échouer la notarisation de l'ensemble ou se
fait refuser à l'exécution chez l'utilisateur.

**Second piège.** Tester sur sa propre machine, où toutes les autorisations TCC sont accordées
depuis des mois. Le passage à une signature Developer ID change l'identité du binaire : c'est
précisément le scénario « la re-signature désactive le tap », mais chez l'utilisateur. **Le test
se fait sur un compte macOS vierge, ou pas du tout.**

---

## 6. Chemin critique et parallélisation

### 6.1 Ce qui bloque quoi

```
Lot 0 ──> Lot 1 ──> Lot 2 ══> UTILISABLE (mode eclair + export manuel)
                       │
                       └──> Lot 3 ──> Lot 4 ══> UTILISABLE (boucle complete)  [GO/NO-GO 2]
                                          │
                                          ├──> Lot 5  (voix + texte)
                                          ├──> Lot 6  (MCP)
                                          └──> Lot 7 ──> Lot 8 ══> DISTRIBUABLE
```

**Chemin critique : 0 → 1 → 2 → 3 → 4 → 7 → 8**, soit 30,5 des 40 jours. Les lots 5 et 6 sont
hors chemin critique et **indépendants l'un de l'autre** : leur ordre relatif se choisit selon
l'humeur et le résultat de la mesure de dictée.

Trois dépendances non évidentes :

- **Le lot 6 dépend d'une brique du lot 4.** La bibliothèque de rendu partagée (§ 9.3) doit
  exister avant le sidecar. Si elle est écrite comme du code applicatif au lot 4, le lot 6 gonfle
  de 1,5 j.
- **Le lot 7 dépend surtout de 2 et 3**, pas de 4. La partie « survie du tap » (watchdog,
  ré-armement) est déjà amorcée au lot 0 et peut se durcir dès la fin du lot 2.
- **Le lot 8 dépend administrativement du lot 1**, pas du code : le certificat Developer ID
  s'obtient au lot 1 et la première notarisation à blanc s'y fait.

### 6.2 Ce qui peut se faire dans le désordre

Un projet du soir a des sessions de qualité inégale. Il faut garder en réserve des tâches
**utiles, indépendantes et sur terrain connu** (HTML, JS, TypeScript, Markdown, JSON) pour les
soirées où on n'a pas la tête à un callback C :

| Tâche de réserve | Lot servi | Durée |
|---|---|---|
| Les applications témoins et le banc de mesure | 0, 3, 7 | 2 h — **à faire en tout premier** |
| Le lexique déterministe de 200 termes | 5 | 3 h, purement rédactionnel |
| Le gabarit Markdown du rapport et son exemple de référence | 4 | 3 h |
| Les motifs de rédaction de secrets et leurs cas de test | 4 | 2 h |
| La liste noire d'applications par défaut | 1 | 30 min |
| Les textes d'onboarding et du doctor | 1, 8 | 2 h |
| La configuration des trois clients MCP, testée à la main | 6 | 2 h |

Cela représente une quinzaine d'heures qu'on peut consommer à tout moment. C'est aussi la parade
la plus efficace contre R15 : une soirée fatiguée qui produit le lexique vaut mieux qu'une soirée
fatiguée qui casse le tap.

### 6.3 Où sont les marges

Par ordre de facilité de récupération :

1. **Le second chemin d'entrée du lot 7** — 1,5 j, à ne dépenser que si FB21879057 se reproduit.
2. **La saisie clavier libre du lot 5** — 2 j (arbitrage A2). À ne sacrifier qu'en connaissance de
   cause : sans elle, aucun usage en open space ni en visioconférence.
3. **La vue `full_hires` et le second palier de jetons** — la variante secondaire du lot 4.
4. **Le pré-roll du lot 3** — c'est un opt-in ([ADR-0004](adr/0004-preroll-opt-in.md)), donc
   décalable après le GO/NO-GO 2 sans amputer le chemin nominal.

Il n'y a **aucune marge** dans les lots 0, 2 et 3. Ce sont les trois lots où couper produit un
produit faux plutôt qu'un produit pauvre.

---

## 7. Séquence recommandée en travail fractionné

Règles valables pour toutes les sessions :

- **On n'ouvre pas une session sans savoir son « fini quand ».** Si on ne peut pas l'écrire en
  une phrase vérifiable, on prend une tâche de réserve du § 6.2.
- **On commence par rejouer la vérification de la session précédente** (2 à 3 min). C'est la
  ré-immersion la moins chère, et elle attrape les régressions le jour même.
- **On termine par un commit**, même laid, même partiel, avec le « fini quand » atteint ou non
  écrit dans le message. Trois semaines sans commit est le signal précoce de R15.
- **Une session qui ne produit rien de vérifiable est une session perdue.** Pas un échec : une
  perte. La différence, c'est qu'on peut la constater et changer de tâche.

### 7.1 Lot 0 — 8 sessions

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S1 | 2 h | Les trois témoins et la page à trois modes | La page affiche son numéro de frame et vide son histogramme de `rAF` |
| S2 | 3 h | Bundle `.app`, `LSUIElement`, `.accessory`, certificat stable, chemin fixe | L'app tourne, pas d'icône Dock, l'icône de barre de menus apparaît, le rituel est écrit |
| S3 | 2 h | Preflights des quatre permissions | On révoque une permission, on relance, le log la **nomme** |
| S4 | 4 h | `CGEventTap` sur thread dédié, passe-plat, compteur | Le compteur monte et l'application testée se comporte comme sans tap |
| S5 | 4 h | `NSPanel` par écran + `CAShapeLayer` à chemin fixe | Trait rouge visible au-dessus de Safari plein écran, sur les deux écrans |
| S6 | 4 h | Porte à verrou + ring lock-free + display link | ⌥⌘-glisser dessine sans sélectionner ; sans ⌥⌘ tout passe → **C1, C2, C5, C6** |
| S7 | 3 h | Instrumentation de latence, ré-armement, watchdog | p95 chiffré ; le tap revient seul après désactivation forcée → **C7, C10** |
| S8 | 3 h | Banc C3b et C11, passage des douze critères | Le tableau du § 4.6 est rempli → **GO/NO-GO n°1** |

### 7.2 Lot 1 — 8 sessions

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S9 | 3 h | Structure du projet, `SessionCoordinator` vide, `NSStatusItem` portant un état | L'icône change de couleur selon un état simulé |
| S10 | 3 h | Raccourcis Carbon ⌃⌥S ouvrir, ⌃⌥F terminer, ⌃⌥M verrou micro, ⌃⌥L mode annotation verrouillé | Les quatre raccourcis répondent **sans aucune permission accordée** |
| S11 | 4 h | Doctor, moteur : chaque ligne exécute l'opération réelle | Sur un compte vierge, chaque ligne dit vrai, vérifié par révocations successives |
| S12 | 3 h | Doctor, interface SwiftUI : bouton de volet Réglages et « Relancer » par ligne | Trois clics maximum de la ligne rouge à la ligne verte |
| S13 | 3 h | Prise de contact TCC hors chemin de session, sondage horaire | `getShareableContent` au lancement et au réveil, jamais au raccourci |
| S14 | 2 h | `$TMPDIR` sécurisé (0700 / 0600 / `O_EXCL`), purge au démarrage de session, liste noire | Un fichier témoin déposé dans le dossier de session disparaît à la session suivante |
| S15 | 3 h | Hardened Runtime, entitlements, `Info.plist`, HUD SwiftUI minimal | L'app se lance signée avec le Hardened Runtime, le doctor reste vert |
| S16 | 2 h | Certificat Developer ID et une notarisation à blanc | Un DMG jetable passe la notarisation → dé-risque le lot 8 |

### 7.3 Lot 2 — 12 sessions

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S17 | 3 h | **La fonction de conversion de coordonnées seule**, avec sa table de cas | Les cas passent, écran externe non-Retina à gauche compris |
| S18 | 3 h | Panneaux industrialisés : reconstruction sur changement d'écrans, gel sur occlusion | Débrancher/rebrancher un écran en cours d'exécution ne laisse ni panneau orphelin ni panneau manquant |
| S19 | 4 h | Outil flèche, de bout en bout, du tap au `CAShapeLayer` | Une flèche se trace et reste affichée |
| S20 | 3 h | Cadre, point, surlignage | Les quatre outils se tracent, changement d'outil au clavier |
| S21 | 3 h | Numérotation au `mouseDown`, `Échap`, `⌘Z` | Le numéro apparaît à la pression ; `⌘Z` supprime sans renuméroter |
| S22 | 3 h | Ancrage à la fenêtre cible, `⌥⌘⇧` d'échappement | ⌥⌘-clic dans l'IDE ne crée pas de marque ; `⌥⌘⇧` force la capture |
| S23 | 3 h | Palette d'intentions ⌥⌘+1..6, badge sur le calque | Les six intentions se posent et s'affichent |
| S24 | 4 h | `SCScreenshotManager.captureImage` + `excludingApplications` | Un PNG est écrit, **sans un pixel du calque ni du HUD** → **R12** |
| S25 | 4 h | Recadrage, dilatation ×2,5, alignement 28, Lanczos | Un recadrage à la bonne échelle native, sans flou d'interpolation |
| S26 | 4 h | Gravure : encre, halo à luminance, badges, huit positions candidates | Contraste lisible sur thème clair **et** sombre, aucun badge recouvert |
| S27 | 3 h | Mode éclair du § 2.1 de bout en bout, écriture dans `~/Regarde/sessions/<date>/` | Une observation isolée produit son dossier complet |
| S28 | 3 h | Passage du livrable : 3 min, 6 marques, 4 outils, 2 écrans | Le critère de réussite du lot 2 est atteint et consigné |

**28 sessions pour les lots 0 à 2**, soit environ 88 heures — cohérent avec les 11,5 journées
calibrées plus la ré-immersion. À partir du lot 3, le découpage se refait lot par lot : les
tâches y sont trop couplées pour être planifiées six mois à l'avance.

### 7.4 Lot 3 — 17 sessions

Premier lot dont le découpage n'était pas écrit d'avance. Il l'est ici, à la fin du lot 2,
contre le code qui existe et non contre l'idée qu'on s'en faisait.

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S29 | 3 h | Témoin en mode compteur lisible par machine : numéro en code-barres binaire par-dessus la charge WebGL, journal de page et relevés C3b déposés sur disque par le même canal | Une commande dépose un journal de 60 s `(numéro, now)` **sans `execute javascript`**, dit combien d'entrées elle a jetées, et la cadence reste entre 70 et 90 % du natif |
| S30 | 3 h | Origine de `SessionClock` posée au lancement et recalée à l'entrée en `arming` ; `originContinuous`, `SessionTime` `Codable`, `hostTicks` transporté du tap jusqu'à `Mark.t` | Le journal donne pour chaque marque son `SessionTime` **et** l'origine de son horodatage ; une marque en mode éclair, sans session, porte `hardware` et n'incrémente pas `fallbackCount` |
| S31 | 4 h | Banc C11 : pont `performance.now()` ↔ horloge hôte, lecture du numéro gravé dans le PNG, **seuil d'acceptation écrit avant toute mesure**, ligne de base de la chaîne ponctuelle | `lot3-c11.sh` publie la latence propre de `captureImage` sans prétendre à un PASS, et **refuse** de conclure si le pont disperse de plus de 16 ms, si `fallbackCount` a bougé, ou si `--visible-capture` est actif |
| S32 | 3 h | Modèle temporel en autotest pur : `fromStream` / `pts(for:)`, `CaptureSegment` `Codable` avec `StopReason`, `assetTime()` bornée, `FrameRef`, `MotionSample`, `CaptureSegmentID` **optionnel** sur `Mark` | La section `segments` passe quatorze cas fabriqués à la main ; **retirer la soustraction de `firstSamplePTS` fait passer la section au rouge** |
| S33 | 2 h | Rotation portrait et recopie vidéo refusées nommément dans `ScreenGeometry`, refus rendu visible | Mettre un écran en recopie fait écrire son `displayID` refusé avec sa raison ; le HUD le dit, et un ⌥⌘-glisser tenté dessus est refusé avec un message |
| S34 | 4 h | Un `SCStream` par écran à la configuration du § 5.2, filtre reconstruit en cours de flux, démarrage entre `arming` et `recording`, échec empruntant `arming → idle` | Sur 20 s à deux écrans, le journal donne les frames `.complete` reçues contre le théorique et les dimensions réelles du buffer **et non 1920×1080** ; verrouiller l'écran ne laisse aucun `.mov` sous `$TMPDIR` |
| S35 | 3 h | `AVAssetWriter` HEVC par segment, GOP à 1 s, `firstSamplePTS` et `lastSamplePTS` relevés, **finalisation par segment dès le premier writer**, manifeste JSON à côté de chaque `.mov` | Deux écrans chargés pendant 60 s laissent deux `.mov` lisibles en 0700/0600 avec leur JSON ; un écran figé produit « segment vide » et non un fichier ; le comptage d'encre sur des frames extraites ne dépasse pas le témoin |
| S36 | 2 h | Débranchement : le writer d'un écran disparu est finalisé **au moment de la déconnexion**, `StopReason` renseigné sur chaque chemin d'arrêt | Débrancher l'externe en pleine session laisse l'heure de finalisation de son segment et un `lastSamplePTS` non nil ; la session continue sur l'écran restant. `lot3-debranchement.sh` rejoue en 3 min |
| S37 | 4 h | Frontière B2 en un seul contrat : ring lock-free du tap vers `encodeQueue`, seule propriétaire des frames ; anneau de 4 frames sous double garde ; appariement au PTS inférieur le plus proche | Une `dispatchPrecondition` garde chaque accès à un `CVPixelBuffer` ; 2 min sous charge sans `EXC_BAD_ACCESS` ; le journal donne copies faites contre copies évitées — **zéro sur écran figé** |
| S38 | 2 h | La frame boîtée décrite là où elle sert : `contentRect` et `scaleFactor` portés par `FrameRef` et `Engraver.Frame`. **Le modèle ne bascule pas** — `Mark` reste normalisée sur le cadre de l'écran | Une frame boîtée dont le `contentRect` est strictement inférieur au buffer passe l'autotest ; sur l'externe non-Retina à origine négative, une marque au bord droit tombe au bord droit de l'image |
| S39 | 4 h | Extraction : un seul `generateCGImagesAsynchronously` par segment, tolérances nommées, provenance inscrite par marque, budget des 3 s décomposé — **et verdict C11 rendu** | `lot3-c11.sh` rend PASS sur 8 marques posées pendant l'animation, au seuil écrit en S31 ; **retirer la soustraction de `firstSamplePTS` fait rendre FAIL** ; écran statique → 8 marques servies par le filet RAM, raison dite par marque |
| S40 | 3 h | Plan de burst du § 5.4 sous double critère de mouvement, clampé par `assetTime()`, chaque borne violée journalisée | Curseur clignotant seul et redraw plein écran unique donnent **une** image, page animée en donne trois, marque à 0,2 s de la fin en donne deux avec la borne violée nommée |
| S41 | 3 h | Les quatre budgets sur 10 min à deux écrans, soak de 20 min, série des écarts C11 dans le temps, **C3b refait en plein écran** — dette du lot 0 soldée | Les quatre nombres consignés face à leurs seuils ; la série des écarts C11 **ne dérive pas** ; six relevés C3b en plein écran, un par session neuve et dans les deux ordres, avec `glLoadLocked` identique sur les six |
| S42 | 3 h | Passage du livrable : 8 marques sur page animée, deux écrans, 10 min, débranchement en cours de route | `docs/livrables/lot3-passage.md` cite le critère mot pour mot et remplit son tableau sans case vide ; `v0.3.0` est posé sur ce commit |
| S43 | 2 h | Recette manuelle du lot 3, auditée contre le code **avant** remise, générateur prenant source et sortie en arguments | Les tests sont cochés un par un par l'auteur ; une seule commande régénère les deux pages, lot 2 et lot 3 ; les défauts trouvés sont corrigés puis étiquetés `v0.3.1` |
| S44 | 3 h | **Marge** — pré-roll opt-in : segments roulants de 10 s à 2 fps en demi-résolution, les trois derniers conservés, bascule pleine résolution à l'ouverture | Sans consentement, **rien n'est écrit** ; avec, trois segments au plus sous 8 MiB ; **verrouiller l'écran arrête toute croissance de fichier** — la couture existe : `forceSuspend` abandonne désormais le travail en vol à tout état, il reste à y brancher l'arrêt du flux |
| S45 | 2 h | **Marge** — marques rétroactives ⌥⌘ + `1`..`9`, seul consommateur du pré-roll, avec le discriminant de substitution du § 6.7 | ⌥⌘ tenu sans rien tracer puis `3` pose une marque à T−3 s servie **par le fichier encodé** ; une marque antérieure au plus ancien segment est refusée avec un message plutôt que servie par une frame fausse |

> **État au 22 août 2026 : S29 à S43 sont écrites et commitées.** Le lot est complet
> en code et instrumenté ; il n'est pas validé. Sept points du critère restent NON
> MESURÉS, tous parce qu'ils demandent la machine — deux écrans, l'autorisation
> d'enregistrement, Chrome en plein écran natif, et du temps réel qui passe. Le
> détail est dans [`livrables/lot3-passage.md`](livrables/lot3-passage.md), et
> `v0.3.0` attend le commit qui remplira son tableau.
>
> Ce qui a été prouvé sans machine : **314 vérifications d'autotest**, dont trois
> contre-épreuves qui cassent délibérément le code pour vérifier que les tests
> rougissent, et **trois invariants vérifiés mécaniquement** — le tap ne touche aucun
> tampon, l'anneau garde sa file, il n'existe qu'une seule porte vers l'asset.
>
> S44 et S45 — pré-roll et marques rétroactives — ne sont pas faites. Elles sont le
> bloc de marge du § 6.3, et le critère de fin du lot ne les mentionne pas.

**45 heures pour S29 à S43**, exactement les 6,5 journées du lot au taux de conversion du lot 2
(5,5 j pour 38 h). Les cinq heures de S44 et S45 sont en plus, et c'est voulu : voir plus bas.

#### Ce que l'ordre impose

Quatre contraintes ne se négocient pas, et elles suffisent à fixer la séquence.

**L'instrument précède l'objet.** S29 à S31 rendent B1 mesurable avant qu'une ligne d'extraction
existe. C'est la consigne du § 5, écrite ici sous forme de trois sessions plutôt que d'un
avertissement.

**Le banc ne prétend pas à un verdict qu'il ne peut pas rendre.** La chaîne du lot 2 capture dans
une `Task.detached` au relâchement (`OverlayController`, au commit d'une marque), et le lot 0 lui
a mesuré 49,1 ms de médiane et 120,9 ms au pire
([`RESULTATS.md`](../prototypes/lot0/RESULTATS.md)). Elle est structurellement hors de la
tolérance du § 4.5. S31 publie donc une **ligne de base** et quatre
refus opposables ; le verdict tombe en S39, sur la chaîne continue, qui est la seule à pouvoir le
soutenir.

**La finalisation par segment arrive avec le premier writer**, pas après la campagne de mesure.
Un écran débranché pendant un relevé emporterait sinon toute la session — y compris les marques
de l'autre écran, qui sont complètes (§ 5.5).

**B2 se ferme en un seul contrat.** S37 pose la frontière entière — ring du tap, propriété des
frames par `encodeQueue`, double garde de l'anneau — parce qu'une frontière posée à moitié est
une frontière qui ne tient pas, et que le bug qu'elle prévient n'est pas reproductible à la
demande.

#### Le seuil de C11 s'écrit avant la mesure, et pas en millisecondes

Le § 4.5 fixe la tolérance à « une frame à 60 fps, soit 16 ms ». Ce chiffre a été écrit pour le
banc du lot 0, qui mesurait un `captureImage` ponctuel. Il ne se transpose pas : le flux du lot 3
tourne à `minimumFrameInterval = 1/15` (§ 5.2), soit **66,7 ms entre deux frames encodées**. Aucune
extraction ne peut être plus fine que ça, et un seuil de 16 ms rendrait C11 infaisable par
construction plutôt que difficile.

Le critère se dit donc en **unités de compteur du témoin**, qui rend à 60 fps : le numéro gravé
dans l'image doit tomber dans l'intervalle des numéros rendus entre la frame encodée précédant le
`mouseDown` et la suivante. L'écart se publie dans les deux unités, frames et millisecondes.

Il est écrit en S31, **avant** la première mesure, et repris mot pour mot en S39. Un seuil écrit
après coup est un seuil ajusté au résultat.

C'est un amendement au § 4.5, qui reste vrai pour le lot 0 et faux pour le lot 3.

#### La marge, en bloc retirable

Le § 6.3 désigne le pré-roll comme le seul poste de marge du lot. S44 et S45 sont donc placées en
fin de lot, et elles y sont **indissociables** : le pré-roll sans les marques rétroactives est un
coût de disque sans usage, et les marques rétroactives sans le pré-roll n'ont rien à lire. On les
livre ensemble ou on les décale ensemble, après le GO/NO-GO n°2.

Tant qu'elles ne sont pas livrées, elles figurent dans « ce qui reste ouvert » du passage comme de
la recette. Le lot 3 est déclaré atteint sans elles — son critère de fin ne les mentionne pas.

#### Cinq constats trouvés en préparant le lot, et corrigés avant lui

Confronter le découpage au code a produit cinq constats. Ils sont réglés dans le commit qui
ouvre le lot : aucun n'attendait une session pour être compris, et deux étaient des pannes.

| Constat | Où | Ce qu'il produisait, et ce qu'il est devenu |
|---|---|---|
| Le contrôle de non-régression comptait `frames/*.png` et en exigeait exactement six | `lot2-livrable.sh`, bloc « Images » | **Rouge en permanence** depuis l'ajout de la vue d'ensemble, qui atterrit dans le même dossier. **Corrigé** — marques, vues d'ensemble et intrus comptés séparément, et le compte des ensembles vaut deux, un par écran annoté : accepter un seul laissait passer la perte d'un écran, sur un script dont tout l'objet est d'en exercer deux |
| `absent` était construit par soustraction du pot, puis cherché dans ce même pot | `MarkCapture.waitForCaptures` | Le filtre était vide à tous les coups : le journal comptait les captures manquantes sans jamais dire lesquelles. **Corrigé** — les marques attendues sont passées entières, les numéros absents sont nommés |
| `forceSuspend` sortait quand l'état valait `.idle` | `SessionCoordinator.forceSuspend` | **Le mode éclair vit entièrement à `.idle`** : un verrouillage d'écran pendant une observation laissait le recadrage dans le pot et la publication programmée partir derrière le verrou. Ce n'était pas une dette du lot 3, c'était une fuite dans le mode majoritaire. **Corrigé** — l'abandon du travail en vol ne dépend plus de l'état, seule la transition reste gardée |
| `Mark` est normalisée contre `screen.cocoaFrame.size` | `MarkStore.beginStroke` | Ce n'est pas un défaut mais la contrainte qui interdit à S38 de faire basculer le modèle : la frame retenue n'existe qu'après l'appariement, et le calque se retrouverait décalé de la marge de boîtage qu'on prétend supprimer. **Écrit dans le code**, avant qu'on la découvre en la cassant |
| `CFBundleShortVersionString` valait `0.1.0` | `Info.plist`, `build-app.sh` | On publiait `v0.2.1` et le bundle annonçait `0.1.0`, faute que rien ne les relie. **Corrigé** — la version se dérive du dernier tag et le `CFBundleVersion` du nombre de commits, avec repli sur le plist si le dépôt n'a pas de tag |

#### Ce que la réfutation des correctifs a trouvé en plus

Les cinq correctifs ont été soumis à quatre lentilles de réfutation avant d'être commités —
concurrence Swift 6, machine à états et sites d'appel, outillage et signature, complétude —
puis chaque constat confronté au code par un sceptique chargé de le démolir. Trente-deux
constats bruts, **quatorze retenus**, sept défauts distincts après dédoublonnage. Le premier
était dans le correctif lui-même.

| Défaut | Où | Ce qu'il produisait |
|---|---|---|
| Glob sans correspondance sous `set -euo pipefail` | `lot2-livrable.sh`, bloc « Images » | **Introduit par le correctif n°1.** `ls` sort en erreur, `pipefail` propage, `errexit` tue le script : un dossier sans marque ne donnait pas « ✗ 0 marques », il ne donnait **rien**, code 1, et la remise en place de la fenêtre en fin de script n'était jamais atteinte. Un contrôle muet au lieu d'un contrôle rouge, ce qui est pire |
| Le tracé EN COURS échappait à l'abandon | `SessionCoordinator.forceSuspend` | `count` ne compte que les marques posées : un geste interrompu par le verrou gardait son numéro et son encre, réapparaissait au geste suivant en suivant le curseur sans bouton enfoncé, et décalait toute la numérotation. `OptionGate.requestReset()`, écrit pour ce cas, n'était pas appelé |
| La cible restait gelée après une suspension | `SessionCoordinator.forceSuspend` | Une session tuée par le verrou ne reprend pas — `resumeFromSuspension` ramène à `.idle`. Mais `TargetWindow.release()` n'était appelé que par `closeSession` : `isPinned` restait vrai pour toujours et **⌥⌘ n'armait plus nulle part**, sans message, jusqu'à un ⌃⌥S suivi d'un ⌃⌥F |
| `openSession` n'annulait pas la publication éclair programmée | `SessionCoordinator.openSession` | Le même défaut que le troisième constat, sur un autre chemin d'abandon. Ouvrir une session moins de 0,8 s après un relâchement de ⌥⌘ publiait la première marque de la session dans un dossier « ÉCLAIR » séparé, puis effaçait l'encre en pleine session |
| `set +o pipefail` désarmait le script entier | `build-app.sh` | `codesign … \| sed` rendait le statut de `sed`, donc zéro quoi qu'il arrive. Une signature en échec passait inaperçue, `--verify` était avalé de même, et le bundle signé était remplacé par un bundle qui ne l'était pas sous un « ✓ Installé ». Au lancement suivant, **TCC redemandait toutes les autorisations** — la panne exacte que le certificat stable existe pour empêcher |

Les deux derniers n'étaient pas dans les cinq constats et ne venaient pas des correctifs : ils
préexistaient, sur des chemins voisins. Les corriger ici plutôt que plus tard suit ce que la
recette du lot 2 a établi — un correctif peut en casser un autre, et le chemin qu'on ne
traverse pas est celui qui casse.

### 7.5 Lot 4 — 13 sessions

Découpé le 23 août 2026, contre le code des lots 0 à 3. Dernier lot avant le
GO/NO-GO n°2 : ce qu'il livre sera jugé sur **dix jours d'usage réel**, pas sur sa
complétude au dernier commit.

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S46 | 2 h | **Neuf seuils écrits avant la première mesure**, dont les trois du § 3.2 que personne n'avait traduits en unités relevables. Quatre trous du § 9.2 tranchés, trois reports de périmètre actés. Aucune ligne de Swift | Le rapport de référence est déclaré conforme, et **retirer une de ses six sections la fait nommer** ; les neuf seuils sont dans `lot4-seuils.md`, chacun avec son unité et sa source |
| S47 | 3 h | Une seule porte vers `write(2)`, et une seule identité de session. `AppendOnlyLog` — boucle jusqu'à épuisement, reprise sur `EINTR`, `flock` consultatif. L'UUID de `SecureWorkspace` devient l'UUID de session, pas un second | **Deux PROCESSUS** écrivant 2 000 lignes de 4 Kio chacun laissent 4 000 lignes entières, aucune entrelacée. Un test mono-processus est **refusé** : verrous et threads ne prouvent rien ensemble. Retirer la boucle sur écriture courte fait rougir |
| S48 | 3 h | Le barème plafonné, puis le manifeste. Cible `RegardeRender` créée ; **aucun type du modèle applicatif ne la traverse**. `schemaVersion 1.1` avec ses réservations | La section jetons rend **4 784 / 4 675 / 1 457 / 513** sur les quatre lignes du § 9.6 ; **retirer le plafond fait annoncer 9 920** et passer au rouge. Un cinquième vecteur 8:1 rend `wp = 92` — qu'aucune des quatre lignes n'aurait révélé |
| S49 | 4 h | **La bibliothèque de rendu, posée en un seul contrat** — le piège principal du lot, et S37 a montré qu'une frontière posée à moitié ne tient pas. Deux sorties, trois profils | `--render-test` rend le rapport à partir du **seul** `manifest.json`, sans acteur ni état en mémoire, et son empreinte est celle inscrite en S46. Les trois options rendent trois sorties distinctes, exercées **sans appelant** |
| S50 | 3 h | Arborescence et identité sur une **racine paramétrée**, donc vérifiables sur un dépôt fabriqué. `index.jsonl` sous `fcntl`, `metrics.jsonl` hors projet, publieur unique | Deux **processus** obtiennent deux numéros distincts, aucune ligne déchirée ; le mono-processus est refusé — `fcntl` verrouille par processus, la seconde demande serait accordée et le test passerait au vert sur un mécanisme absent |
| S51 | 2 h | Le projet à trois états, **côté visible d'abord**. Pastilles comparées côte à côte avant la première ligne de pondération. Le sélecteur a sa **fenêtre clé propre** | Les trois teintes sont mesurées sur captures et le script **refuse de conclure si deux sont plus proches que le seuil** écrit en S46. Sur trois shells pointant trois projets, le sélecteur s'ouvre à `arming` avec ses trois candidats et leur motif |
| S52 | 3 h | La détection réelle derrière les pastilles. `proc_pidinfo` sur **tous les descendants** du terminal, provider validé par `kill(pid, 0)` et fraîcheur, **titre de fenêtre en troisième signal** | Deux signaux forts concordants → certain ; un seul → probable avec son motif ; plusieurs `cwd` → **ambigu, jamais tranché**. Le titre ajoute 0,2 et ne décide jamais seul — le retirer change le verdict d'au moins un cas |
| S53 | 3 h | **La boucle ferme, même imparfaite** — huitième session sur douze. Identité de la cible saisie avant `release()`, sept lignes de Contexte avec leurs producteurs, `state.jsonl` alimenté | Raccourci → 5 marques → raccourci écrit le dossier complet et met la phrase au presse-papiers ; collée, elle produit un diff. `git status` d'un dépôt neuf ne propose que `manifest.json`, `report.md` et `index.jsonl` |
| S54 | 3 h | Le dernier mètre. Sauvegarde du presse-papiers **item par item et type par type**, historique des trois derniers feedbacks, et le **porteur du ⏎** : une fenêtre de grâce dans le tap | Un contenu riche (RTF + TIFF + URL) **se recolle avec ses variantes**, et l'inventaire des types vus face aux types restaurés est publié, tout écart nommé. Aucun ⏎ n'est avalé hors de la fenêtre de grâce |
| S55 | 2 h | De quoi tenir dix jours sans impression : les quatre critères du § 3.2 relevables par commande, tous projets confondus. Repli déclaré, verdict de diff persisté | `lot4-gonogo.sh` imprime les quatre nombres face à leurs seuils et **refuse de conclure** sous dix jours de relevé, sous vingt tentatives d'injection, ou si aucun repli n'a jamais été noté |
| S56 | 2 h | Passage du livrable : cycle complet rejoué dans **cinq projets réels** — Warp à onglets, iTerm, tmux, un IDE — et un dépôt sous `~/Documents` | `lot4-passage.md` remplit son tableau **sans case vide**, « non mesuré » étant une valeur légitime avec sa colonne « ce qu'il faut faire ». `v0.4.0` est posé sur ce commit |
| S57 | 2 h | Recette manuelle, **auditée contre le code avant remise**, au format en quatre temps, ouverte par une section « Ne rien casser » | Les tests sont cochés un par un ; la section bloquante rejoue les livrables des lots 2 et 3, et **le mode éclair a sa section propre**. Les défauts trouvés sont corrigés puis étiquetés `v0.4.1` |
| S58 | 3 h | **Marge** — vue `full_hires` et second palier, derrière l'option `include_hires` posée en S49 | Trois `hi/full-NN@hi.png` annoncées à **4 675** jetons et facturées à moins de 10 % près ; **`schemaVersion` vaut toujours 1.1**, la clé étant réservée depuis S48 |

**32 heures pour S46 à S57**, soit 4,62 journées au taux du lot 3 (6,92 h/j) — les
4,5 journées du lot, marge d'arrondi comprise. Les 3 h de S58 sont comptées à part.

#### Ce que l'ordre impose

**Les seuils avant les mesures, et ils ne se recopient pas.** S46 écrit neuf seuils
avant la première ligne de code, dont trois que le § 3.2 énonçait en français sans
jamais les traduire en quelque chose de relevable : « une session tous les deux
jours », « la moitié des besoins », « 7 sur 10 ». Un seuil écrit après coup est un
seuil ajusté au résultat — la leçon de S31, appliquée à ce qui décide de la suite du
projet.

**La bibliothèque avant ses consommateurs.** Le § 9.3 chiffre à 1,5 jour le surcoût
d'un rendu écrit comme du code applicatif. S49 la pose en un seul contrat, avec ses
trois profils et ses quatre options — dont trois que seul le lot 6 appellera, et qui
sont exercées ici sans appelant. S37 a montré qu'une frontière posée à moitié n'est
pas une frontière.

**Le visible avant le pondéré.** S51 dessine et mesure les trois pastilles avant que
S52 n'écrive la première ligne de barème. L'ordre inverse produit trois libellés
monochromes, qui est le mode d'échec exact de R2 : un badge dont l'apparence ne
varie pas cesse d'être lu.

**La boucle tôt, à la huitième session sur douze.** Le GO/NO-GO n°2 juge dix jours
d'usage réel. Une boucle imparfaite qu'on utilise vaut mieux qu'une moitié de boucle
parfaite qu'on n'utilise pas — et les compteurs qui la mesurent sont armés en amont,
en S50 et S53, faute de quoi les soirées entre la boucle et S55 ne seraient comptées
par rien.

#### Trois hypothèses que le code a invalidées

Vérifiées une par une avant d'écrire ce tableau.

| Hypothèse | Ce que le code dit | Conséquence |
|---|---|---|
| Le HUD peut porter le sélecteur de projet | `HUDWindow.swift` : `.nonactivatingPanel`, `canBecomeKey = false`, `ignoresMouseEvents = true` | Un panneau non-clé ne peut pas porter une liste à choisir. S51 lui donne une **fenêtre distincte**, et le HUD continue de ne jamais voler le focus |
| Le `⏎` du critère a un porteur | L'application est `.accessory`, et `kVK_Return` n'apparaît **nulle part** | Aucune fenêtre ne peut recevoir la frappe. Le `⏎` devient une **fenêtre de grâce armée dans le tap**, avec sa règle de désarmement — sous peine d'avaler un `⏎` dans l'application testée (R4) |
| `LatencyHistogram` peut chronométrer la fin de session | Son échelle s'arrête à **200 ms** — 400 seaux de 0,5 ms | Il rendrait un nombre constant sur un budget de 20 s. Le chrono va dans le manifeste |

La deuxième est la plus coûteuse à découvrir tard : elle porte sur un critère
**observable** du lot, et l'autre issue aurait été d'amender le critère.

#### Ce que le lot ne fera pas, et c'est ainsi qu'il tient en 4,5 jours

Trois reports, écrits au § 11.3 dès S46 plutôt que constatés en S56 :

- **la vue `full` par marque** part au lot 6, avec son seul consommateur —
  `get_feedback_frames(view: "full")`. Le schéma la réserve dès S48, donc la version
  ne bougera pas ;
- **le bouton « Copier pour un chat web » et l'ouverture du Finder** partent au
  lot 6. Le profil de rendu est écrit et testé ici, sans appelant ;
- **le rejeu du journal** part au lot 7 avec la robustesse. Le lot 4 se borne à
  prouver que les événements survivent entiers à un `SIGKILL`.

Les deux tâches de réserve du § 6.2 — gabarit et exemple de rapport (3 h), motifs de
rédaction de secrets (2 h) — **sortent du tableau**. Le plan les désigne comme la
parade la plus efficace contre R15 ; les souder au chemin critique supprimerait la
soupape au pire endroit, c'est-à-dire au dernier lot avant le point d'arrêt. S46 et
S49 les **consomment**, ne les contiennent pas.

#### Ce que la réfutation a corrigé

Dix-sept défauts bloquants, sur trois lentilles — code réel, couverture de la
spécification, mesurabilité du GO/NO-GO. Les quatre qui changeaient le découpage :

- **le sélecteur de projet n'existait dans aucune session**, alors que le § 8.2
  définit l'état ambigu *par* son ouverture et qu'ADR-0017 retient l'option D ;
- **une session présentait comme un renommage la création d'une seconde variante
  d'image** — il n'y en a qu'une par marque aujourd'hui, et `Cropper.Kind.full` est
  un repli au-delà de 40 %, qui aurait collisionné avec l'espace de noms `full-NN` ;
- **deux tests passaient au vert sur un mécanisme absent** : deux publieurs du même
  processus obtiennent toujours leur `fcntl`. Les tests exigent désormais deux
  processus et refusent le mono-processus ;
- **le mode éclair n'était traité par aucune brique**, alors qu'il vit entièrement à
  `.idle` — le mode majoritaire, et le seul chemin qu'un développement centré session
  ne traverse jamais. C'est exactement le défaut que le lot 3 y avait déjà trouvé.

---

### 7.6 Lot 5 — 17 sessions

Découpé le 27 août 2026, contre le code des lots 0 à 4 (v0.4.1). Le lot commence
par la seule mesure du plan capable de le re-cadrer entièrement : la dictée réelle
du § 10.1 n'a jamais été faite, et sa table de décision peut déplacer une journée
ou renverser la conception. Elle ouvre donc le lot au lieu de le précéder.

| # | Durée | Objectif | Fini quand |
|---|---|---|---|
| S59 | 2 h | **La mesure qui décide du lot** — le CLI de 50 lignes du § 10.1, la dictée réelle de 3 min (spontanée, jargon délibéré, micro interne), le comptage à trois nombres. Les arbitrages en attente sont tranchés par écrit : A2 (texte clavier dans le lot), frontière revue/purge (A5 — la purge reste au lot 7) | Les trois nombres — termes prononcés, corrects, erreurs **plausibles** — sont datés dans `lot5-seuils.md` avec la décision de la table § 10.1, **réconciliée ce jour avec le § 7.3 : un terme sur cinq décide, pas 2/3**. Le CLI expose les **segments** : le même fichier sans `SpeechDetector` en rend UN seul — le fait de sonde n°1 est reproduit chez nous, pas cru sur parole |
| S60 | 2 h | **Les seuils et contrats écrits avant la première ligne d'audio.** Budget d'ancrage du « premier mot », format ligne de `transcript.txt` (§ 9.2, versionnable), extension § 9.5 `marks[].voice[]` et schéma de `MarkShape.text`, et les trous réellement ouverts : **les modalités de la voix en éclair** — le principe est tranché par la spec, l'éclair parle ; restent le sort de l'éclair silencieux face au `flashGrace` de 0,8 s, l'armement de l'analyseur hors session, l'horodatage sans horloge de session —, la règle d'affichage de `locale` et latence dans l'en-tête, le sort des paroles d'une marque annulée par `undoLast()` | Chaque seuil a son unité et sa source dans `lot5-seuils.md` ; le décodeur du lot 4 **accepte** un manifeste étendu fabriqué, et l'empreinte du rapport de référence du lot 4 tient inchangée |
| S61 | 3 h | Le micro par fenêtre, **sans transcription**. Sélection du périphérique — jamais l'entrée par défaut, exclusion des pilotes de boucle par fonction PURE sur les marqueurs réels (`MSLoopbackDriver` est sur cette machine), préférence micro interne. `AVAudioEngine` par fenêtre, converter créé une fois hors du tap, latence § 3.6 sommée et journalisée, `ConfigurationChange` → reconstruire et remesurer. Fermeture d'office : `IsSecureEventInputEnabled()` et `suspended` | L'autotest de sélection exclut « Microsoft Teams Audio » et préfère l'interne sur la liste réelle de la machine ; la latence est au journal avec ses trois termes ; verrouiller l'écran pendant une fenêtre la ferme d'office avec sa trace. `when.isHostTimeValid` faux → repli compteur d'échantillons, tracé |
| S62 | 3 h | La chaîne `SpeechAnalyzer` **au fil de l'eau** : transcriber + `SpeechDetector(reportResults: false)` gardé en **défense en profondeur**, `AnalyzerInput(bufferStartTime:)` portant le temps de session compensé — en échantillons entiers, jamais en secondes flottantes —, `AssetInventory` sans condition, deux tampons — le final AJOUTE, le volatil REMPLACE | Le harnais de S59 **mesure** les trois modes (nominal, sans detector, plus vite que le réel) et consigne leurs comptes de segments dans `lot5-seuils.md` — sur macOS 26.1 ils sont identiques, les faits de sonde d'ADR-0012 ne se manifestent plus, et le harnais le re-dira à chaque mise à jour système. Concaténer les volatils fait rougir |
| S63 | 3 h | **La fenêtre de parole, machine à états PURE** sur événements horodatés : ouverture à la prise ⌥⌘, fermeture 8 s après relâchement prolongée par les volatils, plafond dur 20 s, geste global > 400 ms sans tracé, verrou ⌃⌥M. Les quatre règles de rattachement tracées : `.fenetreDeParole`, `.debordement`, `.gesteGlobal`, `.aucuneFenetre` — le premier mot décide, jamais une inférence | La table de cas est exhaustive en autotest, chaque règle avec sa contre-épreuve : un segment dont le premier mot tombe 1 ms **après** la fermeture est global, pas rattaché ; deux fenêtres successives donnent une timeline discontinue mais **monotone** ; les volatils ne prolongent jamais au-delà de 20 s |
| S64 | 2 h | Le branchement au geste réel : `OptionGate` ouvre la fenêtre, le badge **pulse** tant qu'elle vit, le calque n'est retiré qu'à sa **fermeture** — changement assumé face aux lots 2-4 —, HUD « commentaire général », ⌃⌥M réel avec bandeau permanent et `.muted` déjà au contrat | Une session courte parlée rattache le segment à la marque, au journal ; ⌃⌥M pendant une phrase la bascule en global et le bandeau reste jusqu'au déverrouillage ; **l'éclair parle — la spec l'a tranché** — selon les modalités arrêtées en S60 : le mode majoritaire n'est pas oublié, c'est la leçon des réfutations des lots 3 **et** 4 |
| S65 | 3 h | La table ADR-0021 devient entièrement réelle : rétroactive T−N (fenêtre sans marque), `⇧ + chiffre` réaffecte le segment en cours, `⌥⌘ + 0` le bascule en global, `attachment.manual` écrase tout et n'est **jamais recalculé**. Le badge de la marque cible s'illumine **sur le calque**, à sa position | L'autotest couvre les trois lignes de la table × leurs cas ; en réel, ⌥⌘ puis `3` puis `2` enchaîne rétroactive et intention « erreur » ; `7`..`9` en mode intention font flasher l'invalidité et n'appliquent **rien**. Les codes physiques restent la seule identité des chiffres |
| S66 | 3 h | **Le drain dans le chemin ordonné de la publication** — même place, même leçon que l'arrêt des flux du 23 août, jamais un Task détaché. `finalizeAndFinishThroughEndOfInput()` **et** l'attente, composés dans le budget de 20 s de fin. `transcript.txt` écrit par la porte d'append unique, `rawText` conservé | Fermer ⌃⌥F **au milieu d'une phrase** met la fin de la phrase dans le rapport — « aucune perte des 3 dernières secondes » est LE critère du lot, et couper le drain (drapeau d'essai) fait rougir en la perdant. `git status` propose maintenant **cinq** chemins : `transcript.txt` est versionnable, et les tests du lot 4 qui exigeaient quatre sont **mis à jour dans la même session** |
| S67 | 3 h | Manifeste étendu et rendu de la voix, dans `RegardeRender` pur : `marks[].voice[]`, citations en blockquote sous chaque marque, « Commentaires généraux » réels — `- **01:52** — « … »` remplace le `- aucun.` en dur —, `zoneNote` remplie depuis la voix, `session.locale` et `audioInputLatencyMs` | `--render-test` rend un manifeste fabriqué avec voix depuis le **seul** JSON ; un segment global et un segment rattaché rendent deux formes distinctes ; zéro commentaire rend encore « - aucun. » ; **l'en-tête ne rend la locale et la latence que si le manifeste porte de la voix** — une session au micro refusé n'a rien à en dire — ; l'empreinte du rapport de référence du lot 4 est **inchangée** |
| S68 | 2 h | Le lexique déterministe : ~200 termes front figés + identifiants extraits du projet cible — S52 sait déjà lequel —, distance phonétique appliquée aux **seuls** mots de confiance < 0,6, les deux versions au rapport : `pratique` *[padding ?]* | Un mot à confiance 0,9 n'est **jamais** corrigé — la contre-épreuve du seuil ; un mot < 0,6 phonétiquement proche reçoit sa double version ; l'extraction sur un dépôt fabriqué sort les identifiants attendus et eux seuls |
| S69 | 3 h | **Le clavier, le fait de sonde d'abord** (A2) : le tap consomme, `NSEvent(cgEvent:)` nourrit un `NSTextView` **hors écran** via `interpretKeyEvents` — **aucune fenêtre clé**, l'application testée garde son focus, c'est la régression que le produit promet d'éviter. Touches mortes françaises | « é, à, ï, ç » traversent fidèlement pendant une session **sans** que l'application testée perde l'état clé — un champ web garde son curseur pendant la frappe ; les IME asiatiques sont hors périmètre, écrit. Le § 6.3 chiffrait ce périmètre à deux journées : le scinder en deux sessions est la réponse, pas le nier |
| S70 | 3 h | **La marque texte de bout en bout** : `MarkShape.text` au modèle (schéma posé en S60), le calque l'affiche, l'`Engraver` la grave, `RegardeRender` la rend ; Échap abandonne sans rien poser | Une marque texte traverse du geste au rapport publié — gravée dans le PNG **et** rendue dans le markdown ; Échap ne laisse aucune trace ; les autotests marques, rendu et boucle couvrent le nouveau genre |
| S71 | 3 h | **Le bandeau de confirmation et la revue à la demande** — le périmètre § 11.3 que la première version de ce chapitre laissait à une provision conditionnelle. Les quatre actions du § 2.2 — [⏎ Envoyer] [R Revoir] [⌫ Annuler] [V Voir les images] — complètent la fenêtre de grâce de S54, avec les compteurs du § 6.6 ; R ouvre la revue : édition inline du texte (`rawText` conservé), suppression d'une marque ou d'un segment, bande de vignettes § 10.3 | R pressé dans les 8 s ouvre la revue, qui ne s'ouvre **jamais** seule ; une édition conserve `rawText` au manifeste ; supprimer une marque retire son image du rapport publié ; le budget dur de 20 s du § 6.6 tient, chrono au manifeste |
| S72 | 2 h | La permission micro au **premier usage réel**, jamais au lancement ; refusée → la palette d'intentions et le clavier restent, comme le doctor le promet depuis le lot 1. Le doctor gagne la ligne de latence d'entrée | Sur un état TCC réinitialisé (`tccutil`), la première fenêtre de parole déclenche l'invite — pas le démarrage ; refuser laisse la session entièrement utilisable, la fenêtre se ferme avec sa trace, et rien ne redemande à chaque geste |
| S73 | 2 h | **Passage du livrable** : session de 3 min, micro interne, bureau bruyant réel — 6 observations, 6 rattachées à la bonne marque, texte brut conservé, bandeau et revue rejoués. `lot5-passage.md` sans case vide, « non mesuré » valeur légitime | Les 6/6 sont constatés sur le rapport publié, pas au journal ; la dernière observation chevauche ⌃⌥F et sa fin est là. `v0.5.0` est posé sur ce commit |
| S74 | 2 h | Recette manuelle, auditée contre le code avant remise, quatre temps, section « Ne rien casser » bloquante — les livrables des lots 2, 3 **et 4** s'y rejouent ; l'éclair, le clavier et le couple bandeau-revue ont leurs sections propres | Les libellés donnés à VOIR existent au caractère dans les sources — l'audit est un script ; les défauts trouvés sont corrigés puis étiquetés `v0.5.1` |
| S75 | 3 h | **Marge** — AirPods et périphérique agrégé : la latence de 150-300 ms compensée dans `bufferStartTime`, le repli compteur d'échantillons éprouvé sur un agrégé réel, `ConfigurationChange` en pleine fenêtre | Une session AirPods rattache ses observations aux bonnes marques malgré la latence ; débrancher le périphérique **pendant une phrase** reconstruit le moteur sans perdre la fenêtre ni recréer l'analyseur |

**41 heures pour S59 à S74**, soit 5,92 journées au taux du lot 3 (6,92 h/j) — le
budget de 6 j, marge d'arrondi comprise, comme au lot 4. La « provision » de la
première version de ce chapitre a disparu : la journée qu'elle gardait en réserve
finançait en réalité un périmètre normatif — le bandeau et la revue du § 11.3 —
qui est désormais dans le tableau, dans **toutes** les branches du § 10.1. La
branche médiane de la dictée ajoute son +1 j au lot, comme sa table l'écrit ; la
soupape R15 reste les tâches de réserve du § 6.2. Les 3 h de S75 sont comptées à
part.

#### Ce que l'ordre impose

**La mesure avant les seuils, les seuils avant l'audio.** S59 peut re-cadrer le lot
entier — la faire en premier coûte 2 h, la découvrir en S66 coûterait six jours. Et
S60 écrit les contrats avant la première ligne d'`AVAudioEngine` : un format de
`transcript.txt` décidé pendant qu'on l'écrit est un format ajusté au code — la
leçon de S31 et de S46, une troisième fois.

**Le modèle pur avant le branchement.** S63 épuise les règles de rattachement sur
une machine à états sans micro ni moteur — comme `decision()` du porteur ou
l'assembleur de S53. Le premier mot, le débordement, le plafond : tout se juge sur
des événements fabriqués, reproductibles, avant qu'un seul buffer réel n'existe.
L'ordre inverse déboguerait la sémantique à travers deux couches d'asynchronisme.

**Les faits de sonde deviennent des tests rouge/vert avant les sessions réelles.**
La segmentation qui s'effondre quand on pousse plus vite que le temps réel (S62)
est invisible en session courte et ruineuse en session longue. Le harnais de S59
sert de banc : le fait n'est pas une note de bas de page, c'est un test qui rougit.

**La voix arrive au rapport à la huitième session sur dix-sept.** S66 et S67
ferment la boucle voix → transcript → manifeste → rendu avant le lexique, le
clavier, le bandeau et la permission — la règle du lot 4 : une boucle imparfaite
qu'on utilise vaut mieux qu'une moitié de boucle parfaite.

#### Ce que le harnais a montré avant la première session

Le CLI de S59 (`Tools/lot5-dictee.swift`), construit le 29 août et exercé sur une
dictée de synthèse de 75 s : sur **macOS 26.1**, les deux faits de sonde
d'ADR-0012 ne se manifestent plus — sans `SpeechDetector` la segmentation est
identique (7 segments dans les trois modes), et pousser plus vite que le temps
réel ne dégrade rien. C'est le risque résiduel que l'ADR nommait : « révisable
par mise à jour macOS sans note ». La révision a eu lieu, dans le bon sens. Le
produit GARDE le detector et le fil de l'eau — défense en profondeur contre les
versions qui régresseraient —, mais aucun critère n'exige plus de reproduire des
effondrements que le système ne produit plus : le harnais les **mesure** et
consigne, à chaque mise à jour système. Deux leçons d'implémentation gagnées au
passage : le temps de `bufferStartTime` se compte en échantillons entiers (une
somme de secondes flottantes chevauche d'un tick et le moteur refuse l'audio), et
il suit les échantillons **sortis** du converter, pas les entrants (les résidus
de conversion créent des trous qui hachent les mots).

#### Quatre hypothèses que le code a confirmées ou invalidées

Vérifiées contre v0.4.1 avant d'écrire le tableau.

| Hypothèse | Ce que le code dit | Conséquence |
|---|---|---|
| Le verrou micro ⌃⌥M est à construire entièrement | `main.swift:204` : une ligne de journal — mais `IntentionOutcome.muted(Int64)` existe déjà, et `HotKeyCenter` ré-enregistre `m` par disposition | Le contrat est prêt, seul le comportement manque — S64 branche, ne conçoit pas |
| Le manifeste devra être étendu pour la voix | `Manifeste.Mark.zoneNote` est réservé avec son commentaire « le lot 5 la remplira », mais **aucun** champ `voice` n'existe et « Commentaires généraux » est un littéral en dur dans `Rendu.swift` — et l'exemple normatif du § 9.5 montre `voice[]`, `locale` et `audioInputLatencyMs` **sous `schemaVersion` 1.1** | Pas de montée de version : les champs voix sont des membres **optionnels** du schéma 1.1, absents = manifeste identique à l'octet. S67 remplace le littéral — et le décodeur du lot 4 doit accepter un manifeste étendu, c'est un critère |
| Le drain peut vivre dans un `Task` à la fermeture | `closeSession()` porte la leçon du 23 août : deux tâches sans ordre garanti = liste vide lue. L'arrêt des flux est DANS le chemin ordonné de la publication | Le drain s'insère au même endroit, séquencé — S66 le dit dans son critère |
| `git status` à quatre chemins survivra au lot 5 | `transcript.txt` est **versionnable** (§ 9.2) : cinquième chemin. `BoucleSelfTest` juge par égalité d'ensembles et rougira, la recette du lot 4 dit « exactement quatre » | S66 met à jour le test, le `.gitignore` et les cahiers **dans la même session** — un vert cassé qu'on répare plus tard est un vert qu'on ne croit plus |

La quatrième est la plus sournoise : elle ferait échouer un test du lot **précédent**
au milieu du lot 5, précisément le genre de rouge qu'on apprend à ignorer.

#### Ce que le lot ne fera pas, et c'est ainsi qu'il tient en 6 jours

- **la purge du plafond de 15 min (A5)** part au lot 7 avec la robustesse — la
  revue à la demande, elle, est livrée en S71 : la première version de ce chapitre
  la croyait conditionnelle, la réfutation a montré que le § 11.3 la met au
  périmètre sans condition ;
- **les IME asiatiques** sont hors périmètre de la saisie clavier, écrit en S69 —
  les touches mortes françaises sont gratuites, la composition CJK ne l'est pas ;
- **le service du transcript par MCP** n'existera jamais (§ 9.2 : « jamais servi
  par MCP ») — le lot 6 n'aura rien à en dire ;
- **le mode économe micro** part au lot 12 avec le reste de l'économie d'énergie.

Les tâches de réserve du § 6.2 restent hors tableau, pour la même raison qu'au
lot 4 : soudées au chemin critique, elles cesseraient d'être une soupape.

#### Ce que la réfutation a corrigé

Quatre lentilles — norme, code réel, mesurabilité, arithmétique —, dix défauts
vérifiés sur pièces, six confirmés. Les quatre qui changeaient le découpage :

- **le bandeau et la revue à la demande n'étaient construits par aucune session**,
  alors que le § 11.3 les met au périmètre du lot sans condition — et la
  « provision » ne les finançait que dans une branche du § 10.1. S71 les livre,
  dans toutes les branches, et la provision a disparu ;
- **la table § 10.1 contredisait le seuil normatif** : elle concluait « tel que
  spécifié » dès 2/3 de termes corrects, là où le § 7.3 et le signal de révision
  d'ADR-0012 exigent 4/5 — entre les deux, le plan aurait déroulé dix-sept heures
  de voix que les textes interdisent. La table est réconciliée, S59 applique la
  version alignée ;
- **« l'éclair parle-t-il ? » n'était pas un trou** : la spécification le tranche,
  l'éclair parle. Les vraies questions ouvertes sont les modalités — l'éclair
  silencieux face au `flashGrace` de 0,8 s, l'armement de l'analyseur hors
  session, l'horodatage sans horloge de session. S60 les pose, S64 applique la
  réponse de la spec, pas « une décision, quelle qu'elle soit » ;
- **la saisie clavier tenait en 3 h** là où le § 6.3 la chiffre à deux journées :
  S69 et S70 la scindent — le fait de sonde d'abord, la marque texte de bout en
  bout ensuite — et le schéma de `MarkShape.text` part en S60 avec les autres
  contrats.

Deux retouches de précision complètent : l'en-tête ne rend la locale et la latence
d'entrée que si le manifeste porte de la voix — une session au micro refusé n'a
rien à en dire — ; et l'arithmétique de la provision confondait 6,52 h et 6,92 h,
erreur morte avec la provision elle-même.

---

## 8. Vérifications permanentes

Ce qui est vérifié une fois est vérifié pour une version de macOS et une signature. Les deux
changent.

| Vérification | Comment | Fréquence |
|---|---|---|
| **Exclusion du calque des pixels** (R12) | Ouvrir un PNG exporté et y chercher l'encre, un badge, le HUD | À chaque lot ≥ 2, **et à chaque mise à jour de macOS, mineure comprise** — `sharingType = .none` est déjà tombé une fois en 15.4 |
| **Tap encore actif** | Le compteur d'événements du lot 0, conservé en mode debug | **Avant chaque séance de débogage**, et systématiquement après une re-signature |
| **Permissions sur compte vierge** | Créer un compte macOS de test, y installer, dérouler l'onboarding | À chaque lot ≥ 1, et avant chaque version distribuée |
| **Régression FB21879057** | Auto-test au lancement : panneau au-dessus d'une application en plein écran natif | À chaque version de macOS ; **1 j budgété par version majeure** |
| **C3b — coût de composition** (R8) | Protocole du § 4.4, trois états | Lots 0, 2, 3 et 7 — le calque grossit à chaque lot |
| **C11 — appariement marque ↔ frame** (R5) | Banc du § 4.5, témoin en mode compteur | Lot 3 (verdict), puis lot 7 et à chaque changement d'un paramètre d'encodage |
| **Masquage et liste noire** (R11) | Ouvrir une notification pendant une session, vérifier qu'elle est noircie dans l'export | À chaque lot ≥ 4 |
| **Restauration du presse-papiers** | Copier un contenu riche, faire une session, coller ailleurs | À chaque lot ≥ 4 |
| **Événements synthétiques** (C12) | Karabiner ou un pilote de souris tiers installé, refaire C1/C2/C5 | Avant le lot 2, puis avant chaque version distribuée |
| **Coût en jetons** (R3) | Le coût affiché marque par marque, contre un comptage réel | À chaque lot ≥ 4, et à chaque changement de palier de redimensionnement |

Deux rituels courts valent mieux qu'une campagne : la vérification du tap prend dix secondes,
celle du calque dans les pixels en prend trente.

---

## 9. Suivi des risques

| # | Risque | Lot de la parade | Signal précoce | Comment on le surveille |
|---|---|---|---|---|
| R1 | Permissions rebutantes | **1** | Plus de 5 min pour un « tout vert » sur compte vierge, ou on ne sait pas soi-même laquelle manque | Chronométrer l'onboarding sur compte vierge à chaque lot |
| R2 | Rapport dans le mauvais projet | **4** | Le HUD affiche la même confiance quel que soit le contexte | Relire le champ « projet » des 10 derniers `manifest.json` |
| R3 | Explosion du coût en jetons | **4**, complété au **6** | Erreur « response exceeds maximum allowed tokens (25000) », ou l'agent perd le fil | Comparer le coût affiché au comptage réel, marque par marque |
| R4 | Latence de bascule, événements volés | **0** | Le trait démarre à côté du point de départ | C5, rejoué à chaque lot ≥ 2 |
| R5 | Frames décalées (B1) | **3** | **Aucun signal sur écran statique** — visible uniquement au test C11 | Banc du § 4.5, seul instrument existant |
| R6 | Crash intermittent sur l'instantané (B2) | **3** | `EXC_BAD_ACCESS` dans `CVPixelBufferRelease`, fréquence proportionnelle à l'activité écran | Sessions longues sur contenu très animé, pas sur écran fixe |
| R7 | Qualité du français sur le jargon | Mesure **avant 5**, parade au **5** | Plus d'un terme technique sur trois à corriger mentalement en relisant ses rapports | Mesure de dictée du § 10.1, refaite après ajout du lexique |
| R8 | L'outil fausse le test de performance | **0** (C3b), mode économe au **12** | FPS mesurablement plus bas session ouverte | C3b aux lots 0, 2, 3, 7 |
| R9 | Tap désactivé silencieusement | **0** (watchdog), durci au **7** | « Ça marchait il y a dix minutes » | Compteur d'événements permanent en debug |
| R10 | Régression Apple sur les fenêtres transparentes | **0** (l'architecture y survit), parade au **7** | Auto-test au lancement | 1 j par version majeure de macOS |
| R11 | Fuite de contenu privé | **1** et **4** | Ouvrir une capture et y voir une notification privée | Contrôle visuel des exports, à chaque lot ≥ 4 |
| R12 | Calque dans les pixels capturés | **2** | Voir le HUD dans une image exportée | Contrôle visuel, à chaque version de macOS |
| R13 | Conflit du modificateur | **2** | Ne plus pouvoir faire un geste habituel dans son propre IDE | Usage réel quotidien — c'est le seul détecteur |
| R14 | Dérive des dépendances non contractuelles | **4** (détection projet) et **6** (SDK) | Une mise à jour de Claude Code et la détection retombe à zéro | Vérifier la détection après chaque mise à jour de l'agent |
| R15 | **Enlisement du projet personnel** | Le plan lui-même | **Trois semaines sans commit** ; le lot en cours ne produit rien d'utilisable | Regarder l'historique git une fois par mois. Si le signal est là : prendre une tâche de réserve du § 6.2, pas une tâche héroïque |

R15 est le mode d'échec le plus probable, et le seul dont la parade ne soit pas technique :
produit utilisable au lot 2, boucle complète au lot 4, aucun lot au-delà de 6,5 j, deux points
d'arrêt honorables, et lots 9 à 12 interdits.

---

## 10. Mesures à faire avant de coder

Deux chiffres conditionnent le contenu de deux lots. Les obtenir tard, c'est découvrir après
plusieurs jours de travail qu'on construisait la mauvaise chose.

### 10.1 La dictée réelle de trois minutes — avant le lot 5

**Pourquoi maintenant.** Cette mesure ne demande **aucune connaissance d'AppKit** : un outil en
ligne de commande d'une cinquantaine de lignes qui lit un fichier audio et le passe dans
`SpeechAnalyzer`. Elle peut se faire n'importe quel soir, très tôt dans le projet, et son résultat
peut changer le dimensionnement du lot 5 de deux journées.

**Protocole.**

1. Enregistrer 3 minutes de parole **réelle** : soi-même, dans sa pièce habituelle, au micro
   interne, en commentant une vraie application comme on le ferait en session. Pas un texte lu :
   les hésitations, les reprises et le débit spontané font partie de ce qu'on mesure.
2. Y placer délibérément le jargon du quotidien — noms de composants du projet, `useEffect`,
   « le endpoint `/api/cart` », « le composant Checkout », des anglicismes prononcés à la française,
   des identifiants en `camelCase`.
3. Passer l'enregistrement dans la configuration **exacte** du lot 5 : `fr-FR`,
   `preset: .timeIndexedProgressiveTranscription`, `SpeechDetector` présent,
   `attributeOptions: [.audioTimeRange, .transcriptionConfidence]`.
4. Compter trois choses : le nombre de termes techniques prononcés, combien sont correctement
   transcrits, et combien d'erreurs sont **plausibles** — un mot faux qui se lit comme du français
   valide, donc indétectable par la confiance et invisible à la relecture rapide.

**Décision selon le résultat.**

| Termes techniques corrects | Décision |
|---|---|
| **Plus de 4/5** | Lot 5 tel que spécifié. Le lexique déterministe de 200 termes plus les identifiants du projet couvrent le reste. |
| **Entre 1/3 et 4/5** | La saisie clavier passe devant — S69 et S70 remontent avant la chaîne voix —, l'extraction automatique des identifiants passe de confort à exigence, et l'édition inline devient le chemin principal de la revue, pas un repli. Prévoir +1 j sur le lot 5. |
| **Moins de 1/3** | La voix n'est plus le canal principal. La saisie clavier (arbitrage A2) devient le mode par défaut, la voix un complément, et le lot 5 se re-cadre autour de la saisie. **C'est un changement de conception qu'il vaut mieux faire avant d'écrire une ligne, pas après six jours.** |

*Table réconciliée le 27 août 2026 par la réfutation du découpage (§ 7.6) : la
première ligne disait « plus de 2/3 », en contradiction avec le § 7.3 de la
spécification et le signal de révision d'ADR-0012 — « au-delà d'un terme sur cinq
à corriger, le lot 5 tel que spécifié n'est pas livrable et la saisie clavier
passe devant ». Le seuil normatif l'emporte.*

Le taux d'erreurs *plausibles* est le second chiffre à surveiller : au-delà d'une par minute, la
convention `[terme ?]` du rapport ne suffit pas, parce qu'elle ne se déclenche que sur les erreurs
que le lexique a repérées.

### 10.2 Le coût de composition C3b — au lot 0

**Protocole.** § 4.4 : trois états, deux comparaisons, relevés faits dans les deux sens.

**Décision selon le résultat.**

| Résultat | Décision |
|---|---|
| État 2 < 1 % **et** état 3 < 5 % | GO. C'est le cas attendu, et c'est ce que l'[ADR-0010](adr/0010-calque-ordonne-pendant-le-trace-seulement.md) fait tenir. |
| État 2 > 1 % | **Défaut d'implémentation, à corriger avant le lot 1.** Quelque chose reste composité en permanence : un panneau ordonné qui n'a pas été retiré, une couche conservée, un effet visuel. Il n'y a rien à arbitrer, seulement à trouver. |
| État 2 < 1 %, état 3 entre 5 et 15 % | Acceptable sous condition. La dégradation n'existe que pendant le tracé, soit quelques secondes par session. On simplifie le rendu d'encre — moins de couches, rastérisation plus agressive des marques posées — et on documente le chiffre. |
| État 3 > 15 % | Le **lot 12** (mode économe explicite, 1 j) cesse d'être une amélioration post-MVP et devient une parade : il remonte dans le MVP, en bascule affichée. Et le produit doit dire, dans son propre rapport, qu'une mesure de performance faite session ouverte n'est pas fiable. |

Le cas où l'on ne mesure pas du tout est le seul vraiment mauvais : on livre alors un outil de
diagnostic de lenteur qui est peut-être la cause de la lenteur diagnostiquée (R8), et on ne le
saura jamais.

---

## 11. Ce qu'on ne fait pas avant d'avoir livré

| Lot | Périmètre | Effort |
|---|---|---|
| 9 — Providers natifs | Registre avec budget 150/250 ms, liste noire, consentements depuis les réglages uniquement. Terminal via AX, Simulateur via `simctl`, URL via AppleScript. | 5 j |
| 10 — Extension Chrome MV3 | Sélecteur CSS sous la marque, console à la source, WebSocket vers 127.0.0.1. | 5 j |
| 11 — Canal push Claude Code | `capabilities.experimental["claude/channel"]`. Jamais sur le chemin critique. | 3 j |
| 12 — Mode économe explicite | Bascule demi-résolution / 2 fps en session. | 1 j |

**La règle : aucun de ces quatre lots ne commence avant que les lots 0 à 8 soient livrés**,
livré signifiant un DMG installé et fonctionnel sur une machine qui n'est pas celle de
développement. Pas « presque fini », pas « il reste deux détails au lot 7 ».

Cette règle existe contre une tentation précise. Le **lot 10** est cinq jours de TypeScript, de
`WebSocket` et de MV3 : terrain d'origine, hot reload, dopamine immédiate, aucun débogage TCC
aveugle. C'est pour ça qu'il est dangereux. Cinq jours passés là produisent une extension qui ne
sert à rien tant que le noyau n'est pas distribuable, pendant que le lot 7 — pénible, invisible,
et strictement nécessaire — attend. Le [protocole `ContextProvider` est figé dès maintenant](adr/0019-providers-hors-mvp-protocole-fige.md) précisément pour que ces lots restent
faisables plus tard sans être commencés aujourd'hui.

Une seule exception, et elle est conditionnelle : **le lot 12 remonte dans le MVP si et seulement
si C3b dépasse 15 %** (§ 10.2). Il ne s'agit alors plus d'une optimisation mais d'une parade à R8,
et une parade à un risque avéré n'est pas du post-MVP.

Les tâches de réserve du § 6.2 sont la soupape prévue pour les soirées de faible énergie. Elles
servent les lots 0 à 8. C'est là qu'il faut aller quand l'envie de commencer l'extension Chrome
se fait sentir.
