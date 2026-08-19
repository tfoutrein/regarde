---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 4
---

# ADR-0018 — La livraison passe par une phrase au presse-papiers restaurable, doublée d'une injection best-effort

## Contexte

La session se termine, le rapport est sur disque, le serveur MCP est prêt à le servir. Reste à
faire savoir à l'agent qu'il y a quelque chose à lire — et c'est là que la contrainte du protocole
mord : **MCP est pull-only**. Le serveur expose des outils, le client les appelle quand il le
décide ; rien ne permet de réveiller l'agent. Un canal push existe côté Claude Code
(`capabilities.experimental["claude/channel"]`), mais il est en research preview, réservé à ce
seul client, et exige `claude --channels` plus un runtime Node ou Bun.

Il reste donc forcément un geste humain. La question n'est pas de le supprimer, c'est impossible,
mais de le réduire au minimum sur un parcours qui doit tenir en 8 secondes (§ 2.1) face à `⌘⇧4`.

## Décision

À la fin de chaque session, Regarde dépose au presse-papiers une phrase d'une seule ligne :

```
Lis le feedback #42 avec regarde (get_feedback number=42) puis applique les corrections. Si l'outil n'est pas disponible, lis /chemin/absolu/.regarde/sessions/0042-…/report.md
```

Le presse-papiers antérieur est sauvegardé et restauré si l'utilisateur n'a pas collé dans les
60 s ; les trois derniers feedbacks restent accessibles depuis la barre de menus. Le bandeau
propose « ⏎ Envoyer à \<agent détecté\> » : activation de la fenêtre de l'agent et injection du
texte par Accessibilité, **best-effort avec repli silencieux** sur le presse-papiers seul.

## Options envisagées

### Option A — Canal push expérimental de Claude Code
- **Pour** : zéro geste. Le mécanisme existe et fonctionne.
- **Contre** : research preview, un seul client, un drapeau de lancement et un runtime que
  l'application native n'a pas. Il rendrait le produit inutilisable pour Cursor, Zed, Windsurf et
  le chat web. Repoussé au lot 11.

### Option B — Presse-papiers seul, sans injection ni sauvegarde
- **Pour** : universel, quinze lignes de code, aucune permission supplémentaire.
- **Contre** : le geste final reste « changer de fenêtre, coller, Entrée », soit 6 s et une rupture
  d'attention par session (§ 13 A3). Surtout, écraser sans prévenir le presse-papiers d'un
  développeur, c'est un comportement qu'aucun outil de développement ne se permet.

### Option C — Ouvrir le terminal de l'agent et y taper la commande
- **Pour** : fermeture complète du geste.
- **Contre** : suppose de connaître l'agent, son terminal et son état — taper dans un agent en
  cours de tour corrompt son entrée. Inutilisable sans repli.

### Option D — Phrase au presse-papiers, cycle de vie complet, injection AX best-effort (retenue)
- **Pour** : universelle par construction, réversible, dernier mètre franchi quand c'est possible.
- **Contre** : trois mécanismes à maintenir plutôt qu'un.

## Justification

**La phrase est un artefact conçu, pas une étiquette.** Sa clause la plus importante est
`puis applique les corrections` : sans elle, l'agent lit le rapport et le résume — conforme à la
demande, et inutile, puisque le développeur veut qu'il code.

**La clause de repli avec chemin absolu est l'assurance du produit.** Serveur MCP non configuré,
planté, ou pas chargé par le client : l'agent trouve dans la même phrase un chemin de fichier qu'il
sait ouvrir avec son propre outil de lecture. Aucune session n'est perdue à cause d'un problème
d'intégration — c'est « le disque est la source de vérité »
([ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md)) appliqué à la notification.

**Trois corrections du cycle de vie** découlent du fait que le presse-papiers n'appartient pas à
l'application :

1. **Sauvegarde et restauration.** Le contenu antérieur est lu à l'ouverture de session et remis
   en place si l'utilisateur n'a pas collé dans les 60 s ; `changeCount` dit s'il y a touché
   entre-temps, auquel cas on ne restaure rien.
2. **Persistance dans la barre de menus.** Les trois derniers feedbacks y sont listés, un clic
   recopie la phrase. La perte devient rattrapable — ce qui rend la restauration automatique
   acceptable au lieu d'être un risque.
3. **Fermeture du geste.** `setValue` par Accessibilité sur le champ de saisie de l'agent, repli
   sur une synthèse `⌘V`, repli final silencieux sur le presse-papiers seul. Trois heures de
   travail pour le dernier mètre, sur une application qui détient déjà l'Accessibilité pour son
   `CGEventTap` ([ADR-0005](0005-cgeventtap-arbitre-unique.md)).

Le mot-clé est **silencieux** : une injection qui échoue ne produit aucune alerte — le texte est au
presse-papiers, l'utilisateur colle, on retombe sur l'option B.

## Conséquences

- **Positives** : le chemin nominal se termine sur ⏎, et le mode dégradé complet — pas de MCP, pas
  d'AX, pas d'agent détecté — reste fonctionnel au seul copier-coller.
- **Négatives** — le prix à payer, assumé : l'injection AX dépend de la hiérarchie
  d'accessibilité de chaque agent, contractuelle chez aucun d'eux ; il faudra du code par agent
  cible, et il se dégradera sans prévenir. La restauration à 60 s crée une fenêtre où la phrase a
  disparu alors que l'utilisateur y revient tardivement — l'historique de la barre de menus
  n'existe que pour compenser cette décision. Et la phrase contient un chemin absolu, donc
  l'arborescence du poste : elle est exclue de la variante « chat web » (`paste-web.md`).
- **Ce que ça ferme** : toute conception où Regarde réveille l'agent. L'initiative de la lecture
  appartient à l'agent, donc l'état de session (`new → delivered → …`) reste lisible sur disque
  plutôt que poussé.

## Signal de révision

Le canal push cesse d'être en research preview **et** un second client l'implémente : le rejet de
l'option A tombe, le geste ⏎ peut disparaître pour ces clients — sans retirer le presse-papiers,
qui reste le chemin universel. Réviser aussi si l'injection AX échoue sur plus d'une session sur
cinq en usage réel : « ⏎ Envoyer » promet alors plus qu'il ne tient.

## Références

- Spécification § 9.10, § 2.1, § 9.11 (modes dégradés), § 13 A3, § 14 (canal push), § 11.3 lot 4.
- [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) — le disque source de vérité.
- [ADR-0016](0016-aucune-image-via-mcp.md) — le chemin absolu comme canal principal.
- [ADR-0017](0017-detection-projet-trois-etats.md) — la phrase suppose un projet résolu.
- [ADR-0005](0005-cgeventtap-arbitre-unique.md) — permission Accessibilité déjà acquise.
