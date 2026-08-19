---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 6
---

# ADR-0015 — Le disque est la source de vérité, un sidecar MCP stdio n'en est qu'une vue

## Contexte

Le produit écrit ses artefacts dans `<projet>/.regarde/` : un `manifest.json` par session, un
`report.md`, les images, plus deux journaux de projet (`index.jsonl`, `state.jsonl`). Reste à
décider comment l'agent y accède.

La contrainte dominante est un fait d'usage : **l'agent tourne le plus souvent après la session,
application fermée**. Le développeur trace ses marques, envoie la phrase, referme Regarde et
repart sur autre chose ; l'agent travaille dans les minutes qui suivent, parfois le lendemain,
parfois depuis une autre fenêtre de terminal. Trois clients sont visés — Claude Code, Cursor,
Zed — et aucun ne garantit qu'un processus tiers soit vivant au moment de l'appel. Seconde
contrainte (§ 9.1) : plusieurs agents lisent la même session en parallèle, et muter un fichier
versionné à chaque lecture salirait le diff git.

## Décision

Les fichiers sur disque sont la source de vérité : `manifest.json` est le fichier source de la
session, tout le reste en est un rendu. MCP est une **vue** de ce disque, servie par un binaire
distinct, `regarde-mcp`, en transport **stdio uniquement**, qui n'a besoin ni de l'application ni
d'un réseau pour répondre.

## Options envisagées

### Option A — Serveur MCP porté par l'application
- **Pour** : un seul binaire à signer et à notariser ; accès direct à l'état en mémoire ; pas de
  problème de résolution du projet, l'application sait déjà lequel est ouvert.
- **Contre** : ne répond plus dès que l'application est fermée, c'est-à-dire dans le cas
  majoritaire. La parade — la relancer au premier appel — suppose un démarrage en moins d'une
  seconde et vole le focus au milieu d'un tour d'agent.

### Option B — Transport HTTP local (127.0.0.1, port dynamique)
- **Pour** : plusieurs clients simultanés sur une seule instance ; débogage à la boucle avec
  `curl`.
- **Contre** : une URL à port aléatoire ne peut pas figurer dans une configuration client stable.
  Le fichier de configuration MCP de Claude Code, de Cursor et de Zed est un fichier statique que
  l'utilisateur édite une fois. Écrire un port variable dans ce fichier à chaque démarrage revient
  à faire éditer par un processus la configuration d'un autre, avec rechargement à chaud non
  garanti chez les trois. Le port fixe déplace le problème sur les collisions.

### Option C — Sidecar stdio lisant le disque (retenue)
- **Pour** : le client lance le processus lui-même, avec une commande fixe ; fonctionne
  application fermée ; un processus par client, donc aucune concurrence en écriture autre que
  celle des journaux append-only, déjà traitée par [ADR-0014](0014-journal-append-only.md).
- **Contre** : deuxième binaire dans le cycle de distribution ; le sidecar doit retrouver seul le
  projet ; il hérite de l'identité TCC du processus qui le lance.

### Option D — Le sidecar sert `report.md` tel quel
- **Pour** : sidecar trivial, quelques dizaines de lignes ; aucun code de rendu dupliqué.
- **Contre** : impossible. `get_feedback` doit préfixer le bandeau « DÉJÀ TRAITÉ le … par … » —
  issu de `state.jsonl`, donc dynamique et absent du fichier —, filtrer par `marks` quand l'appel
  en demande un sous-ensemble, et honorer `include_context: false`. Trois transformations qu'un
  `cat` ne fait pas.

## Justification

L'option A échoue sur le cas majoritaire, pas sur un cas limite : c'est disqualifiant. L'option B
échoue sur un point que rien ne rattrape côté produit, la stabilité du fichier de configuration
client. Restait C, dont les coûts sont bornés et connus d'avance.

L'option D, écartée, produit la conséquence d'architecture la plus lourde de cet ADR : puisque le
sidecar doit transformer, il lui faut le générateur de rapport. **Le générateur devient donc une
bibliothèque partagée entre l'application et le sidecar, et `report.md` sur disque n'est qu'un
rendu du manifeste**, produit par la même bibliothèque au moment de la publication. Ce point
n'était pas énoncé dans la conception initiale : il déplace du travail du lot 4 vers une brique
commune, à écrire avant le lot 6.

## Conséquences

- **Positives** : le format survit à l'outil — `report.md` est du Markdown, `manifest.json` du
  JSON, aucune base de données ; le mode dégradé « sans MCP, avec accès au disque » du § 9.11 est
  gratuit, l'agent lit le fichier et suit les chemins absolus ; une session reste lisible des mois
  après, sans l'application. Un seul chemin de rendu, donc pas de divergence entre ce que
  l'utilisateur relit et ce que l'agent reçoit.
- **Négatives — le prix à payer, assumé** :
  - **Deux binaires à signer et à notariser** au lot 8, avec deux passages d'agrafage et deux
    occasions de casser Gatekeeper. Voir [ADR-0002](0002-hors-sandbox-developer-id.md).
  - **Le SDK MCP Swift est en 0.12.1**, c'est-à-dire pré-1.0 et sans contrat de compatibilité. Il
    est isolé derrière une couche interne mince pour que sa rupture reste une journée de travail et
    non une réécriture (risque R14).
  - **Résolution du projet à la charge du sidecar.** Le comportement naturel « cwd, puis remontée
    vers la racine git » échoue sur deux des trois clients : Cursor et Zed lancent fréquemment un
    serveur déclaré en configuration globale avec le cwd de l'application ou `/`. L'ordre retenu
    ajoute donc un **index utilisateur** `~/Library/Application Support/Regarde/projects.jsonl`,
    maintenu par l'application, avant l'erreur explicite listant les candidats. C'est un couplage
    caché : un sidecar installé sur une machine où l'application n'a jamais publié de session ne
    résout rien.
  - **Piège TCC du sidecar.** Il hérite de l'identité TCC de son lanceur. Si le projet est sous
    `~/Documents` ou `~/Desktop`, le premier `resolve_feedback` déclenche une invite « fichiers et
    dossiers » **au nom de Claude Code**, en plein tour d'agent, et échoue sur `EPERM`. Testé
    explicitement au lot 6 et documenté, faute de pouvoir l'empêcher.
- **Ce que ça ferme** : aucun agent distant ou conteneurisé ne peut être servi, puisqu'il n'y a ni
  écoute réseau ni système de fichiers partagé. Aucun état ne peut être tenu en mémoire entre deux
  appels : tout ce que le sidecar sait, il le relit.

## Signal de révision

Sur un mois d'usage réel, plus d'une session sur dix qui se termine par l'erreur « projet
introuvable » du sidecar : l'index utilisateur ne tient pas sa promesse et la résolution doit
passer par un mécanisme explicite (argument de ligne de commande dans la configuration client).
Second signal : l'adoption par les trois clients cibles d'un mécanisme de découverte de serveurs
locaux à port dynamique, qui lèverait l'objection unique contre le transport HTTP.

## Références

- Spécification § 4.1 (ligne « Canal vers l'IA »), § 9.1 (P1, P4), § 9.3, § 9.7, § 9.11, § 11.3
  (lot 6), risque R14.
- [ADR-0014](0014-journal-append-only.md) — journal d'événements append-only.
- [ADR-0016](0016-aucune-image-via-mcp.md) — aucune image dans le chemin nominal MCP.
- [ADR-0017](0017-detection-projet-trois-etats.md) — détection du projet côté application.
- [ADR-0019](0019-providers-hors-mvp-protocole-fige.md) — `get_feedback_context`, vide au MVP.
