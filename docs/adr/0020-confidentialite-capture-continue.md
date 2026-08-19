---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 1 et 4
---

# ADR-0020 — Cinq mesures de confidentialité pour une capture continue de l'écran entier

## Contexte

Regarde filme l'écran entier en continu ([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)),
éventuellement avant même que le développeur ait décidé d'ouvrir une session
([ADR-0004](0004-preroll-opt-in.md)), et ouvre le micro. Sur cet écran il y a le gestionnaire de mots
de passe resté ouvert, la messagerie, l'autre projet client. En sortie, des images et un texte partent
chez un tiers — l'agent — par une action délibérée de l'utilisateur.

Le mode de défaillance visé (R11) n'est pas un bug mais un **incident** : un contenu privé publié,
qui ne se répare pas et se constate. Les garanties doivent être explicites, vérifiables, et tenir
sans discipline de l'utilisateur.

## Décision

Cinq mesures, chacune posée sur un point distinct du chemin de la donnée.

1. **Fichier vidéo intermédiaire** : écrit dans `NSTemporaryDirectory()` (`/var/folders/.../T/`),
   répertoire en `0700`, fichier en `0600`, création en `O_EXCL` ; purge **au démarrage de chaque
   session**, pas seulement au lancement de l'application ; suppression immédiate en `publishing`,
   dès l'extraction de la dernière frame. À défaut, `isExcludedFromBackup = true`.
2. **Liste noire d'applications** dans `SCContentFilter(display:excludingApplications:)` — par
   défaut 1Password, Trousseau d'accès, Messages, Mail, Signal, WhatsApp, éditable.
3. **Masquage des fenêtres tierces à la composition** (§ 5.6) : toute fenêtre n'appartenant pas à
   l'application cible et recouvrant la zone exportée est noircie, notifications comprises.
4. **Rédaction de secrets par motifs** sur tout fragment de contexte et sur `paste-web.md` :
   `Bearer`, `api[_-]?key`, `password`, `secret`, `token`, forme JWT, `AKIA…`, `sk-…`.
5. **Vignettes de contrôle** : la revue affiche la bande des images à écrire, suppression d'un clic.

## Options envisagées

### Option A — Chiffrer le fichier intermédiaire au repos
- **Pour** : protège même si le fichier survit à un crash ou finit sur un disque de sauvegarde.
- **Contre** : la clé vit sur la même machine, donc la protection ne vaut que contre un accès froid
  au disque, qui n'est pas le modèle de menace ; le coût CPU tombe sur un chemin d'encodage temps
  réel dont le budget est déjà fixé à moins de 3 % d'un cœur par le critère du lot 3. Elle traite la
  lecture, quand le problème est la **persistance non voulue** — que changer d'emplacement supprime
  pour zéro octet de code.

### Option B — Conserver `~/Library/Application Support/` avec `isExcludedFromBackup`
- **Pour** : emplacement conventionnel et stable, qui permettrait de récupérer une session après un
  crash au lieu de la perdre.
- **Contre** : la conception initiale écrivait là **sans poser l'attribut**, or ce répertoire est
  **inclus dans les sauvegardes Time Machine par défaut**. Une session qui plante y laissait une
  copie permanente de l'écran sur le disque de sauvegarde, que la purge à 24 h ne touche jamais et
  que l'utilisateur ne peut pas soupçonner. L'attribut corrige le défaut mais laisse ouverte la
  fenêtre entre la création du fichier et sa pose. Et une session perdue se refait en trois minutes :
  la récupération après crash n'est pas un besoin.

### Option C — Consigne à l'utilisateur, ou analyse du contenu des frames (OCR, classifieur local)
- **Contre** : la consigne (« fermez vos applications sensibles ») reporte la charge sur l'humain au
  moment où il veut commencer, et personne ne l'appliquera deux fois de suite. L'analyse de contenu
  coûte en permanence, laisse passer des faux négatifs certains, et devrait lire tout ce que
  l'utilisateur voit — une garantie qui exige d'analyser davantage n'en est pas une.

## Justification

La défense est en profondeur parce que les fuites n'ont pas une origine unique. Chaque mesure tient
un point du chemin — la persistance (le fichier vidéo), la source (ce qui entre dans le flux), la
composition (ce qui reste dans l'image exportée), la sortie texte (`paste-web.md` et les fragments),
l'humain (les vignettes) — à un coût faible en ce point, et aucune ne couvre les autres.

Le rapport coût/valeur est très inégal, et c'est ce qui a tranché. La liste noire coûte une ligne,
`excludingApplications` étant déjà utilisé pour s'exclure soi-même ([ADR-0010](0010-calque-ordonne-pendant-le-trace-seulement.md), R12).
La rédaction par motifs tient en **trente lignes** et reste le contrôle le plus rentable du produit,
seule à agir sur ce qui part réellement chez un tiers. Le masquage à la composition a un argument
supplémentaire, comportemental : la première fois qu'un développeur voit une notification privée dans
une capture déjà partie chez un tiers, il ne ferme pas Slack avant chaque session — il n'utilise plus
l'outil.

Le modèle de menace initial était incohérent sur un point maintenant corrigé : `paste-web.md` ôtait
les chemins absolus « pour ne pas divulguer l'arborescence » tout en publiant les corps de requête
HTTP. Protéger le nom des dossiers en laissant passer les jetons d'authentification, c'est se tromper
d'inventaire de ce qui a de la valeur.

## Conséquences

- **Positives** : aucune copie du média source ne survit à la session, ni sur le disque ni sur une
  sauvegarde ; les applications les plus sensibles n'entrent jamais dans le flux, donc jamais dans une
  frame, pré-roll compris ; le dernier filtre reste visuel et humain.
- **Négatives** — le prix à payer, assumé : `$TMPDIR` peut être purgé par le système sous une session
  longue si l'espace manque, et l'échec d'écriture doit être traité comme une fin de session, pas
  comme un plantage ; aucune récupération n'est possible après un crash. Une application de la liste
  noire qui recouvre la fenêtre cible laisse un trou dans les pixels, sans que l'utilisateur comprenne
  toujours pourquoi, et le masquage noircit parfois une fenêtre légitime — un inspecteur, un
  simulateur, une fenêtre auxiliaire portée par un pid différent de l'application cible. La
  rédaction par motifs produit des faux positifs (un test avec un JWT factice, un identifiant
  contenant `token`) qui abîment la lisibilité du rapport, et des faux négatifs (un secret maison
  sans motif reconnaissable) : réduction de risque, jamais garantie. Le
  pré-roll allume l'indicateur système de capture en permanence, sans possibilité de le désactiver.
- **Ce que ça ferme** : la reprise d'une session interrompue ; la rétention longue du média source,
  donc toute réextraction a posteriori ; le partage et la synchronisation, dont l'absence de réseau
  sortant est ici une garantie ([ADR-0012](0012-speechanalyzer-avec-speechdetector.md),
  [ADR-0011](0011-micro-par-fenetre-de-parole.md)).

## Signal de révision

Un fichier `.mov` de Regarde retrouvé dans `/var/folders` plus de 24 h après la fin d'une session,
ou sur un instantané Time Machine : la chaîne purge/suppression a une brèche que l'auto-test de
démarrage doit chercher. Ou un contenu tiers — notification, fenêtre d'un autre projet — constaté
dans une image d'un rapport **déjà transmis** : le masquage a laissé passer un cas, et la liste des
niveaux de fenêtre couverts est à revoir avant tout autre travail.

## Références

- Spécification § 10, § 5.6 (masquage), § 9.11 (`paste-web.md`), § 12 R11 et R12, § 11.3 (lots 1 et 4).
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md) — le fichier intermédiaire
  découle de ce choix ; [ADR-0004](0004-preroll-opt-in.md) — pourquoi le pré-roll est opt-in.
- [ADR-0019](0019-providers-hors-mvp-protocole-fige.md) — les fragments de contexte, second flux
  soumis à la rédaction par motifs.
