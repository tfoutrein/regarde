---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 4 et 6
---

# ADR-0016 — Aucune image dans le chemin nominal MCP : le canal principal est le texte et le chemin absolu

## Contexte

Regarde produit des images : un recadrage et une vue complète par marque, plus une variante haute
résolution. La tentation évidente est de les renvoyer dans le résultat de `get_feedback`, en
contenu `image` MCP — l'agent reçoit tout en un appel.

Trois faits mesurés interdisent ce chemin. Un **plafond dur de 25 000 jetons par résultat
d'outil** côté Claude Code, au-delà duquel l'appel échoue en bloc (« response exceeds maximum
allowed tokens (25000) »), sans troncature. Un surcoût de **+33 %** dû au base64, payé sur des
octets qui ne portent aucune information. Un bug client documenté : Zed lève
`missing field mime_type` sur des contenus image pourtant conformes.

En face, un fait d'usage : **tous les agents cibles savent déjà lire un PNG local** avec leur
propre outil de lecture de fichier — et ce chemin-là ne passe pas par le plafond MCP. C'est la
parade principale du risque R3.

## Décision

Le canal principal vers l'agent est le **texte et le chemin absolu du fichier**. `get_feedback` ne
renvoie **jamais** d'image. Les pixels ne partent que sur demande explicite, via
`get_feedback_frames`, au recadrage par défaut, avec le coût en jetons annoncé sous chaque marque.

## Options envisagées

### Option A — Images inline dans `get_feedback`
- **Pour** : un seul appel, aucune capacité requise du client hors MCP, prévu par la spécification.
- **Contre** : le chemin naïf coûte **19 332 jetons** pour une session type (voir plus bas), soit
  un appel à moins de 6 000 jetons du plafond dur, franchi dès la quatrième marque — et l'agent
  perd le fil bien avant. Avec le +33 % de base64 et le bug Zed, le chemin nominal casse sur un
  client cible sur trois.

### Option B — `resource_link` vers `file://`
- **Pour** : pas de base64, coût nul dans le résultat d'outil, sémantique MCP propre.
- **Contre** : le client doit ensuite émettre un `resources/read` que les trois cibles ne
  supportent pas uniformément, et l'image finit de toute façon en base64 dans ce second résultat.
  Un aller-retour et une dépendance à une partie peu implémentée du protocole, pour rien.

### Option C — Texte, chemin absolu, images à la demande (retenue)
- **Pour** : le chemin nominal descend à **2 123 jetons**, l'image passe hors du plafond MCP par
  l'outil de lecture natif de l'agent, et le mode dégradé « sans MCP, avec accès au disque » du
  § 9.11 fonctionne sans code supplémentaire — le rapport porte déjà les chemins.
- **Contre** : le produit s'appuie sur une capacité hors protocole ; un agent sans accès au
  système de fichiers de la machine n'est pas servi.

## Justification

Le chiffre qui tranche est le budget d'une session type :

| Poste | Chemin nominal | Escalade fenêtre | Chemin naïf |
|---|---|---|---|
| `report.md` | 1 180 | 1 180 | 1 180 |
| `structuredContent` réduit | 430 | 430 | 3 800 (manifeste entier) |
| Images | 1 recadrage = **513** | 3 vues fenêtre = **4 371** | 3 captures natives = **14 352** |
| **Total** | **2 123** | **5 981** | **19 332** |

Un facteur neuf entre les extrémités, et beaucoup de sessions se traitent **sans charger la
moindre image** : coût médian attendu entre 1 600 et 2 500 jetons. Ce chiffrage suppose une
formule exacte, que la conception initiale n'avait pas :

```
tokens_visuels(l, h) = min( ceil(l/28) × ceil(h/28) , plafond_du_palier )
```

La formule brute, sans plafond, annonçait 9 920 jetons pour une capture native 3 456 × 2 234,
alors que le coût réel est de 4 784. L'API **redimensionne d'elle-même** toute image dépassant son
palier et facture le plafond de ce palier — 4 784 en haute résolution, 1 568 en standard. La
formule brute surestime donc d'un facteur 2 à 3 dès qu'on dépasse le palier, c'est-à-dire toujours
sur un écran Retina. Or le produit vend à l'agent sa capacité à arbitrer entre texte et pixels
**sur le coût annoncé** : un coût faux fait renoncer à des images utiles autant qu'il en fait
charger d'inutiles, et vide l'arbitrage de son intérêt.

Trois corrections mécaniques accompagnent la décision côté outils :

- **`maxResultSizeChars` ramené de 120 000 à 60 000.** À quatre caractères par jeton, 120 000
  caractères autorisent 30 000 jetons, au-dessus du plafond dur de 25 000 : le garde-fou censé
  protéger l'appel le laissait échouer.
- **`outputSchema` inliné**, jamais un `$ref` vers un hôte inexistant (`https://regarde.local/…`) :
  un client qui tente de le résoudre échoue ou refuse l'outil.
- **Base64 brut dans `data`**, sans préfixe `data:`, quand `get_feedback_frames` renvoie enfin une
  image : l'erreur la plus fréquemment rapportée sur les serveurs MCP qui servent des images.

## Conséquences

- **Positives** : aucun appel MCP ne peut franchir le plafond par accident ; le rapport reste
  utile quand MCP est absent ; le coût affiché marque par marque fait de l'agent un décideur
  informé.
- **Négatives — le prix à payer, assumé** :
  - **Une capacité hors protocole devient une dépendance produit.** Si un agent cible perd l'accès
    au système de fichiers local, le chemin nominal ne délivre plus d'image du tout.
  - **Un mode dégradé de plus à maintenir.** Le chat web n'a pas accès au disque : d'où
    `paste-web.md`, chemins remplacés par des noms de fichiers, géométrie décrite en mots, Finder
    ouvert sur `frames/`. Les chemins absolus en sont retirés — ils divulgueraient l'arborescence
    à un service tiers (voir [ADR-0020](0020-confidentialite-capture-continue.md)).
  - **La formule est un engagement à tenir.** Les paliers de l'API sont extérieurs au produit ;
    s'ils changent, l'annonce devient fausse sans que rien ne casse visiblement.
  - **Asymétrie d'exactitude assumée.** Le coût des images est exact, celui du texte est une
    approximation à quatre caractères par jeton, explicitement étiquetée comme telle : aucun
    tokeniseur n'est embarqué.
  - **Des variantes produites et stockées pour rien** dans la majorité des sessions (recadrage, vue
    complète, haute résolution), afin que l'escalade reste instantanée.
- **Ce que ça ferme** : le scénario « je branche mon agent et il voit tout sans rien faire ». Un
  agent qui ignore les chemins absolus travaillera sur le texte seul — comportement voulu, pas
  échec.

## Signal de révision

Le coût facturé observé s'écarte de plus de 10 % du coût annoncé par la formule sur une image de
référence : les paliers de l'API ont bougé et la table du § 9.6 doit être recalculée. Second
signal : un agent cible se met à tourner sans accès au système de fichiers de la machine
(exécution en conteneur ou à distance) — le chemin absolu cesse alors d'être résoluble et
`resource_link` redevient la seule voie.

## Références

- Spécification § 4.1 (ligne « Livraison des images »), § 9.1 (P2, P3), § 9.6, § 9.7, § 9.8,
  § 9.11, risque R3.
- [ADR-0015](0015-sidecar-mcp-stdio-disque-source-de-verite.md) — le disque est la source de vérité.
- [ADR-0009](0009-geometrie-normalisee-sur-contentrect-de-frame.md) — géométrie du recadrage.
- [ADR-0018](0018-presse-papiers-et-injection-best-effort.md) — la clause de repli avec chemin
  absolu dans la phrase du presse-papiers.
