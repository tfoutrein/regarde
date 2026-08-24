# Feedback #42 — shop-front — 19 août 2026, 14 h 32

Session de test de 2 min 14 s. **3 marques**.
Regarde 0.4.0 (macOS 26.1). Aucune donnée sortie de la machine.

## Comment lire ce rapport

Le développeur a testé son application en la manipulant normalement. Quand quelque chose l'a
gêné, il a maintenu ⌥⌘ et entouré la zone à l'écran : cela a créé une **marque numérotée**.

- Les marques sont dans l'ordre chronologique, pas par importance. Les numéros peuvent
  comporter des trous : une marque supprimée n'est jamais renumérotée.
- **Le texte suffit dans la majorité des cas.** Ne charge une capture que si tu ne sais pas
  quel élément est visé, ou si le problème est purement visuel (alignement, espacement,
  chevauchement). Le chemin absolu et le coût en jetons sont sous chaque marque.
- Quand tu as appliqué ou écarté ces retours, appelle `resolve_feedback(number: 42)`.
  Sans cela, ce feedback te sera re-servi.

## Contexte

| | |
|---|---|
| Projet | `/Users/dev/shop-front` |
| Détection | **certaine** — session Claude Code vivante sur ce répertoire (pid 20378, il y a 12 s) et cwd du shell Warp au premier plan concordant |
| Git | `feat/checkout-coupon` @ `a3f19c2`, 3 fichiers modifiés non commités |
| Application testée | Google Chrome — fenêtre « Panier — Boutique Démo », 1512×982 pt |
| Écran | Display 1, 1728×1117 pt @2×, capture native 3456×2234 px |
| Interruptions | aucune |
| Statut | **nouveau** |

## Marque 1 — 00:21 — `mal aligné`

**Zone entourée** : rectangle 372×72 pt à (988, 806), coin inférieur droit de la carte de
récapitulatif de commande.

**Captures**
- Recadrage : `/Users/dev/shop-front/.regarde/sessions/0042-20260819-1432-checkout/frames/crop-01.png` — 756×532 px, **513 jetons** ← à privilégier
- Fenêtre entière : `/Users/dev/shop-front/.regarde/sessions/0042-20260819-1432-checkout/frames/full-01.png` — 1316×868 px, **1 457 jetons**

## Marque 2 — 01:04 — `à revoir`

**Zone entourée** : rectangle 434×280 pt à (521, 388), champ code promo et son message d'erreur.

**Captures**
- Recadrage : `/Users/dev/shop-front/.regarde/sessions/0042-20260819-1432-checkout/frames/crop-02.png` — 868×560 px, **620 jetons** ← à privilégier
- Fenêtre entière : `/Users/dev/shop-front/.regarde/sessions/0042-20260819-1432-checkout/frames/full-02.png` — 1316×868 px, **1 457 jetons**

## Marque 3 — 01:38 — `ne marche pas`

**Zone entourée** : rectangle 268×44 pt à (1204, 918), ligne « Total TTC ».
**Écran en mouvement à cet instant** : oui — deux frames de contexte disponibles (`-0,8 s`, `+0,4 s`).

**Captures**
- Recadrage : `/Users/dev/shop-front/.regarde/sessions/0042-20260819-1432-checkout/frames/crop-03.png` — 700×448 px, **400 jetons** ← à privilégier

## Commentaires généraux

- aucun.

## Récapitulatif

| Marque | Recadrage | Jetons | Fenêtre entière | Jetons |
|---|---|---|---|---|
| 1 | `crop-01.png` 756×532 | 513 | `full-01.png` 1316×868 | 1 457 |
| 2 | `crop-02.png` 868×560 | 620 | `full-02.png` 1316×868 | 1 457 |
| 3 | `crop-03.png` 700×448 | 400 | `full-03.png` 1316×868 | 1 457 |
| | **Total recadrages** | **1 533** | **Total fenêtres** | **4 371** |

## Suite

1. Applique marque par marque. En cas d'ambiguïté, charge le **recadrage**, pas la fenêtre.
2. Un commit par marque facilite la relecture.
3. Termine par `resolve_feedback(number: 42, status: "handled", note: "…")`.
