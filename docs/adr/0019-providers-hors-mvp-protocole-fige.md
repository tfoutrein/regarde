---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: —
---

# ADR-0019 — Aucun provider contextuel dans le MVP, protocole `ContextProvider` figé dès maintenant

## Contexte

Le noyau de Regarde ne capture que des pixels et de la géométrie. L'idée d'enrichir une marque
par du contexte applicatif — l'URL de la page testée, le sélecteur CSS de l'élément désigné, les
erreurs de la console, les dernières lignes du terminal — est ce qui sépare un rapport « voici une
image » d'un rapport « voici le composant ». La tentation est donc forte de l'intégrer tôt.

Deux contraintes cadrent le choix. La première est le consentement TCC Automation : il se demande
**par application cible**, et son prompt vole le focus. La seconde est structurelle : un fragment de
contexte est une donnée du manifeste, rendue dans le rapport et lue par le sidecar MCP
([ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md)). Sa forme conditionne le modèle de
données bien avant son implémentation.

## Décision

Le MVP n'embarque **aucun provider contextuel**, à une exception près : l'enrichissement gratuit —
identité (`NSWorkspace.frontmostApplication` : bundle, pid) et titre/cadre de la fenêtre cible
(`SCWindow.title` / `.frame`), acquis sans permission supplémentaire dès que Screen Recording est
accordé. Le protocole `ContextProvider` — `canHandle` synchrone sans IPC, `enrich` asynchrone
retournant un `ContextFragment?` — est **figé maintenant**, avec son budget, son moment d'appel et
sa politique d'échec. Les implémentations arrivent aux lots 9 (AppleScript, AX, `simctl`) et 10
(extension Chrome MV3), et ne sont **jamais** déclenchées depuis le chemin d'une session : les
consentements se demandent depuis l'écran de réglages, hors session.

## Options envisagées

### Option A — Providers AppleScript dès le MVP (URL du navigateur, contenu du terminal)
- **Pour** : la valeur est réelle et immédiate ; l'URL supprime à elle seule la moitié des
  allers-retours « de quelle page tu parles ? ».
- **Contre** : le prompt Automation apparaît **pendant** l'enregistrement, vole le focus, et l'état
  de l'application testée change sous l'objectif — l'outil casse le test qu'il documente. Le
  consentement étant par couple (application, cible), le développeur revit le prompt à chaque
  nouvelle application testée. Ce n'est pas un coût, c'est une rupture de flux.

### Option B — Chrome DevTools Protocol pour le contexte web
- **Pour** : DOM, console et réseau à la source, sans extension à installer ni à maintenir.
- **Contre** : depuis Chrome 136, `--remote-debugging-port` est **ignoré sur le profil par défaut**.
  Il faudrait relancer Chrome sur un profil jetable — donc demander au développeur de ne plus tester
  son application comme il la teste, avec ses sessions, ses extensions et son état. Écarté
  définitivement au profit d'une extension MV3 (lot 10).

### Option C — Aucun provider et aucun protocole ; on verra au lot 9
- **Pour** : rien à spécifier à vide, zéro code mort.
- **Contre** : le `ContextFragment` traverse le manifeste, `report.md`, `context/*.json` et les
  outils MCP. L'ajouter après coup, c'est migrer un format sur lequel des sessions existent déjà et
  qu'un agent lit — pour une portion du produit dont on sait aujourd'hui qu'elle viendra.

## Justification

La ligne de partage n'est pas le coût de développement mais l'effet sur le flux : tout ce qui
s'obtient sans prompt entre dans le MVP, tout ce qui en déclenche un est expulsé du chemin de
session. Le titre de fenêtre traverse cette ligne, l'URL non — alors que la seconde vaut plus que le
premier.

Le protocole est figé maintenant pour trois points qui ne sont pas des détails d'implémentation.
**Le budget est dur** : 150 ms par provider, 250 ms au total ; au-delà, la marque part sans son
fragment. Un enrichissement qui retarde la pose d'une marque a détruit plus de valeur qu'il n'en
apporte. **Le moment d'appel est la pose de la marque**, jamais la fin de session : les erreurs de
console et le DOM auront disparu, et un contexte reconstitué après coup est un contexte faux.
**Un provider en échec est mis en liste noire pour le reste de la session, sans message** : un
timeout AppleScript qui produirait une alerte à chaque marque rendrait l'outil inutilisable ; le
silence est ici la bonne réponse à l'utilisateur, à condition que l'échec parte au journal.

Le sélecteur CSS est le levier de valeur numéro un du lot 10 : quand il est fiable, il **remplace
intégralement la capture d'écran** pour l'agent, qui ouvre alors le composant plutôt que de lire des
pixels. C'est aussi la plus forte réduction de jetons du produit, dans la ligne de
[ADR-0016](0016-aucune-image-via-mcp.md).

## Conséquences

- **Positives** : aucun prompt TCC ne peut interrompre une session du MVP ; le budget de permissions
  reste à quatre autorisations (R1) ; le modèle de données accueille les fragments sans migration ;
  la surface de test du MVP se réduit d'autant.
- **Négatives** — le prix à payer, assumé : le rapport du MVP ne dit pas quelle URL était affichée
  ni quel composant était visé ; l'agent travaille sur des pixels et un titre de fenêtre, et fera
  parfois fausse route. Le protocole est spécifié **sans consommateur réel** : ses hypothèses — la
  gratuité de `canHandle`, l'unité du `ContextFragment`, la suffisance de 150 ms pour un aller-retour
  AppleScript — ne seront confrontées qu'au lot 9, et une correction à ce moment-là touchera un
  format déjà en production. La liste noire silencieuse rend le débogage d'un provider défaillant
  pénible : il disparaît à la première marque et ne se manifeste plus.
- **Ce que ça ferme** : le CDP, définitivement. Tout enrichissement en fin de session, y compris pour
  les données qui y survivraient. Toute demande de consentement depuis le chemin d'une session, y
  compris « juste une fois, au premier usage ».

## Signal de révision

Deux observations rouvrent la décision. **Sur les providers** : si, en relisant dix rapports publiés,
plus d'un tiers a donné lieu à une question de clarification de l'agent sur l'URL ou sur l'élément
visé, le lot 10 est démontré nécessaire et passe avant le lot 7. **Sur le CDP** : si une version de
Chrome rétablit `--remote-debugging-port` sur le profil par défaut, ou expose une API équivalente
sans profil jetable, la comparaison avec l'extension MV3 est à refaire — l'extension a un coût de
maintenance permanent que le CDP n'aurait pas.

## Références

- Spécification § 8.1 (protocole, budget, plafonds de capture), § 11.5 (lots 9 et 10), § 14 (lignes
  « Chrome DevTools Protocol » et « Providers contextuels »).
- [ADR-0016](0016-aucune-image-via-mcp.md) — le sélecteur CSS comme substitut de l'image.
- [ADR-0017](0017-detection-projet-trois-etats.md) — l'autre consommateur de signaux opportunistes.
- [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) — le format que le protocole contraint.
- Risques R1 (permissions), R14 (dérive des dépendances non contractuelles).
