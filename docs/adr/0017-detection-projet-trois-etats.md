---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 4
---

# ADR-0017 — Le projet cible est détecté à trois états et tranché à l'ouverture de session

## Contexte

Regarde écrit ses artefacts dans `<projet>/.regarde/`. Il faut donc savoir, pour chaque session,
de quel projet il s'agit — alors que rien dans l'écran capturé ne le dit : l'application testée est
un navigateur ou un binaire compilé, le dépôt vit dans un terminal ou un IDE ailleurs sur le
bureau. Deux faits établis par les sondes éliminent les approches naïves :

- **Le `cwd` du processus terminal ne dit rien.** Warp a pour `cwd` le répertoire personnel de
  l'utilisateur ; ses dix shells enfants pointent sur six projets distincts. Interroger le
  processus au premier plan donne systématiquement une réponse fausse et plausible.
- **Le nom de dossier `~/.claude/projects/` est un encodage lossy.** Les séparateurs de chemin y
  sont remplacés par des tirets, sans échappement : 52 des 86 projets du poste de référence
  contiennent déjà un tiret dans un segment. Le décodage est mathématiquement ambigu.

Le risque R2 qualifie l'échec : un rapport écrit dans le mauvais projet est silencieux, découvert
dans une revue de code plus tard, et détruit la confiance dans l'outil.

## Décision

Le projet est déterminé par croisement de signaux pondérés — fichier de session Claude Code (0,9),
`proc_pidinfo` sur **tous les descendants** du terminal au premier plan (0,6), titre de fenêtre
d'IDE (0,2, jamais décisif seul) — et le résultat est affiché sous **trois états visuellement
distincts** : certain (vert discret), probable (ambre, motif affiché en clair), ambigu (rouge,
sélecteur ouvert). La résolution intervient dès l'état `arming`, à l'ouverture de session.
Le chemin exact provient toujours du champ `cwd` du fichier de session ; le nom de dossier
`~/.claude/projects/` n'est jamais décodé.

## Options envisagées

### Option A — Un seul signal : le `cwd` du processus au premier plan
- **Pour** : trivial, une ligne de code, aucune dépendance à un format tiers.
- **Contre** : faux dans le cas d'usage principal — Warp, iTerm à onglets, tmux. Ce signal seul
  produit une détection confiante et fausse, exactement le mode d'échec de R2.

### Option B — Demander le projet à l'utilisateur à chaque session
- **Pour** : jamais faux, aucune dépendance, zéro heuristique à maintenir.
- **Contre** : ajoute une interaction à un parcours dont l'argument central est de tenir en
  8 secondes (§ 2.1). Le mode éclair n'ouvre aucun panneau ; un sélecteur systématique le tue.

### Option C — Détection avec confirmation en fin de session (conception initiale)
- **Pour** : l'utilisateur voit le résultat avant écriture, dernier filet de sécurité.
- **Contre** : elle refusait d'écrire en état ambigu, donc ouvrait un sélecteur **à la seconde
  exacte où l'utilisateur voulait avoir fini**. Le retour est formulé, l'attention est repartie
  ailleurs, et la confirmation se dégrade en réflexe de clic — l'inverse de la protection visée.

### Option D — Signaux croisés, trois états, résolution à `arming` (retenue)
- **Pour** : l'ambiguïté se traite au moment où l'utilisateur n'attend rien.
- **Contre** : détection à faire au démarrage, et dépendance à un format non contractuel.

## Justification

Ce qui départage l'option D de l'option C n'est pas la qualité de la détection — elle est
identique — mais **le moment**. Une confirmation demandée au début coûte une seconde à quelqu'un
qui n'a rien investi ; la même à la fin interrompt quelqu'un qui a terminé. La pastille cliquable
reste dans le HUD toute la session : la correction est possible sans jamais être imposée.

Les trois états doivent être visuellement distincts, pas trois nuances de vert : un badge dont
l'apparence ne varie pas selon la confiance entraîne l'utilisateur à ne plus le lire, ce qui
transforme R2 en certitude. L'ambre affiche son motif en clair (« shell Warp #20378 ») — la
confiance se justifie, elle ne se décrète pas.

La validation est stricte de bout en bout : `kill(pid, 0)` et `updatedAt` de moins de 2 h pour le
fichier de session, chemin absolu existant contenant `.git` ou `package.json` pour `proc_pidinfo`.
Devant plusieurs `cwd` de shells concurrents, l'application **ne tranche jamais** seule : elle passe
en ambigu. Quand aucun projet n'est détecté — cas légitime du test d'une application sans dépôt —
les artefacts vont dans `~/Library/Application Support/Regarde/orphelins/`, jamais nulle part.

**Corollaire sur l'identité de session.** Le projet peut changer entre `arming` et la publication
(l'utilisateur corrige la pastille en cours de session) ; or le numéro de session est monotone *par
projet*. Il ne peut donc pas être attribué à `t0`. L'identité pendant tout le cycle de vie est un
UUID ; le numéro et le nom de dossier définitif sont calculés en `publishing`, sous verrou `fcntl`
sur `index.jsonl` (§ 9.2) — deux sessions publiées en parallèle ne peuvent pas collisionner.

## Conséquences

- **Positives** : l'écriture est directe en états certain et probable, donc le chemin nominal ne
  contient aucune boîte de dialogue. Le rapport porte la mention du motif quand l'état était
  probable, ce qui rend une erreur diagnosticable après coup.
- **Négatives** — le prix à payer, assumé : le signal de poids 0,9 dépend de
  `~/.claude/sessions/<pid>.json`, format **non contractuel** qui peut changer ou disparaître à
  toute mise à jour de Claude Code (R14). D'où la validation stricte et la désactivation propre :
  sur schéma inattendu, le provider se coupe sans message et la détection retombe sur
  `proc_pidinfo` + marqueurs git, avec davantage d'états ambigus. L'énumération des descendants
  coûte par ailleurs quelques dizaines de millisecondes de plus qu'un `cwd` unique.
- **Ce que ça ferme** : l'attribution d'un numéro dès `t0`, donc tout affichage du numéro définitif
  pendant la session ; et l'usage de `~/.claude/projects/` comme source de chemin, même en
  diagnostic.

## Signal de révision

Une session écrite dans le mauvais projet alors que l'état affiché était **certain** : deux signaux
forts peuvent donc concorder à tort, et la règle des deux signaux ne suffit pas. Réviser également
si, sur 10 sessions réparties dans 5 projets (critère du lot 4), plus de trois retombent en état
ambigu : la détection serait trop conservatrice et le sélecteur redeviendrait le chemin nominal.

## Références

- Spécification § 8.2 (signaux pondérés, trois états), § 9.2 (numéro attribué en `publishing`),
  § 12 R2 et R14, § 11.3 lot 4.
- [ADR-0014](0014-journal-append-only.md) — journal append-only et verrou sur `index.jsonl`.
- [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) — résolution du projet côté sidecar.
- [ADR-0019](0019-providers-hors-mvp-protocole-fige.md) — protocole `ContextProvider`.
