---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 4
---

# ADR-0014 — Une session est un journal d'événements append-only, projeté en une structure `Session`

## Contexte

Une session agrège des événements produits par des files distinctes : le tap souris, la file
d'encodage, le moteur audio, l'interface de revue. Elle dure deux à dix minutes de travail humain
non reproductible — la parole prononcée pendant un geste ne se rejoue pas. Et les modes
d'interruption ne sont pas hypothétiques : `SCStream` peut rendre `-3821` et exiger un
redémarrage, un écran externe peut être débranché en pleine session, la machine peut se mettre en
veille. Un crash à la minute 8 d'une session de 10 ne doit pas coûter les 8 minutes précédentes.

Le disque est par ailleurs la source de vérité et MCP n'en est qu'une vue
([ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md)) : un lecteur externe doit pouvoir
lire pendant que l'application écrit.

## Décision

L'état d'une session est écrit au fil de l'eau dans un journal d'événements append-only, projeté
en mémoire en une structure `Session`. `TimelineStore` est l'acteur de projection ; l'écriture
disque passe par une file série dédiée disposant de son propre descripteur ouvert en `O_APPEND`.
Le même principe gouverne `state.jsonl` (états de résolution) et `index.jsonl` (catalogue des
sessions).

## Options envisagées

### Option A — État en mémoire, un seul `manifest.json` écrit à la finalisation
- **Pour** : le plus simple, une seule sérialisation, aucun format d'événement à définir.
- **Contre** : tout crash avant la finalisation perd l'intégralité de la session, y compris la
  parole. C'est précisément le scénario que les modes d'interruption connus rendent probable.

### Option B — État en mémoire, instantané complet réécrit toutes les 10 s
- **Pour** : borne la perte à dix secondes, sans format incrémental.
- **Contre** : un instantané est une écriture multi-kilo-octets non atomique, et un crash pendant
  l'écriture corrompt le seul état existant. Écrire dans un temporaire puis `rename` demanderait
  plus de machinerie que le journal, pour une garantie inférieure.

### Option C — SQLite en mode WAL
- **Pour** : durabilité et lecture concurrente sans effort d'implémentation.
- **Contre** : un fichier binaire, donc ni lisible ni versionnable, alors que `manifest.json` et
  `index.jsonl` sont explicitement destinés au dépôt git du projet. Ajoute un schéma à migrer pour
  quelques centaines de lignes par session — un volume où le moteur n'apporte rien.

### Option D — Journal JSONL append-only, projeté (retenue)
- **Pour** : écriture au fil de l'eau, lecture concurrente triviale, format inspectable à `cat` ;
  une ligne finale tronquée par un crash se jette sans compromettre les précédentes.
- **Contre** : deux représentations de la même vérité à garder cohérentes, et l'état courant d'un
  objet édité plusieurs fois ne se lit qu'en rejouant le journal.

## Justification

Le critère décisif est le coût d'un crash rapporté au coût du mécanisme. Une session perdue est
irrécupérable au sens fort : il faudrait reproduire le bug, refaire les gestes et redire les
phrases. Le journal ramène ce coût à la dernière ligne écrite, pour un descripteur et une file.

**Correction sur l'atomicité.** `PIPE_BUF` qualifie l'atomicité des écritures sur un **tube**,
pas sur un fichier régulier. Pour un fichier ouvert en `O_APPEND`, l'atomicité du couple
« positionnement en fin de fichier + écriture » repose sur le verrou de vnode pris par le noyau :
deux `write(2)` uniques ne s'entrelacent pas. La conclusion « aucun verrou applicatif nécessaire »
tient donc, mais la contrainte de 512 octets par ligne qui l'accompagnait n'existe pas — et
n'était de toute façon pas respectée, une ligne `resolved` portant une note de 600 caractères la
dépassant.

Les risques réels sont ailleurs, et sont traités explicitement :

1. **Écriture courte** — `write` peut rendre moins d'octets que demandé : le code boucle jusqu'à
   épuisement du tampon et le lecteur tolère une dernière ligne incomplète. 2. **`EINTR`** —
   l'appel est repris. 3. **Projet sur dossier synchronisé** — sur un volume Dropbox ou iCloud
   Drive, le fichier peut être remplacé sous le descripteur et `O_APPEND` ne garantit plus rien ;
   un `flock` consultatif est pris dans ce cas.

**Séparation acteur / entrées-sorties.** `TimelineStore` sérialise les mutations de la projection
mais ne bloque jamais sur un `write` : un acteur qui attend le disque sérialise aussi ses lecteurs.
D'où la file série dédiée et son propre descripteur — deux descripteurs `O_APPEND` sur le même
fichier sont sûrs, précisément grâce au verrou de vnode. Les événements `frameIndexed`, émis à 4/s
et par écran, n'entrent jamais dans l'acteur : à deux écrans sur dix minutes, ce sont environ cinq
mille réveils pour des données que seule la file d'encodage consomme ; ils sont agrégés sur cette
file et écrits directement.

## Conséquences

- **Positives** : une session interrompue reste exploitable jusqu'à sa dernière ligne ; le sidecar
  et l'application lisent le même fichier sans coordination ; le format se diagnostique à la
  lecture, ce qui compte pour un mécanisme dont les bugs n'apparaissent qu'après un crash.
- **Négatives — le prix à payer, assumé** : le journal restitue les marques, la géométrie et la
  parole, **pas les images**. L'extraction des frames a lieu à la finalisation, et un `.mov`
  abandonné par un crash est illisible faute d'atome `moov` ; les 8 minutes récupérées le sont
  donc en texte et en géométrie, plus les seules images déjà écrites sur disque. Le chemin de
  rejeu n'est par ailleurs jamais exercé en développement normal, ce qui impose un test qui tue le
  processus et relit le journal, sans quoi la garantie reste théorique. Enfin, `flock` est
  consultatif : un processus qui ne le prend pas passe outre.
- **Ce que ça ferme** : l'édition en place d'un état déjà écrit — toute correction est un
  événement de plus — et la troncature partielle d'une session, puisque supprimer réellement du
  contenu revient à supprimer le fichier entier.

## Signal de révision

`state.jsonl` est global au projet et croît indéfiniment, contrairement au journal d'une session.
Si son rejeu au démarrage d'un appel MCP devient perceptible — quelques dizaines de millisecondes,
ou un fichier de plusieurs mégaoctets — il faudra lui adjoindre un instantané compacté, ce qui
rouvre la question du format.

## Références

- Spécification § 3.7 (atomicité), § 9.2 (`index.jsonl` sous verrou), § 9.9 (`state.jsonl`
  rejoué à la lecture), § 5.5 (finalisation par segment).
- `open(2)` / `write(2)` : sémantique de `O_APPEND` et verrou de vnode (XNU).
- [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) — le disque source de vérité.
- [ADR-0013](0013-numerotation-definitive-au-mousedown.md) — le numéro comme événement du journal.
- [ADR-0020](0020-confidentialite-capture-continue.md) — effacement et append-only.
