# Lot 0 — prototype de risque

Ce prototype valide **une seule chose** : le geste. Maintenir ⌥⌘ et tracer par-dessus une
application qui continue de tourner, sans lui voler le focus et sans la ralentir.

Il ne produit rien qu'on puisse montrer, et sa version « ça a l'air de marcher » se fabrique
en trois heures. Cette version-là ne répond à aucune des questions posées. Le plan compte
**2,5 jours**, et c'est le lot qui porte le premier GO/NO-GO.

Le code de ce dossier sera **jeté**. Ce qui survit, ce sont les nombres de
[`RESULTATS.md`](RESULTATS.md) et le journal des surprises qui s'y trouve.

## Démarrage

```bash
./Tools/make-cert.sh          # une seule fois — demande sudo, voir plus bas
./Tools/build-app.sh --run    # build, signature, installation, lancement
./Tools/serve-temoin.sh       # le témoin 1 dans Chrome
```

Au premier lancement, macOS demandera **Surveillance de la saisie** et **Accessibilité**.
Les deux sont requises : sans elles, `CGEvent.tapCreate` renvoie `nil` — sans erreur, sans
exception, sans le moindre indice. C'est pourquoi le rapport de permissions s'imprime avant
toute autre chose au démarrage.

## Le rituel de re-signature

> **Ne jamais déboguer plus de dix minutes sans avoir revérifié que le tap est vivant.**
> La quasi-totalité des « bugs » de cette phase n'en sont pas.

TCC identifie une application par son identité de signature. Avec `codesign -s -` (ad hoc),
cette identité change à chaque build et les autorisations sont perdues à chaque fois — on
passe alors ses soirées à déboguer un tap qui ne démarre pas, pour une raison sans rapport
avec le code.

D'où trois règles, à adopter au premier build et pas au dixième soir :

1. **Un certificat auto-signé stable**, nommé `Regarde Dev`. `make-cert.sh` le crée une fois.
   Il utilise `sudo` pour marquer le certificat comme digne de confiance pour la signature de
   code — c'est la seule commande privilégiée du prototype. Si tu préfères le faire à la main :
   Trousseau d'accès → Assistant de certification → certificat auto-signé de type
   *Signature de code*, puis onglet *Se fier* → *Toujours approuver*.
2. **Un chemin d'installation fixe**, `~/Applications/Regarde0.app`. Le chemin `DerivedData`
   change et emmène l'autorisation avec lui.
3. **Le compteur d'événements comme témoin permanent.** Il est dans le menu ◎ et reste en
   place pour toute la durée du lot. On l'interroge *avant* de soupçonner quoi que ce soit.

Quand l'autorisation saute malgré tout : Réglages → Confidentialité et sécurité →
Surveillance de la saisie, retirer l'entrée, la remettre, relancer. Trente secondes, à
condition de savoir que c'est ça.

## Utilisation

| Geste | Effet |
|---|---|
| ⌥⌘ + glisser | trace |
| relâcher | la souris revient à l'application testée, immédiatement |
| `Échap` pendant le tracé | annule le trait en cours |
| ⌥⌘Z | supprime le dernier trait posé |

Le menu ◎ de la barre de menus porte l'état du tap, les rapports de mesure, l'activation du
banc C11 et l'export JSON. Son icône reflète l'état réel : gris au repos, bleu quand le
calque est ordonné, **rouge quand le tap est mort**.

## Les trois témoins

Ils ne sont pas interchangeables : chacun couvre un chemin de composition différent du
WindowServer.

| Témoin | Rôle | Lancement |
|---|---|---|
| 1 · page web animée | C3, C3b, C11 — trois modes : horloge, charge, compteur | `./Tools/serve-temoin.sh` |
| 2 · Simulateur iOS | fenêtre à composition accélérée d'un processus tiers, avec ses surfaces Metal | ouvrir le Simulateur, lancer une animation |
| 3 · Terminal avec `top` | rendu texte à cadence lente — le seul où une frame décalée se voit à l'œil nu | `top` dans une fenêtre de terminal |

Deux manipulations s'y ajoutent, sans application dédiée : **le Finder** (glisser un fichier,
pour C6) et **Safari en plein écran natif** (C8).

## Structure

```
Sources/Regarde0/
├── main.swift                     démarrage, observation de l'état système
├── SessionClock.swift             horloge maîtresse — ADR-0007
├── RunReport.swift                export des mesures
├── StatusItemController.swift     barre de menus, état lisible sans lire un journal
├── Permissions/Preflight.swift    T0.3 — préflights, jamais de demande
├── Input/
│   ├── InkRing.swift              ring lock-free SPSC, zéro allocation
│   ├── OptionGate.swift           T0.6 — la porte à verrou, § 6.2
│   └── EventTap.swift             T0.4, T0.8 — tap sur thread dédié, watchdog
├── Overlay/
│   ├── Coordinates.swift          conversions entre espaces — § 3.3
│   ├── OverlayPanel.swift         T0.5 — NSPanel par écran, § 6.1
│   ├── InkView.swift              rendu CAShapeLayer + display link, § 6.4
│   └── OverlayController.swift    ordonnancement à la demande — ADR-0010
├── Metrics/LatencyHistogram.swift T0.7 — instrumentation
└── Bench/SnapshotBench.swift      T0.9 — banc C11
```

## Ce que ce prototype ne fait pas

Volontairement, et il ne faut pas le lui ajouter : pas de flux de capture continu (lot 3),
pas de numérotation ni de badges (lot 2), pas d'ancrage réel à la fenêtre testée — le
rectangle cible vaut `.infinite` (lot 2), pas de voix (lot 5), pas de MCP (lot 6),
pas de rapport (lot 4).

Chaque ajout repousse le moment où l'on saura si le geste fonctionne. C'est le seul risque
que ce lot doit réduire.
