# Regarde

> Montre à ton IA ce que tu vois, en parlant, sans quitter ton application.

**Regarde** est un compagnon macOS qui reste invisible pendant que tu testes l'application
que ton agent IA vient de coder. Tu traces une flèche sur ce qui cloche, tu dis pourquoi à
voix haute, et l'agent reçoit un rapport où chaque commentaire est collé au bon pixel, au
bon instant.

Il n'y a plus de capture d'écran à recadrer, plus de contexte à retaper, plus de
« le bouton en haut à droite, tu vois ? ».

## Le problème

Quand on développe avec une IA, le coût n'est pas dans la capture d'écran — CleanShot et
Shottr la font très bien. Il est dans le **dernier mètre** : transmettre à l'agent un paquet
exploitable sans sortir du flux de test. Aujourd'hui, cette boucle coûte capture, recadrage,
glisser-déposer, description textuelle de ce qu'on montre, et recontextualisation.

Et pour tout ce qui est animé — une transition, un état de survol, un décalage de 400 ms —
la capture figée ne dit tout simplement rien.

## Le principe

```
⌃⌥S          Session ouverte. L'écran est enregistré en continu en arrière-plan.
             Le micro reste fermé : il ne s'ouvre que le temps de chaque commentaire,
             et la transcription est locale. Rien ne bouge à l'écran.

             Tu testes normalement. Tu cliques, tu navigues, l'app s'anime.

⌥⌘ + glisser Une flèche numérotée ① apparaît par-dessus. Tu relâches, tu recliques
             dans l'app. Elle n'a jamais perdu le focus ni cessé de tourner.

  « ce bouton devrait passer en vert au survol »     → rattaché à ①

⌥⌘ + glisser Un cadre ②.  « et le libellé déborde de deux pixels »   → rattaché à ②

  « globalement les transitions sont trop lentes »   → commentaire global

⌃⌥F          Session fermée. Pour chaque marque, la frame de SON instant est extraite
             du buffer, les repères y sont gravés, le rapport part dans ton projet.
             Le presse-papiers contient déjà la phrase à coller.

Cmd+V ⏎      L'agent lit, voit les repères sur les pixels exacts, et corrige.
```

L'enregistrement démarre **avant** la marque. C'est ce qui permet d'annoter une animation en
cours, et de commenter rétroactivement : « attends, le truc d'il y a trois secondes » reste
exploitable, puisque les images sont déjà dans le buffer.

## Principes de conception

**Universel.** Le noyau ne connaît que des pixels et de la géométrie. Application web,
application native, fenêtre de terminal, simulateur iOS, script en cours d'exécution :
tout ce qui s'affiche à l'écran est capturable. Des greffons optionnels enrichissent le
contexte quand ils reconnaissent la fenêtre — console d'un navigateur, texte d'un terminal —
mais leur absence ne dégrade jamais le fonctionnement de base.

**Agnostique du modèle.** Ni Claude ni GPT ne lisent de vidéo. Le format pivot transmis à
l'IA est donc une séquence d'images horodatées, jamais un fichier vidéo. N'importe quel
agent capable de lire une image et du texte peut exploiter un rapport Regarde.

**Local.** La transcription vocale ne quitte pas la machine.

**Sans rupture de flux.** L'application testée garde le focus et continue de tourner
pendant l'annotation. Aucun mode à mémoriser : on maintient une touche, on trace, on relâche.

## État du projet

Conception terminée, aucune ligne de code applicatif n'est encore écrite. La spécification du
MVP, les vingt-et-une décisions d'architecture et le plan de développement sont rédigés et cohérents
entre eux.

| Document | Contenu | État |
|---|---|---|
| [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md) | Spécification technique du MVP — parcours, architecture, format des artefacts, risques | Version 1.0 |
| [`docs/adr/`](docs/adr/README.md) | Vingt-et-une décisions d'architecture, une par fichier, toutes au statut `accepté` | Complet |
| [`docs/PLAN-DE-DEVELOPPEMENT.md`](docs/PLAN-DE-DEVELOPPEMENT.md) | Découpage en neuf lots, deux GO/NO-GO, calibrage en travail fractionné | Complet |
| `prototypes/` | Prototypes de réduction de risque | Vide |

**Prochaine étape : le lot 0**, le prototype de risque qui porte le premier GO/NO-GO — deux
jours et demi pour établir que le geste fonctionne (`CGEventTap` arbitre, calque au-dessus de
l'application testée, focus jamais perdu) et à quel coût de composition. Ses douze critères et
son découpage en huit séances sont détaillés au § 4 du
[plan de développement](docs/PLAN-DE-DEVELOPPEMENT.md).

## Plateforme

macOS 26 (Tahoe) ou supérieur, Apple Silicon. Swift / SwiftUI, ScreenCaptureKit.
Windows et Linux sont hors périmètre du MVP.
