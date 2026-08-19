---
statut: accepté
date: 2026-08-19
décideurs: [Thomas Foutrein]
lot: 3
---

# ADR-0009 — La géométrie normalisée est relative au `contentRect` de la frame retenue

## Contexte

Une marque naît dans un espace de coordonnées et est gravée dans un autre. Trois espaces
cohabitent, et aucun n'est celui du voisin :

| Espace | Origine | Unité |
|---|---|---|
| `CGEvent.location` (le tap, [ADR-0005](0005-cgeventtap-arbitre-unique.md)) | haut-gauche de l'écran principal, global | points |
| Cocoa / `NSScreen` (le calque) | bas-gauche | points |
| Buffer ScreenCaptureKit (l'image gravée) | haut-gauche du `contentRect` **de la frame** | pixels |

La conception initiale posait une conversion unique fondée sur le `contentRect` du
`SCContentFilter`, constant pour toute la session. C'est le point que cet ADR corrige. La
configuration du flux (§ 5.2) impose `cfg.width = Int(frameContentRect.width * pointPixelScale) & ~1`
et `cfg.scalesToFit = false` : les dimensions du buffer sont arrondies au pair inférieur, donc leur
ratio n'est plus exactement celui du display, et comme le flux ne met pas à l'échelle, il **centre**
le contenu dans le buffer au lieu de l'étirer. Un écran externe non-Retina placé à gauche (origine
négative) ajoute une troisième source d'écart.

## Décision

Toute géométrie de marque est normalisée dans `[0,1]` **relativement au `contentRect` de la frame
effectivement retenue**, lu dans les attachements `SCStreamFrameInfo.contentRect` / `.scaleFactor` /
`.contentScale` de cette frame. `FrameRef` porte le `contentRect` et le `scaleFactor` effectifs de sa
frame, et toute `Mark` porte son `CaptureSegmentID`. La rotation portrait et la recopie vidéo sont
refusées explicitement, jamais traitées approximativement.

## Options envisagées

### Option A — Coordonnées en pixels absolus du display
- **Pour** : aucune conversion, aucun type intermédiaire, débogage immédiat (un pixel est un pixel).
- **Contre** : un changement de résolution, un `backingScaleFactor` différent ou une réouverture de
  segment après un `-3821` rendent les coordonnées antérieures ininterprétables. Le chaînage
  « Reprendre le feedback #N » devient impossible dès que la disposition d'écrans a bougé.

### Option B — Normalisation sur le `contentRect` du filtre (constant pour la session)
- **Pour** : une seule conversion, calculée à l'ouverture de session, testable hors flux ; c'était la
  conception initiale.
- **Contre** : le `contentRect` du filtre décrit ce qu'on a **demandé**, pas ce que le compositeur a
  **livré**. L'arrondi `& ~1` casse le ratio et `scalesToFit = false` centre le contenu : le résultat
  est un décalage constant de quelques pixels et des bandes noires sur les bords. Cet écart est petit,
  systématique et proportionnel à rien de visible — il se diagnostique à tort comme un bug d'échelle
  Retina, et on le cherche alors dans la conversion points → pixels, où il n'est pas.

### Option C — Recalage a posteriori par corrélation d'image entre la frame et une capture témoin
- **Pour** : indépendant de ce que ScreenCaptureKit publie.
- **Contre** : coût de calcul par marque hors de proportion, et non déterministe sur un écran qui
  bouge — exactement le cas d'usage qui justifie le produit.

### Option D — Normalisation sur le `contentRect` de la frame retenue (retenue)
- **Pour** : la seule source qui décrit le boîtage réel du contenu dans le buffer ; ScreenCaptureKit
  publie ces attachements par frame précisément parce que ce boîtage varie.
- **Contre** : la géométrie ne peut plus être calculée sans le contexte de sa frame.

## Justification

Apple ne publierait pas `contentRect` et `scaleFactor` **par frame** si le rectangle du filtre
suffisait. Ce que ces attachements décrivent, c'est le résultat de la négociation entre la
configuration demandée et ce que le compositeur peut livrer, et cette négociation change avec
l'arrondi des dimensions, avec `scalesToFit`, et avec les changements d'échelle à chaud.

Le critère de décision n'a pas été la justesse théorique, mais le coût de l'erreur : l'option B
produit un défaut **invisible sur un écran statique et systématique sur un écran animé**, comme le
décalage temporel traité par [ADR-0008](0008-temps-asset-distinct-du-temps-session.md). Le prix payé
pour le lire par frame est une lecture d'attachement sur le chemin d'appariement, déjà propriétaire
de la frame ([ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md)) — négligeable
devant le recadrage et la gravure de la § 5.6.

Le `CaptureSegmentID` sur chaque marque est le corollaire non négociable : après une erreur `-3821`
et une réouverture de segment aux dimensions différentes, les pixels d'une marque antérieure ne sont
plus interprétables sans savoir dans quel segment elle a été posée.

Deux cas sont refusés proprement plutôt que rendus approximativement. **Rotation portrait** : largeur
et hauteur sont inversées entre `CGDisplayBounds` et le buffer, et rien dans les attachements ne dit
laquelle des deux conventions s'applique. **Recopie vidéo** : `SCShareableContent` remonte deux
`SCDisplay` pour une même surface ; sans filtrage par `CGDisplayIsInMirrorSet` /
`CGDisplayMirrorsDisplay`, la marque atterrit sur le mauvais `displayID` et la géométrie est juste
dans un référentiel faux — le pire mode d'échec possible.

## Conséquences

- **Positives** : les coordonnées survivent au changement de résolution, de `backingScaleFactor` et
  de segment, ce qui rend possible le chaînage de sessions et la numérotation stable de
  [ADR-0013](0013-numerotation-definitive-au-mousedown.md) ; `FrameRef` est auto-portant, donc le
  rendu du rapport n'a besoin d'aucun état de session vivante.
- **Négatives** — le prix à payer, assumé : le manifeste grossit d'un `contentRect` et d'un
  `scaleFactor` par `FrameRef`, dupliqués sur les marques d'un même segment ; il n'existe plus de
  fonction utilitaire « pixels → normalisé » appelable hors du contexte d'une frame, ce qui alourdit
  les tests unitaires qui doivent fabriquer un `FrameRef` plausible ; deux configurations matérielles
  légitimes (écran pivoté, vidéoprojecteur en recopie) donnent un refus explicite là où un
  concurrent afficherait un résultat à peu près juste.
- **Ce que ça ferme** : plus de conversion globale de session ; interdiction de graver à partir des
  coordonnées d'événement brutes ; le mode économe demi-résolution du lot 12 ne pourra pas se
  contenter de diviser les coordonnées par deux, il devra passer par un nouveau segment.

## Signal de révision

Sur deux versions majeures consécutives de macOS, si le `contentRect` publié par chaque frame
coïncide au pixel près avec celui du filtre sur l'ensemble du parc de test (Retina, externe
non-Retina à origine négative, changement d'échelle à chaud), la lecture par frame est du code mort
et doit être simplifiée. Inversement, si le `contentRect` se met à varier **en cours de segment**,
`CaptureSegment.pixelSize` cesse d'être une constante du segment et le modèle de données doit être
rouvert.

## Références

- Spécification § 3.3 et § 3.4 (`NormPoint`, `NormRect`, `FrameRef`, `Mark`), § 5.2, § 5.6.
- Lot 3 du plan de lots — point B3, critère C11 du lot 0 (compteur d'images affichant son numéro).
- [ADR-0003](0003-encodage-continu-hevc-plutot-que-ring-buffer-ram.md),
  [ADR-0005](0005-cgeventtap-arbitre-unique.md),
  [ADR-0008](0008-temps-asset-distinct-du-temps-session.md),
  [ADR-0013](0013-numerotation-definitive-au-mousedown.md).
