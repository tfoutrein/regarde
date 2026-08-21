# Lot 2 — passage du livrable

**Date** : 2026-08-20
**Critère du plan** : « Session de 3 min sur une vraie application : 6 marques, 4 outils, 2 écrans
dont un externe non-Retina **placé à gauche** (origine négative). 6 PNG au bon endroit, bon numéro,
**aucun pixel du calque ni du HUD**, aucun décalage ×2. »

## Ce qui a été exécuté

Session explicite (`⌃⌥S`) sur TextEdit, six marques réparties sur les deux écrans, fermeture par
`⌃⌥F`. Rejouable : `app/Tools/lot2-livrable.sh`.

| Écran | Échelle | Origine (espace événement) | Marques |
|---|---|---|---|
| display 1 | @2× | (0, 0) | 1 flèche, 2 cadre, 3 point |
| display 3 | @1× | (−971, −1440) | 4 surlignage, 5 flèche, 6 cadre |

L'écran externe est **au-dessus et à gauche** du principal, donc à coordonnées négatives sur les
deux axes, et à une échelle différente. C'est la disposition qui casse un code supposant un
facteur global, et elle est ici la disposition réelle du poste.

## Résultat

```
1 · flèche     sur display 1 — bbox (0.174, 0.669) 0.116×0.063
2 · cadre      sur display 1 — bbox (0.174, 0.552) 0.116×0.063
3 · point      sur display 1 — bbox (0.220, 0.499) 0.000×0.000
4 · surlignage sur display 3 — bbox (0.108, 0.715) 0.058×0.049
5 · flèche     sur display 3 — bbox (0.108, 0.625) 0.058×0.049
6 · cadre      sur display 3 — bbox (0.108, 0.535) 0.058×0.049
```

Six PNG dans `~/Regarde/sessions/2026-08-20_19-13-03/frames/`, toutes dimensions multiples de 28 :
896×308, 896×308, 644×644, 644×224, 644×252, 644×252.

| Point du critère | Verdict | Comment il a été établi |
|---|---|---|
| 6 marques | ✅ | six fichiers, numéros 1 à 6 sans trou |
| 4 outils | ✅ | flèche, cadre, point, surlignage, chacun dans son mode de peinture |
| 2 écrans, dont un externe à origine négative | ✅ | display 1 @2× et display 3 @1× à (−971, −1440) |
| PNG au bon endroit, bon numéro | ✅ | `marque-01` à `marque-06`, gravure conforme au journal |
| Aucun pixel du calque ni du HUD | ✅ | voir ci-dessous |
| Aucun décalage ×2 | ✅ | les marques de display 3 sont centrées dans leur recadrage |

## Ce qui rend la mesure de R12 concluante

Ce n'est pas « je n'ai rien vu ». Sur `marque-06`, tracée en dernier, **les cinq marques
précédentes étaient affichées à l'écran** au moment où la capture est partie — dont la marque 5,
distante de 130 px, donc géométriquement dans le champ du recadrage. Aucune n'apparaît dans
l'image. Le calque était visible, il n'a rien laissé.

La mesure quantitative complète (`app/Tools/lot2-cible.sh`) donne 670 pixels vermillon dans la
région cible avec quatre marques affichées, contre 670 sur la scène nue — au pixel près.

## Validation par recette manuelle — 21 août 2026

Le passage automatisé ci-dessus prouvait que la chaîne fonctionne. Il ne prouvait pas que le
produit tient en main. **Soixante-quatre tests manuels** l'ont vérifié, tous cochés par l'auteur.

Ils ont trouvé **onze défauts** qu'aucun scénario automatisé n'avait vus, et dont plusieurs
auraient rendu le produit inutilisable :

| Défaut | Ce qu'il produisait |
|---|---|
| `dict[key] = nil` supprime la clé en Swift | une marque sans intention n'était **jamais gravée** — le cas majoritaire du mode éclair |
| Deux algorithmes de placement du badge | le numéro sautait d'un endroit à l'autre entre l'écran et l'image |
| Recadrage centré sur le trait | ce que la flèche désigne se retrouvait sur un bord, souvent coupé |
| Facteur d'échelle mêlant réduction et rognage | forme gravée jusqu'à 18 % trop courte sur un recadrage non carré |
| Plafond de 896 px sur le côté long | 128 tuiles dépensées sur les 1568 du palier, texte au quart de sa taille |
| Épaisseur et diamètre calculés sur le côté long | trait un tiers trop épais, badge deux fois trop gros |
| Halo ajouté autour du trait | épaisseur perçue triplée, cadre collé au texte |
| Cible = premier morceau de fenêtre listé | **Warp inannotable** : la cible était sa barre d'onglets de 44 px |
| Vue gelée ignorant les ordres de dessin | les marques publiées ressurgissaient au ré-armement |
| Pot de captures vidé avant la gravure | « 1 marque, 0 image », sans erreur |
| `⌘Z` nu intercepté en permanence | **le raccourci le plus utilisé de macOS volé à l'application testée** |

Deux d'entre eux venaient de corrections faites la veille : un correctif peut en casser un autre,
et seul l'usage le révèle.

**Une décision de conception a été renversée** par l'usage : `⌥⌘Z` rend désormais son numéro
([ADR-0013](../adr/0013-numerotation-definitive-au-mousedown.md) révisé). L'argument décisif était
que `Échap` et `⌥⌘Z` font la même chose du point de vue de l'utilisateur, et que l'un rendait le
numéro quand l'autre le retenait.

**Deux ajouts** sont nés de la recette : une **vue d'ensemble** par écran, qui situe les marques
les unes par rapport aux autres, et un **journal formaté** en trois colonnes, avec démarcation à
chaque session.

**La recette elle-même a dû être refaite.** Un audit multi-agents l'a confrontée au code : sur
37 tests, **43 problèmes** — des comportements décrits à l'envers, des lignes de journal illisibles
au moment où on les demandait, des gestes sans rien à observer. Elle est passée à 64 tests, chacun
nommant ce qu'on regarde et où, et un générateur la produit désormais depuis sa source Markdown.

## Ce qui reste ouvert

- **S16** — Developer ID et notarisation, reporté faute de compte Apple Developer payant. Le lot 8
  en dépend.
- **Dette du lot 0** — C6c à la main, C12 avec Karabiner, C3b en plein écran. Trois mesures qui
  demandent une manipulation physique.
- **Durée** — le scénario automatisé dure moins de trois minutes. Le critère substantiel (six
  marques, quatre outils, deux écrans) est atteint ; la durée reste à confirmer par une session
  humaine réelle, qui est de toute façon le vrai juge du lot 3.
